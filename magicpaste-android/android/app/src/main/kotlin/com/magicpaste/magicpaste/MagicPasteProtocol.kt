package com.magicpaste.magicpaste

import java.io.BufferedOutputStream
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Native (Kotlin) implementation of the MagicPaste wire protocol, mirroring
 * magicpaste-windows/protocol.py and lib/services/protocol.dart.
 *
 * Header (32 bytes, big-endian):
 *   0-3   magic 0x534E4150 ("SNAP")
 *   4-7   message type (uint32)
 *   8-11  payload length (uint32)
 *   12-15 reserved (0)
 *   16-31 auth token (16 bytes; zeros when none)
 *
 * IMAGE payload prefix (12 bytes) + raw bytes:
 *   0-3   image format (1=PNG, 2=JPEG)
 *   4-7   width
 *   8-11  height
 */
object MagicPasteProtocol {
    const val MAGIC = 0x534E4150
    const val MSG_IMAGE = 0x01
    const val MSG_IMAGE_ACK = 0x06
    const val IMG_PNG = 0x01
    const val IMG_JPEG = 0x02
    const val DEFAULT_PORT = 49152
    const val TOKEN_SIZE = 16

    /** Coerce a token to exactly TOKEN_SIZE bytes (zero-padded / truncated). */
    private fun normToken(token: ByteArray?): ByteArray {
        val out = ByteArray(TOKEN_SIZE)
        if (token != null) System.arraycopy(token, 0, out, 0, minOf(token.size, TOKEN_SIZE))
        return out
    }

    /** Parse a hex token string into TOKEN_SIZE bytes, or zeros. */
    fun tokenFromHex(hex: String?): ByteArray {
        val out = ByteArray(TOKEN_SIZE)
        if (hex.isNullOrEmpty()) return out
        val clean = hex.trim()
        var i = 0
        while (i + 1 < clean.length && i / 2 < TOKEN_SIZE) {
            out[i / 2] = clean.substring(i, i + 2).toInt(16).toByte()
            i += 2
        }
        return out
    }

    private fun header(msgType: Int, payloadLen: Int, token: ByteArray?): ByteArray =
        ByteBuffer.allocate(32).order(ByteOrder.BIG_ENDIAN).apply {
            putInt(MAGIC)
            putInt(msgType)
            putInt(payloadLen)
            putInt(0)
            put(normToken(token))
        }.array()

    /**
     * Send a single image to host:port. Returns true on success.
     * Opens a short-lived connection, writes the IMAGE message, then closes.
     */
    fun sendImage(
        host: String,
        port: Int,
        raw: ByteArray,
        imageFormat: Int,
        width: Int,
        height: Int,
        token: ByteArray? = null,
        timeoutMs: Int = 8000,
    ): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), timeoutMs)
                val prefix = ByteBuffer.allocate(12).order(ByteOrder.BIG_ENDIAN).apply {
                    putInt(imageFormat)
                    putInt(width)
                    putInt(height)
                }.array()
                val payloadLen = prefix.size + raw.size
                BufferedOutputStream(socket.getOutputStream()).apply {
                    write(header(MSG_IMAGE, payloadLen, token))
                    write(prefix)
                    write(raw)
                    flush()
                }
                // Wait for the PC's ACK so we only count it as delivered when
                // it actually hit the clipboard (1) and not when paused (0).
                socket.soTimeout = 4000
                readAccepted(socket.getInputStream())
            }
        } catch (e: Exception) {
            false
        }
    }

    /** Read an IMAGE_ACK. Returns false only on an explicit "dropped" (0);
     *  a missing/!timed-out ACK is treated as delivered for resilience. */
    private fun readAccepted(ins: InputStream): Boolean {
        val header = ByteArray(32)
        if (!readFully(ins, header)) return true
        val bb = ByteBuffer.wrap(header).order(ByteOrder.BIG_ENDIAN)
        if (bb.getInt(0) != MAGIC || bb.getInt(4) != MSG_IMAGE_ACK) return true
        val plen = bb.getInt(8)
        if (plen <= 0) return true
        val pl = ByteArray(plen)
        if (!readFully(ins, pl)) return true
        return pl[0].toInt() != 0
    }

    private fun readFully(ins: InputStream, buf: ByteArray): Boolean {
        var off = 0
        while (off < buf.size) {
            val n = try {
                ins.read(buf, off, buf.size - off)
            } catch (e: Exception) {
                return false
            }
            if (n < 0) return false
            off += n
        }
        return true
    }
}
