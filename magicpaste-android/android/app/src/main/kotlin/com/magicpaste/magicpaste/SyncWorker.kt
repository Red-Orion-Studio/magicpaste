package com.magicpaste.magicpaste

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The one and only background engine.
 *
 * WorkManager invokes this worker via the URI trigger (instant, fires
 * within seconds of a new screenshot appearing in MediaStore) and via
 * the 6h periodic safety net. Inside doWork the worker promotes itself
 * to a foreground service through [setForeground] — the only path
 * Android 12+ still permits for "start FGS while in background", and
 * the reason we deliberately route everything through WorkManager
 * instead of calling Service.startForegroundService() directly.
 *
 * At the end of every run the worker re-arms the URI trigger, so a
 * single fire is enough to keep the chain alive indefinitely.
 */
class SyncWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "MagicPaste"
        const val CHANNEL_ID = "magicpaste_service"
        // Distinct from ScreenshotService's 4242 so a brief worker run doesn't
        // clobber the persistent service's ongoing notification.
        const val NOTIF_ID = 4243
        const val PREFS = ScreenshotScanner.PREFS
        const val KEY_HOST = ScreenshotScanner.KEY_HOST
        const val KEY_AUTO = "flutter.mp_auto_enabled"
        // "Always-on detection" opt-in: run the persistent ScreenshotService.
        const val KEY_GUARANTEED = "flutter.mp_guaranteed_bg"
        // "Auto-start on boot" toggle (default on).
        const val KEY_BOOT = "flutter.mp_boot"
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        ensureChannel(applicationContext)
        val notif: Notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setContentTitle("MagicPaste")
            .setContentText(Strings.t(applicationContext, "notif_searching"))
            .setOngoing(true)
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIF_ID, notif)
        }
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val autoEnabled = prefs.getBoolean(KEY_AUTO, false)
        val host = prefs.getString(KEY_HOST, null)
        if (!autoEnabled || host.isNullOrEmpty()) {
            // Auto-sync was disabled or the user unpaired — finish
            // cleanly without re-arming so we don't loop forever.
            Log.i(TAG, "Worker: auto disabled / unpaired, exiting")
            return@withContext Result.success()
        }

        // Promote to foreground service for the duration of this run.
        // Wrapped in try/catch because a handful of edge launch contexts
        // refuse the promotion — better to scan in plain-worker priority
        // than fail entirely.
        try {
            setForeground(getForegroundInfo())
        } catch (e: Exception) {
            Log.w(TAG, "setForeground refused; continuing in background priority", e)
        }

        try {
            val n = ScreenshotScanner.scanAndSend(applicationContext)
            if (n > 0) Log.i(TAG, "Worker scan sent $n screenshot(s)")
        } catch (e: Exception) {
            Log.e(TAG, "Worker scan failed", e)
        }

        // Self-heal: if the user opted into always-on mode, make sure the
        // persistent ContentObserver service is up (the OEM may have killed
        // it). Idempotent — onStartCommand just re-scans if already running.
        // In the default lightweight mode this worker IS the engine, so we
        // don't spawn the service.
        if (prefs.getBoolean(KEY_GUARANTEED, false)) {
            ScreenshotService.start(applicationContext)
        }

        // Re-arm the URI trigger so the next screenshot kicks us again
        // without waiting for the 6h periodic. WorkManager's unique-work
        // policy dedupes if multiple paths try to re-arm concurrently.
        SyncScheduler.scheduleUriTrigger(applicationContext)

        Result.success()
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "MagicPaste",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { description = Strings.t(context, "channel_desc") }
            )
        }
    }
}
