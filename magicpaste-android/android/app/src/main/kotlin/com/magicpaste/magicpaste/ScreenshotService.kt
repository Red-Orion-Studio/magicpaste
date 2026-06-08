package com.magicpaste.magicpaste

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Persistent foreground service — the reliable background engine on MIUI/EMUI.
 *
 * WorkManager's content-URI trigger silently stops firing once the app is
 * backgrounded on these OEMs (verified on Xiaomi: the worker only runs again
 * when the app is reopened). Keeping a live process with an ongoing
 * notification + a [ContentObserver] on MediaStore makes a new screenshot get
 * sent within ~1s even with the app fully closed.
 *
 * This is OPT-IN: only started when the user enables "Always-on detection"
 * (KEY_GUARANTEED). It is purely event-driven — a ContentObserver costs no CPU
 * while idle, so the battery impact is negligible (the visible cost is the
 * ongoing notification Android requires). No polling loop.
 *
 * START_STICKY + Autostart + "no battery restriction" is what keeps it alive.
 * All the actual scan/send work is reused from [ScreenshotScanner].
 */
class ScreenshotService : Service() {

    companion object {
        private const val TAG = "MagicPaste"
        const val CHANNEL_ID = "magicpaste_service"
        const val NOTIF_ID = 4242
        private const val DEBOUNCE_MS = 700L

        fun start(context: Context) {
            val intent = Intent(context, ScreenshotService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Android 12+ forbids starting a dataSync FGS from some
                // background contexts (e.g. boot). The next app open / periodic
                // worker will start it; don't crash the caller.
                Log.w(TAG, "ScreenshotService.start refused: ${e.message}")
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ScreenshotService::class.java))
        }
    }

    private lateinit var workerThread: HandlerThread
    private lateinit var bgHandler: Handler
    private var observer: ContentObserver? = null
    @Volatile private var pendingScan = false

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        startForegroundCompat()
        workerThread = HandlerThread("mp-scan").apply { start() }
        bgHandler = Handler(workerThread.looper)
        registerObserver()
        bgHandler.post { runScan() } // initial catch-up
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Stop ourselves if auto-send was turned off, the user disabled
        // always-on mode, or the device was unpaired.
        val prefs = getSharedPreferences(ScreenshotScanner.PREFS, Context.MODE_PRIVATE)
        val auto = prefs.getBoolean(SyncWorker.KEY_AUTO, false)
        val guaranteed = prefs.getBoolean(SyncWorker.KEY_GUARANTEED, false)
        val host = prefs.getString(ScreenshotScanner.KEY_HOST, null)
        if (!auto || !guaranteed || host.isNullOrEmpty()) {
            Log.i(TAG, "Service: not needed (auto/guaranteed/host), stopping")
            stopSelf()
            return START_NOT_STICKY
        }
        // Re-scan on every (re)start command — covers the restart-after-kill case.
        if (::bgHandler.isInitialized) bgHandler.post { runScan() }
        return START_STICKY
    }

    private fun registerObserver() {
        observer = object : ContentObserver(bgHandler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                // MediaStore fires several events per save — debounce so we
                // scan once, shortly after the file has settled.
                if (pendingScan) return
                pendingScan = true
                bgHandler.postDelayed({
                    pendingScan = false
                    runScan()
                }, DEBOUNCE_MS)
            }
        }
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, observer!!,
        )
    }

    private fun runScan() {
        try {
            val n = ScreenshotScanner.scanAndSend(applicationContext)
            if (n > 0) Log.i(TAG, "Service sent $n screenshot(s)")
        } catch (e: Exception) {
            Log.e(TAG, "Service scan failed", e)
        }
    }

    private fun startForegroundCompat() {
        val notif = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun buildNotification(): Notification {
        val tap = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        val pi = PendingIntent.getActivity(
            this, 0, tap,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        // "Desactivar" action -> turns off always-on mode and stops the service.
        val stopIntent = Intent(this, NotificationActionReceiver::class.java).apply {
            action = NotificationActionReceiver.ACTION_STOP
        }
        val stopPi = PendingIntent.getBroadcast(
            this, 1, stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setContentTitle("MagicPaste")
            .setContentText(Strings.t(this, "notif_ready"))
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pi)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                Strings.t(this, "notif_turn_off"), stopPi,
            )
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID, "MagicPaste", NotificationManager.IMPORTANCE_LOW,
                ).apply { description = Strings.t(this@ScreenshotService, "channel_desc") }
            )
        }
    }

    override fun onDestroy() {
        observer?.let { contentResolver.unregisterContentObserver(it) }
        if (::bgHandler.isInitialized) bgHandler.removeCallbacksAndMessages(null)
        if (::workerThread.isInitialized) workerThread.quitSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
