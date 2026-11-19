package io.github.sirreal7808.pocketpaste

import java.io.File
import java.util.Properties
import java.util.UUID

/**
 * Items waiting to reach the Mac. Every share goes through here first, so nothing is lost
 * when the Mac is off. Each item is `<id>.bin` (content) plus `<id>.meta`, written last.
 */
class Outbox(private val dir: File, private val now: () -> Long = System::currentTimeMillis) {
    data class Entry(val header: Header, val content: File)

    fun add(type: String, mime: String, content: ByteArray): Header = synchronized(LOCK) {
        dir.mkdirs()
        val header = Header(UUID.randomUUID().toString(), type, mime, now())
        File(dir, "${header.id}.bin").writeBytes(content)
        val meta = Properties().apply {
            setProperty("type", header.type)
            setProperty("mime", header.mime)
            setProperty("sentAt", header.sentAt.toString())
        }
        val tmp = File(dir, "${header.id}.meta.tmp")
        tmp.outputStream().use { meta.store(it, null) }
        tmp.renameTo(File(dir, "${header.id}.meta"))
        prune()
        header
    }

    /** Oldest first, after applying the age and count limits. */
    fun pending(): List<Entry> = synchronized(LOCK) {
        prune()
        readAll().sortedBy { it.header.sentAt }
    }

    fun count(): Int = pending().size

    fun remove(id: String): Unit = synchronized(LOCK) {
        File(dir, "$id.bin").delete()
        File(dir, "$id.meta").delete()
    }

    private fun readAll(): List<Entry> {
        val metas = dir.listFiles { f -> f.name.endsWith(".meta") } ?: return emptyList()
        return metas.mapNotNull { metaFile ->
            val id = metaFile.name.removeSuffix(".meta")
            val content = File(dir, "$id.bin")
            val props = Properties()
            runCatching { metaFile.inputStream().use(props::load) }
            val sentAt = props.getProperty("sentAt")?.toLongOrNull()
            val type = props.getProperty("type")
            val mime = props.getProperty("mime")
            if (sentAt == null || type == null || mime == null || !content.exists()) {
                metaFile.delete()
                content.delete()
                null
            } else {
                Entry(Header(id, type, mime, sentAt), content)
            }
        }
    }

    private fun prune() {
        val cutoff = now() - MAX_AGE_MS
        val all = readAll().sortedByDescending { it.header.sentAt }
        all.forEachIndexed { index, entry ->
            if (index >= MAX_ITEMS || entry.header.sentAt < cutoff) remove(entry.header.id)
        }
        // Content files whose meta was never written (the app died mid-write).
        dir.listFiles { f -> f.name.endsWith(".bin") && !File(dir, f.name.removeSuffix(".bin") + ".meta").exists() }
            ?.filter { now() - it.lastModified() > 60_000 }
            ?.forEach { it.delete() }
    }

    companion object {
        const val MAX_ITEMS = 20
        const val MAX_AGE_MS = 10L * 24 * 3600 * 1000
        private val LOCK = Any()
    }
}

/** Sends everything in the outbox, oldest first. */
class Sender(
    private val outbox: Outbox,
    private val pairing: Pairing,
    /** Finds the Mac over Bonjour; returns host and port, or null. */
    private val discover: () -> Pair<String, Int>?,
) {
    enum class Problem { UNREACHABLE, UNAUTHORIZED }

    data class Report(val sent: Int, val rejected: Int, val remaining: Int, val problem: Problem?)

    private var endpoint: Pair<String, Int>? = null

    fun flush(deadline: Long = Long.MAX_VALUE): Report {
        var sent = 0
        var rejected = 0
        var problem: Problem? = null
        for (entry in outbox.pending()) {
            if (System.currentTimeMillis() > deadline) {
                problem = Problem.UNREACHABLE
                break
            }
            val content = runCatching { entry.content.readBytes() }.getOrNull()
            if (content == null) {
                outbox.remove(entry.header.id)
                continue
            }
            val result = post(PATH_ITEMS, Envelope.seal(entry.header, content, pairing.keyBytes, PATH_ITEMS))
            when {
                result.status == 200 -> {
                    outbox.remove(entry.header.id)
                    sent++
                }
                result.status == 401 -> {
                    problem = Problem.UNAUTHORIZED
                    break
                }
                // Bad request, too large, expired: retrying cannot help.
                result.status in 400..499 && result.status != 408 -> {
                    outbox.remove(entry.header.id)
                    rejected++
                }
                else -> {
                    problem = Problem.UNREACHABLE
                    break
                }
            }
        }
        return Report(sent, rejected, outbox.count(), problem)
    }

    fun ping(): HttpResult {
        val header = Header(UUID.randomUUID().toString(), "ping", "", System.currentTimeMillis())
        return post(PATH_PING, Envelope.seal(header, ByteArray(0), pairing.keyBytes, PATH_PING))
    }

    /** The paired address first (fast with a static IP), then Bonjour if that cannot be reached. */
    private fun post(path: String, body: ByteArray): HttpResult {
        endpoint?.let { return MacClient.post(it.first, it.second, path, body) }
        var result = HttpResult(-1, "no address")
        if (pairing.host.isNotBlank()) {
            result = MacClient.post(pairing.host, pairing.port, path, body, connectTimeoutMs = 1500)
            if (result.reachable) {
                endpoint = pairing.host to pairing.port
                return result
            }
        }
        val found = discover() ?: return result
        result = MacClient.post(found.first, found.second, path, body)
        if (result.reachable) endpoint = found
        return result
    }
}
