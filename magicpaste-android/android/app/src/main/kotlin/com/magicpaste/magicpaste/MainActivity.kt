package com.magicpaste.magicpaste

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter UI <-> native WorkManager scheduler.
 *
 *   enableAutoSync  -> arm URI trigger + periodic safety net
 *   disableAutoSync -> cancel both
 *   runOnce         -> fire a one-shot SyncWorker immediately
 *
 * Everything routes through [SyncScheduler], which only uses
 * WorkManager. No Service.startForegroundService() calls — those would
 * trip Android 12+'s background launch restrictions when invoked from
 * the periodic worker / boot receiver path.
 */
class MainActivity : FlutterActivity() {
    private val channel = "magicpaste/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableAutoSync" -> {
                        val prefs = getSharedPreferences(SyncWorker.PREFS, MODE_PRIVATE)
                        prefs.edit().putBoolean(SyncWorker.KEY_AUTO, true).apply()
                        // WorkManager URI trigger is the lightweight default
                        // (no persistent notification). Only spin up the
                        // always-on service if the user opted in.
                        SyncScheduler.enable(applicationContext)
                        if (prefs.getBoolean(SyncWorker.KEY_GUARANTEED, false)) {
                            ScreenshotService.start(applicationContext)
                        }
                        result.success(true)
                    }
                    "disableAutoSync" -> {
                        getSharedPreferences(SyncWorker.PREFS, MODE_PRIVATE)
                            .edit()
                            .putBoolean(SyncWorker.KEY_AUTO, false)
                            .apply()
                        ScreenshotService.stop(applicationContext)
                        SyncScheduler.disable(applicationContext)
                        result.success(true)
                    }
                    "setGuaranteedBg" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val prefs = getSharedPreferences(SyncWorker.PREFS, MODE_PRIVATE)
                        prefs.edit().putBoolean(SyncWorker.KEY_GUARANTEED, enabled).apply()
                        // Reflect immediately if auto-send is already on.
                        val auto = prefs.getBoolean(SyncWorker.KEY_AUTO, false)
                        if (auto && enabled) {
                            ScreenshotService.start(applicationContext)
                        } else if (!enabled) {
                            ScreenshotService.stop(applicationContext)
                        }
                        result.success(true)
                    }
                    "runOnce" -> {
                        SyncScheduler.runOnce(applicationContext)
                        result.success(true)
                    }
                    "getDeviceName" -> {
                        result.success(deviceName())
                    }
                    "isXiaomi" -> {
                        result.success(isXiaomi())
                    }
                    "openAutostart" -> {
                        openAutostart(); result.success(true)
                    }
                    "openBattery" -> {
                        openBattery(); result.success(true)
                    }
                    "openAppDetails" -> {
                        tryStart(appDetailsIntent()); result.success(true)
                    }
                    "beep" -> {
                        beep(); result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Short confirmation beep (same as the background sender's). */
    private fun beep() {
        try {
            val tg = android.media.ToneGenerator(
                android.media.AudioManager.STREAM_NOTIFICATION, 70,
            )
            tg.startTone(android.media.ToneGenerator.TONE_PROP_BEEP, 150)
            android.os.Handler(android.os.Looper.getMainLooper())
                .postDelayed({ try { tg.release() } catch (e: Exception) {} }, 350)
        } catch (e: Exception) {
        }
    }

    private fun isXiaomi(): Boolean {
        val m = (Build.MANUFACTURER ?: "").lowercase()
        val b = (Build.BRAND ?: "").lowercase()
        return listOf("xiaomi", "redmi", "poco").any { m.contains(it) || b.contains(it) }
    }

    /** Try each intent in order; return on the first that launches. */
    private fun tryStart(vararg intents: Intent): Boolean {
        for (i in intents) {
            try {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                return true
            } catch (e: Exception) {
                // not available on this build — fall through to the next
            }
        }
        return false
    }

    private fun appDetailsIntent(): Intent =
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )

    /** Open MIUI's Autostart manager, falling back to the app's details page. */
    private fun openAutostart() {
        val miui = Intent().setComponent(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            )
        )
        tryStart(miui, appDetailsIntent())
    }

    /** Open MIUI's per-app power settings / battery-optimisation, then app details. */
    private fun openBattery() {
        val miuiPower = Intent().setComponent(
            ComponentName(
                "com.miui.powerkeeper",
                "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
            )
        ).putExtra("package_name", packageName)
            .putExtra("package_label", "MagicPaste")
        val ignoreOpt = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        tryStart(miuiPower, ignoreOpt, appDetailsIntent())
    }

    /** The user-set device name (e.g. "Héctor's phone"), or brand + model. */
    private fun deviceName(): String {
        val custom = try {
            Settings.Global.getString(contentResolver, "device_name")
        } catch (e: Exception) {
            null
        }
        if (!custom.isNullOrBlank()) return custom.trim()
        val mk = (Build.MANUFACTURER ?: "").trim()
        val md = (Build.MODEL ?: "Android").trim()
        return (if (md.startsWith(mk, ignoreCase = true) || mk.isEmpty()) md else "$mk $md").trim()
    }
}
