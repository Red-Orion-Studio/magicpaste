package com.magicpaste.magicpaste

import android.content.Context
import java.util.Locale

/**
 * Localized strings for native notifications. Reads the same language override
 * the Flutter UI writes (flutter.mp_lang: 'system' | 'en' | 'es'); 'system'
 * follows the device locale (Spanish -> es, otherwise en).
 */
object Strings {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_LANG = "flutter.mp_lang"

    fun lang(context: Context): String {
        val mode = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_LANG, "system") ?: "system"
        if (mode == "en" || mode == "es") return mode
        return if (Locale.getDefault().language.startsWith("es")) "es" else "en"
    }

    fun t(context: Context, key: String): String {
        val e = S[key] ?: return key
        return e[lang(context)] ?: e["en"] ?: key
    }

    private val S = mapOf(
        "notif_ready" to mapOf(
            "en" to "Ready — sending screenshots to your PC",
            "es" to "Listo — enviando capturas a tu PC",
        ),
        "notif_searching" to mapOf(
            "en" to "Looking for screenshots…",
            "es" to "Buscando capturas…",
        ),
        "notif_turn_off" to mapOf(
            "en" to "Turn off",
            "es" to "Desactivar",
        ),
        "channel_desc" to mapOf(
            "en" to "Watching for screenshots",
            "es" to "Vigilando capturas",
        ),
    )
}
