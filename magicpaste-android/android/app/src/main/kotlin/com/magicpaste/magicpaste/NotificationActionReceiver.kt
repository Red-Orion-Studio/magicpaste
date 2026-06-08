package com.magicpaste.magicpaste

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Handles the "Desactivar" action on the always-on service notification.
 *
 * Turns off always-on mode (so the service won't be re-spawned by the worker /
 * boot receiver) and stops the running [ScreenshotService]. Writes the same
 * pref the Flutter "Always-on detection" toggle reads, so the UI stays in sync.
 * Auto-send itself stays on — the app just drops back to the lightweight
 * WorkManager path.
 */
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_STOP) return
        Log.i("MagicPaste", "Always-on disabled from notification")
        context.getSharedPreferences(ScreenshotScanner.PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(SyncWorker.KEY_GUARANTEED, false)
            .apply()
        ScreenshotService.stop(context)
    }

    companion object {
        const val ACTION_STOP = "com.magicpaste.magicpaste.STOP_ALWAYS_ON"
    }
}
