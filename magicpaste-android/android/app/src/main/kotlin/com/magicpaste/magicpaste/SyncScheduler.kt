package com.magicpaste.magicpaste

import android.content.Context
import android.provider.MediaStore
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Pure-WorkManager background scheduling for MagicPaste.
 *
 *  - URI trigger (one-time, re-armed by [SyncWorker] at the end of
 *    every run): fires within ~2-10s of a new screenshot showing up
 *    in MediaStore. This is what gives the app its instant feel
 *    without needing a persistent Service.
 *  - 6h periodic: safety net for anything the URI trigger missed
 *    (process killed mid-flight, OEM suppressing content updates,
 *    Doze edge cases).
 *
 * Both run as [SyncWorker]. We deliberately avoid Service.start* APIs
 * from any background entry point (BootReceiver, periodic worker)
 * because Android 12+ blocks foreground-service starts from background
 * — [CoroutineWorker.setForeground] is the only path the platform
 * exempts, and it lives inside the worker.
 */
object SyncScheduler {
    const val PERIODIC_NAME = "magicpaste_periodic"
    const val URI_TRIGGER_NAME = "magicpaste_uri"
    const val ONESHOT_NAME = "magicpaste_oneshot"

    fun enable(context: Context) {
        scheduleUriTrigger(context)
        schedulePeriodic(context)
    }

    fun disable(context: Context) {
        val wm = WorkManager.getInstance(context)
        wm.cancelUniqueWork(PERIODIC_NAME)
        wm.cancelUniqueWork(URI_TRIGGER_NAME)
        wm.cancelUniqueWork(ONESHOT_NAME)
    }

    /** Fire a one-shot scan immediately — used by the Flutter "runOnce"
     *  MethodChannel and useful for the user's "sync now" button. */
    fun runOnce(context: Context) {
        val request = OneTimeWorkRequestBuilder<SyncWorker>().build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            ONESHOT_NAME, ExistingWorkPolicy.REPLACE, request,
        )
    }

    /**
     * Schedules (or replaces) the URI-trigger one-shot. Called both
     * from [enable] and from [SyncWorker.doWork] so the trigger chain
     * always has exactly one entry pending.
     */
    fun scheduleUriTrigger(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .addContentUriTrigger(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true,
            )
            .setTriggerContentUpdateDelay(2, TimeUnit.SECONDS)
            .setTriggerContentMaxDelay(10, TimeUnit.SECONDS)
            .build()
        val request = OneTimeWorkRequestBuilder<SyncWorker>()
            .setConstraints(constraints)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            URI_TRIGGER_NAME, ExistingWorkPolicy.REPLACE, request,
        )
    }

    private fun schedulePeriodic(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val request = PeriodicWorkRequestBuilder<SyncWorker>(6, TimeUnit.HOURS)
            .setConstraints(constraints)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC_NAME, ExistingPeriodicWorkPolicy.KEEP, request,
        )
    }
}
