package com.magicpaste.magicpaste

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms the WorkManager jobs after a device reboot or an app update —
 * WorkManager does NOT restore them automatically. Calls only into
 * [SyncScheduler]; never touches Service.start* APIs directly because
 * BroadcastReceiver context on Android 12+ cannot start a foreground
 * service reliably (the exemption is narrow and OEM-dependent).
 *
 * Uses goAsync() so the OS keeps the process alive long enough to
 * re-enqueue both unique works before the receiver is destroyed.
 */
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }

        val pendingResult = goAsync()
        try {
            val prefs = context.getSharedPreferences(
                SyncWorker.PREFS, Context.MODE_PRIVATE,
            )
            val autoEnabled = prefs.getBoolean(SyncWorker.KEY_AUTO, false)
            val bootEnabled = prefs.getBoolean(SyncWorker.KEY_BOOT, true)
            val host = prefs.getString(SyncWorker.KEY_HOST, null)
            if (autoEnabled && bootEnabled && !host.isNullOrEmpty()) {
                // Always re-arm the lightweight WorkManager jobs.
                SyncScheduler.enable(context)
                // Only bring the always-on service back if the user opted in.
                // On Android 12+ a dataSync FGS start from BOOT may be refused —
                // ScreenshotService.start() swallows that; the WorkManager jobs
                // and the next app open cover the gap.
                if (prefs.getBoolean(SyncWorker.KEY_GUARANTEED, false)) {
                    ScreenshotService.start(context)
                }
            }
        } finally {
            pendingResult.finish()
        }
    }
}
