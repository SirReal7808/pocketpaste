package dev.macclip.android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import java.io.InputStream

/**
 * Target of "Send to Mac" in the share sheet. Has no UI: copies what was shared into the outbox
 * (the share permission ends when this activity does), tries to send for a few seconds, shows a
 * Toast and finishes. Anything not sent is retried later by [OutboxWorker].
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = applicationContext
        val shared = intent
        Thread {
            val message = runCatching { handle(app, shared) }.getOrElse { app.getString(R.string.share_failed, it.message) }
            runOnUiThread {
                Toast.makeText(app, message, Toast.LENGTH_SHORT).show()
                finish()
            }
        }.start()
    }

    private fun handle(app: Context, intent: Intent): String {
        val outbox = Graph.outbox(app)
        var added = 0
        var tooLarge = 0
        var unsupported = 0

        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (intent.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true && !text.isNullOrBlank()) {
            if (text.toByteArray().size > MAX_TEXT_BYTES) {
                tooLarge++
            } else {
                outbox.add("text", "text/plain", text.toByteArray(Charsets.UTF_8))
                added++
            }
        } else {
            for (uri in streams(intent)) {
                val mime = contentResolver.getType(uri) ?: intent.type ?: ""
                if (!mime.startsWith("image/")) {
                    unsupported++
                    continue
                }
                val bytes = contentResolver.openInputStream(uri)?.use { readLimited(it, MAX_IMAGE_BYTES) }
                when (bytes) {
                    null -> tooLarge++
                    else -> {
                        outbox.add("image", mime, bytes)
                        added++
                    }
                }
            }
        }

        if (added == 0) {
            return when {
                tooLarge > 0 -> app.getString(R.string.share_too_large)
                else -> app.getString(R.string.share_unsupported)
            }
        }

        val pairing = Graph.pairing(app) ?: return app.getString(R.string.share_saved_unpaired)
        val report = Graph.sender(app, pairing).flush(deadline = System.currentTimeMillis() + SEND_BUDGET_MS)
        if (report.remaining > 0) Retry.schedule(app)

        val skippedCount = tooLarge + unsupported
        val skipped = if (skippedCount > 0) app.resources.getQuantityString(R.plurals.share_skipped, skippedCount, skippedCount) else ""
        return when (report.problem) {
            null -> app.getString(if (report.rejected > 0) R.string.share_some_rejected else R.string.share_sent, skipped)
            Sender.Problem.UNAUTHORIZED -> app.getString(R.string.share_wrong_key)
            Sender.Problem.UNREACHABLE -> app.getString(R.string.share_queued, skipped)
        }
    }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableExtra(Intent.EXTRA_STREAM)
        )
        Intent.ACTION_SEND_MULTIPLE ->
            (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)) ?: emptyList()
        else -> emptyList()
    }

    /** Returns null when the stream is longer than [limit]. */
    private fun readLimited(input: InputStream, limit: Int): ByteArray? {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) return out.toByteArray()
            out.write(buffer, 0, n)
            if (out.size() > limit) return null
        }
    }

    companion object {
        const val MAX_IMAGE_BYTES = 25 * 1024 * 1024
        const val MAX_TEXT_BYTES = 1_000_000
        const val SEND_BUDGET_MS = 4_000L
    }
}
