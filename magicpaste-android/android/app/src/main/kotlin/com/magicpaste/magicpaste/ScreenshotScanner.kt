package com.magicpaste.magicpaste

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/**
 * Shared screenshot scan + send logic, invoked from [SyncWorker] (the
 * single background engine — driven by MediaStore URI triggers + a 6h
 * periodic safety net).
 *
 * Idempotent via a persisted watermark (last sent DATE_ADDED) plus a
 * set of already-sent IDs, so nothing is ever sent twice even if the
 * worker is killed mid-run and retried by WorkManager.
 */
object ScreenshotScanner {
    private const val TAG = "MagicPaste"
    const val PREFS = "FlutterSharedPreferences"
    const val KEY_HOST = "flutter.paired_host"
    const val KEY_PORT = "flutter.paired_port"
    const val KEY_TOKEN = "flutter.paired_token"
    // Image quality (Flutter ImageQuality enum index): 0=Low, 1=Medium, 2=High.
    const val KEY_QUALITY = "flutter.mp_quality"
    // Play a short beep after each successful send (default on).
    const val KEY_SOUND = "flutter.mp_sound"
    const val KEY_WATERMARK = "flutter.mp_last_sent_ms"
    // Native-owned (no "flutter." prefix). Flutter's shared_preferences
    // plugin serialises lists as Base64-wrapped Strings prefixed with a
    // marker, so reading them as a native getStringSet() throws
    // ClassCastException. Keeping the sent-ids set on a Kotlin-only key
    // means the Worker can use native APIs without that mismatch.
    const val KEY_SENT_IDS = "native_sent_ids"
    // Sent-history list the Flutter UI reads (services/sent_history.dart).
    // Stored as a JSON string under a simple String key, which IS compatible
    // across Flutter shared_preferences and native getString/putString.
    const val KEY_HISTORY = "flutter.mp_sent_history"
    private const val MAX_HISTORY = 50

    @Volatile
    private var busy = false

    /** Scan for new screenshots and send them. Returns number sent. */
    @Synchronized
    fun scanAndSend(context: Context): Int {
        if (busy) return 0
        busy = true
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val host = prefs.getString(KEY_HOST, null)
            if (host.isNullOrEmpty()) {
                Log.i(TAG, "scanAndSend: not paired, skipping")
                return 0
            }
            val port = readInt(prefs, KEY_PORT, MagicPasteProtocol.DEFAULT_PORT)
            val token = MagicPasteProtocol.tokenFromHex(prefs.getString(KEY_TOKEN, null))
            val quality = readInt(prefs, KEY_QUALITY, 2) // default High
            val sound = prefs.getBoolean(KEY_SOUND, true)
            var watermark = readLong(prefs, KEY_WATERMARK, System.currentTimeMillis())
            val sentIds = (prefs.getStringSet(KEY_SENT_IDS, emptySet()) ?: emptySet()).toMutableSet()

            val shots = queryNewScreenshots(context, watermark)
            Log.i(TAG, "scanAndSend: ${shots.size} candidate(s) since $watermark")
            var sent = 0
            for (shot in shots) {
                if (sentIds.contains(shot.id.toString())) continue
                val raw = readBytes(context, shot.id) ?: continue
                val enc = encodeForQuality(raw, shot.width, shot.height, shot.isPng, quality)
                val ok = MagicPasteProtocol.sendImage(
                    host = host,
                    port = port,
                    raw = enc.bytes,
                    imageFormat = enc.format,
                    width = enc.width,
                    height = enc.height,
                    token = token,
                )
                Log.i(TAG, "scanAndSend: sent id=${shot.id} -> $ok")
                if (ok) {
                    sent++
                    sentIds.add(shot.id.toString())
                    if (shot.dateAddedMs > watermark) watermark = shot.dateAddedMs
                    prefs.edit()
                        .putLong(KEY_WATERMARK, watermark)
                        .putStringSet(KEY_SENT_IDS, trim(sentIds))
                        .apply()
                    // Record in the history the Flutter UI shows.
                    addHistory(prefs, shot, raw)
                    if (sound) playConfirmation()
                }
            }
            return sent
        } catch (e: Exception) {
            Log.e(TAG, "scanAndSend error", e)
            return 0
        } finally {
            busy = false
        }
    }

    private data class Shot(
        val id: Long,
        val width: Int,
        val height: Int,
        val isPng: Boolean,
        val dateAddedMs: Long,
        val name: String = "screenshot.png",
    )

    /** Prepend a sent item to the Flutter-visible history JSON (newest first). */
    private fun addHistory(prefs: android.content.SharedPreferences, shot: Shot, raw: ByteArray) {
        try {
            val arr = try {
                JSONArray(prefs.getString(KEY_HISTORY, "[]") ?: "[]")
            } catch (e: Exception) {
                JSONArray()
            }
            val item = JSONObject().apply {
                put("name", shot.name)
                put("w", shot.width)
                put("h", shot.height)
                put("ok", true)
                put("ts", System.currentTimeMillis())
                makeThumbB64(raw)?.let { put("thumb", it) }
            }
            // newest first
            val out = JSONArray()
            out.put(item)
            var count = 1
            var i = 0
            while (i < arr.length() && count < MAX_HISTORY) {
                out.put(arr.get(i)); i++; count++
            }
            prefs.edit().putString(KEY_HISTORY, out.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "addHistory error", e)
        }
    }

    /** Small JPEG thumbnail (base64) for the UI preview, downsampled cheaply. */
    private fun makeThumbB64(raw: ByteArray): String? {
        return try {
            // Decode bounds first to pick a sample size (avoid loading full image).
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
            val target = 240
            var sample = 1
            var w = bounds.outWidth
            while (w / 2 >= target) { w /= 2; sample *= 2 }
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            val bmp = BitmapFactory.decodeByteArray(raw, 0, raw.size, opts) ?: return null
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 70, out)
            bmp.recycle()
            Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }

    /** Short confirmation beep on the notification stream (best-effort). */
    private fun playConfirmation() {
        try {
            val tg = android.media.ToneGenerator(
                android.media.AudioManager.STREAM_NOTIFICATION, 70,
            )
            tg.startTone(android.media.ToneGenerator.TONE_PROP_BEEP, 150)
            android.os.Handler(android.os.Looper.getMainLooper())
                .postDelayed({ try { tg.release() } catch (e: Exception) {} }, 350)
        } catch (e: Exception) {
            // Some devices throw if audio is unavailable — ignore.
        }
    }

    private class Encoded(val bytes: ByteArray, val format: Int, val width: Int, val height: Int)

    /**
     * Apply the user's quality choice before sending:
     *   High (2)   -> original bytes, untouched (lossless PNG screenshots).
     *   Medium (1) -> full-resolution JPEG q85 (smaller, slight artifacts).
     *   Low (0)    -> downscaled to ~1280px longest side, JPEG q70.
     * Falls back to the original bytes if decoding fails.
     */
    private fun encodeForQuality(
        raw: ByteArray, origW: Int, origH: Int, isPng: Boolean, quality: Int,
    ): Encoded {
        val origFormat = if (isPng) MagicPasteProtocol.IMG_PNG else MagicPasteProtocol.IMG_JPEG
        if (quality >= 2) return Encoded(raw, origFormat, origW, origH)
        return try {
            var bmp = BitmapFactory.decodeByteArray(raw, 0, raw.size, BitmapFactory.Options())
                ?: return Encoded(raw, origFormat, origW, origH)
            val jpegQ = if (quality <= 0) 70 else 85
            val maxDim = if (quality <= 0) 1280 else 0
            if (maxDim > 0) {
                val longest = maxOf(bmp.width, bmp.height)
                if (longest > maxDim) {
                    val scale = maxDim.toFloat() / longest
                    val scaled = Bitmap.createScaledBitmap(
                        bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true,
                    )
                    if (scaled != bmp) { bmp.recycle(); bmp = scaled }
                }
            }
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, jpegQ, out)
            val w = bmp.width
            val h = bmp.height
            bmp.recycle()
            Encoded(out.toByteArray(), MagicPasteProtocol.IMG_JPEG, w, h)
        } catch (e: Exception) {
            Log.e(TAG, "encodeForQuality failed", e)
            Encoded(raw, origFormat, origW, origH)
        }
    }

    private fun queryNewScreenshots(context: Context, sinceMs: Long): List<Shot> {
        val out = mutableListOf<Shot>()
        val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.RELATIVE_PATH,
            MediaStore.Images.Media.DISPLAY_NAME,
        )
        val sinceSec = sinceMs / 1000
        val selection = "${MediaStore.Images.Media.DATE_ADDED} > ?"
        val args = arrayOf(sinceSec.toString())
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} ASC"

        context.contentResolver.query(uri, projection, selection, args, sortOrder)?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val wCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val hCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            val mimeCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)
            val dateCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            val pathCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.RELATIVE_PATH)
            val nameCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            while (c.moveToNext()) {
                val path = (c.getString(pathCol) ?: "").lowercase()
                val rawName = c.getString(nameCol) ?: "screenshot.png"
                val name = rawName.lowercase()
                val isScreenshot = path.contains("screenshot") ||
                    path.contains("captura") ||
                    name.contains("screenshot") ||
                    name.contains("captura")
                if (!isScreenshot) continue
                val mime = (c.getString(mimeCol) ?: "").lowercase()
                out.add(
                    Shot(
                        id = c.getLong(idCol),
                        width = c.getInt(wCol),
                        height = c.getInt(hCol),
                        isPng = mime.contains("png"),
                        dateAddedMs = c.getLong(dateCol) * 1000,
                        name = rawName,
                    )
                )
            }
        }
        return out
    }

    private fun readBytes(context: Context, id: Long): ByteArray? {
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
        return try {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            Log.e(TAG, "readBytes error id=$id", e)
            null
        }
    }

    private fun trim(ids: MutableSet<String>): Set<String> {
        if (ids.size <= 200) return ids
        return ids.toList().takeLast(200).toSet()
    }

    private fun readInt(prefs: android.content.SharedPreferences, key: String, def: Int): Int =
        try {
            prefs.getInt(key, def)
        } catch (e: ClassCastException) {
            prefs.getLong(key, def.toLong()).toInt()
        }

    private fun readLong(prefs: android.content.SharedPreferences, key: String, def: Long): Long =
        try {
            prefs.getLong(key, def)
        } catch (e: ClassCastException) {
            prefs.getInt(key, def.toInt()).toLong()
        }
}
