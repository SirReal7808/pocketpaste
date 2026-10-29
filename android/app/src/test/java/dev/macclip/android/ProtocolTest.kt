package dev.macclip.android

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.file.Files
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class EnvelopeTest {
    private val key = ByteArray(32) { it.toByte() }

    @Test
    fun sealsInTheSharedFormat() {
        val header = Header("00000000-0000-0000-0000-000000000001", "text", "text/plain", 1)
        val body = Envelope.seal(header, "hi".toByteArray(), key, PATH_ITEMS, nonce = ByteArray(12) { 7 })

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, body.copyOfRange(0, 12)))
        cipher.updateAAD(PATH_ITEMS.toByteArray())
        val plain = ByteBuffer.wrap(cipher.doFinal(body.copyOfRange(12, body.size)))
        val headerBytes = ByteArray(plain.int).also { plain.get(it) }
        val content = ByteArray(plain.remaining()).also { plain.get(it) }

        assertEquals("""{"id":"00000000-0000-0000-0000-000000000001","type":"text","mime":"text/plain","sentAt":1}""", String(headerBytes))
        assertArrayEquals("hi".toByteArray(), content)
    }

    @Test
    fun escapesJson() {
        assertEquals("""{"id":"a\"b\\c\u000a","type":"t","mime":"m","sentAt":5}""", Header("a\"b\\c\n", "t", "m", 5).toJson())
    }
}

class PairingTest {
    private val key = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32) { 1 })

    @Test
    fun parsesMacQr() {
        val p = Pairing.parse("macclip://pair?v=1&h=192.168.1.10&p=47812&k=$key&n=Mert%E2%80%99in%20Mac")
        assertNotNull(p)
        assertEquals("192.168.1.10", p!!.host)
        assertEquals(47812, p.port)
        assertEquals("Mert’in Mac", p.name)
        assertEquals(8, p.keyId.length)
    }

    @Test
    fun rejectsBadInput() {
        assertNull(Pairing.parse("https://example.com"))
        assertNull(Pairing.parse("macclip://pair?v=2&h=1.2.3.4&p=1&k=$key"))
        assertNull(Pairing.parse("macclip://pair?v=1&h=1.2.3.4&p=99999&k=$key"))
        assertNull(Pairing.create("1.2.3.4", "47812", "short"))
        assertNotNull(Pairing.create(" 1.2.3.4 ", " 47812 ", " $key "))
    }

    @Test
    fun keyIdMatchesMac() {
        // Same input as the Mac computes: SHA-256 of the key string, first 4 bytes.
        val p = Pairing.create("", "1", key)!!
        val expected = java.security.MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).take(4).joinToString("") { "%02x".format(it) }
        assertEquals(expected, p.keyId)
    }
}

class OutboxTest {
    private val dir: File = Files.createTempDirectory("outbox").toFile()
    private var now = 1_800_000_000_000L
    private val outbox = Outbox(dir) { now }

    @Test
    fun keepsNewest20OldestFirst() {
        repeat(25) {
            now += 1000
            outbox.add("text", "text/plain", "item $it".toByteArray())
        }
        val pending = outbox.pending()
        assertEquals(20, pending.size)
        assertEquals("item 5", String(pending.first().content.readBytes()))
        assertEquals(40, dir.listFiles()!!.size)
    }

    @Test
    fun dropsItemsOlderThanTenDays() {
        outbox.add("text", "text/plain", "old".toByteArray())
        now += 11L * 24 * 3600 * 1000
        assertEquals(0, outbox.count())
    }

    @Test
    fun senderKeepsItemsWhenMacIsUnreachable() {
        outbox.add("text", "text/plain", "x".toByteArray())
        val key = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32))
        // Port 9 on localhost: nothing listens there.
        val sender = Sender(outbox, Pairing("127.0.0.1", 9, key, "Mac")) { null }
        val report = sender.flush()
        assertEquals(Sender.Problem.UNREACHABLE, report.problem)
        assertEquals(1, report.remaining)
    }
}

/**
 * Talks to a running Mac app. Skipped unless the key is given:
 * ./gradlew test -PmacclipTestKey=<key> -PmacclipTestPort=<port>
 */
class MacIntegrationTest {
    private val key: String? = System.getProperty("macclipTestKey")
    private val port = System.getProperty("macclipTestPort")?.toInt() ?: DEFAULT_PORT
    private val host = System.getProperty("macclipTestHost") ?: "127.0.0.1"

    @Test
    fun sendsToRealMac() {
        assumeTrue("macclipTestKey not set", key != null)
        val pairing = Pairing.create(host, port.toString(), key!!, "Mac")!!
        val outbox = Outbox(Files.createTempDirectory("outbox").toFile())
        val sender = Sender(outbox, pairing) { null }

        assertEquals(200, sender.ping().status)

        outbox.add("text", "text/plain", "Android testinden merhaba 👋 — ğüşiöç".toByteArray())
        outbox.add("image", "image/png", solidPng(64, 32))
        val report = sender.flush()
        assertNull(report.problem)
        assertEquals(2, report.sent)
        assertEquals(0, report.remaining)

        // A wrong key must be refused and keep the item queued.
        outbox.add("text", "text/plain", "yanlış anahtar".toByteArray())
        val wrongKey = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32) { 9 })
        val bad = Sender(outbox, pairing.copy(key = wrongKey)) { null }.flush()
        assertEquals(Sender.Problem.UNAUTHORIZED, bad.problem)
        assertEquals(1, bad.remaining)
        assertTrue(sender.flush().sent == 1)
    }
}

/** A valid blue PNG built with java.util.zip only (java.awt is not available to Android unit tests). */
fun solidPng(width: Int, height: Int): ByteArray {
    fun chunk(type: String, data: ByteArray): ByteArray {
        val typeBytes = type.toByteArray()
        val crc = java.util.zip.CRC32().apply { update(typeBytes); update(data) }.value.toInt()
        return ByteBuffer.allocate(12 + data.size).putInt(data.size).put(typeBytes).put(data).putInt(crc).array()
    }
    val ihdr = ByteBuffer.allocate(13).putInt(width).putInt(height)
        .put(8).put(2).put(0).put(0).put(0).array() // 8-bit RGB
    val raw = java.io.ByteArrayOutputStream()
    repeat(height) {
        raw.write(0) // no filter
        repeat(width) { raw.write(0x1F); raw.write(0x6F); raw.write(0xEB) }
    }
    val compressed = java.io.ByteArrayOutputStream().also { out ->
        java.util.zip.DeflaterOutputStream(out).use { it.write(raw.toByteArray()) }
    }.toByteArray()
    val signature = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    return signature + chunk("IHDR", ihdr) + chunk("IDAT", compressed) + chunk("IEND", ByteArray(0))
}
