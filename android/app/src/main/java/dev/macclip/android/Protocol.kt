package dev.macclip.android

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

// Wire format shared with the Mac app; see SPEC.md. Nothing in this file uses Android APIs,
// so the JVM unit tests can talk to a real Mac app with it.

const val PATH_ITEMS = "/v1/items"
const val PATH_PING = "/v1/ping"
const val DEFAULT_PORT = 47812

data class Header(val id: String, val type: String, val mime: String, val sentAt: Long) {
    fun toJson(): String =
        """{"id":${jsonString(id)},"type":${jsonString(type)},"mime":${jsonString(mime)},"sentAt":$sentAt}"""
}

private fun jsonString(s: String): String = buildString {
    append('"')
    for (c in s) {
        when {
            c == '"' -> append("\\\"")
            c == '\\' -> append("\\\\")
            c < ' ' -> append(String.format("\\u%04x", c.code))
            else -> append(c)
        }
    }
    append('"')
}

object Envelope {
    private val random = SecureRandom()

    /** nonce(12) || AES-256-GCM(headerLength(4) || header JSON || content) || tag(16), AAD = path. */
    fun seal(
        header: Header,
        content: ByteArray,
        key: ByteArray,
        path: String,
        nonce: ByteArray = ByteArray(12).also(random::nextBytes),
    ): ByteArray {
        val headerBytes = header.toJson().toByteArray(Charsets.UTF_8)
        val plain = ByteBuffer.allocate(4 + headerBytes.size + content.size)
            .putInt(headerBytes.size).put(headerBytes).put(content).array()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(path.toByteArray(Charsets.UTF_8))
        return nonce + cipher.doFinal(plain)
    }
}

data class Pairing(val host: String, val port: Int, val key: String, val name: String) {
    val keyBytes: ByteArray get() = decodeKey(key)!!

    /** Same fingerprint the Mac advertises in its Bonjour TXT record. */
    val keyId: String
        get() = MessageDigest.getInstance("SHA-256").digest(key.toByteArray(Charsets.UTF_8))
            .take(4).joinToString("") { "%02x".format(it) }

    companion object {
        /** Parses `macclip://pair?v=1&h=<ip>&p=<port>&k=<key>&n=<name>` from the Mac's QR code. */
        fun parse(text: String): Pairing? {
            val uri = runCatching { URI(text.trim()) }.getOrNull() ?: return null
            if (uri.scheme != "macclip" || uri.host != "pair") return null
            val params = (uri.rawQuery ?: "").split("&").mapNotNull { part ->
                val eq = part.indexOf('=')
                if (eq < 0) null else part.substring(0, eq) to URLDecoder.decode(part.substring(eq + 1), "UTF-8")
            }.toMap()
            if (params["v"] != "1") return null
            return create(params["h"] ?: "", params["p"] ?: "", params["k"] ?: "", params["n"] ?: "Mac")
        }

        /** Validates manually entered or scanned values. */
        fun create(host: String, port: String, key: String, name: String = "Mac"): Pairing? {
            val portNumber = port.trim().toIntOrNull()?.takeIf { it in 1..65535 } ?: return null
            val cleanKey = key.trim()
            if (decodeKey(cleanKey) == null) return null
            return Pairing(host.trim(), portNumber, cleanKey, name.trim().ifEmpty { "Mac" })
        }

        private fun decodeKey(key: String): ByteArray? =
            runCatching { Base64.getUrlDecoder().decode(key) }.getOrNull()?.takeIf { it.size == 32 }
    }
}

/** [status] is -1 when the Mac could not be reached at all. */
data class HttpResult(val status: Int, val body: String) {
    val reachable: Boolean get() = status > 0
}

object MacClient {
    fun post(host: String, port: Int, path: String, body: ByteArray, connectTimeoutMs: Int = 2000): HttpResult {
        val connection = try {
            URL("http", host, port, path).openConnection() as HttpURLConnection
        } catch (e: IOException) {
            return HttpResult(-1, e.toString())
        }
        return try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = connectTimeoutMs
            connection.readTimeout = 20_000
            connection.setFixedLengthStreamingMode(body.size)
            connection.setRequestProperty("Content-Type", "application/octet-stream")
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            val stream = if (status < 400) connection.inputStream else connection.errorStream
            HttpResult(status, stream?.bufferedReader()?.use { it.readText() } ?: "")
        } catch (e: IOException) {
            HttpResult(-1, e.toString())
        } finally {
            connection.disconnect()
        }
    }
}
