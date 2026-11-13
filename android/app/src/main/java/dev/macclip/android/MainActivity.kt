package dev.macclip.android

import android.app.Activity
import android.os.Bundle
import android.text.InputType
import android.util.TypedValue
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

/** Pairing and settings: scan the Mac's QR code or enter it by hand, test the connection, flush the queue. */
class MainActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var host: EditText
    private lateinit var port: EditText
    private lateinit var key: EditText
    private lateinit var result: TextView
    private lateinit var pending: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(16), dp(24), dp(24))
        }
        fun add(view: View, top: Int = 8) {
            column.addView(view, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { topMargin = dp(top) })
        }
        fun heading(text: String) = TextView(this).apply {
            this.text = text
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        fun button(text: String, onClick: () -> Unit) = Button(this).apply {
            this.text = text
            isAllCaps = false
            setOnClickListener { onClick() }
        }

        add(TextView(this).apply {
            text = getString(R.string.app_name)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }, top = 0)
        status = TextView(this)
        add(status)
        add(button(getString(R.string.scan_qr)) { scan() }, top = 16)

        add(heading(getString(R.string.manual_heading)), top = 28)
        host = EditText(this).apply {
            hint = getString(R.string.host_hint)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
        }
        add(host)
        port = EditText(this).apply {
            hint = getString(R.string.port_hint)
            inputType = InputType.TYPE_CLASS_NUMBER
        }
        add(port)
        key = EditText(this).apply {
            hint = getString(R.string.key_hint)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        }
        add(key)
        add(button(getString(R.string.save)) { saveManual() })

        add(heading(getString(R.string.connection_heading)), top = 28)
        add(button(getString(R.string.test_connection)) { test() })
        result = TextView(this)
        add(result)
        pending = TextView(this)
        add(pending, top = 16)
        add(button(getString(R.string.send_now)) { sendNow() })

        add(TextView(this).apply {
            text = getString(R.string.usage)
            alpha = 0.7f
        }, top = 28)

        val scroll = ScrollView(this).apply { addView(column) }
        // targetSdk 35+ draws edge to edge; keep content clear of the status and navigation bars.
        scroll.setOnApplyWindowInsetsListener { view, insets ->
            val bars = if (android.os.Build.VERSION.SDK_INT >= 30) {
                insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                    .let { android.graphics.Rect(it.left, it.top, it.right, it.bottom) }
            } else {
                @Suppress("DEPRECATION")
                android.graphics.Rect(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            }
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        setContentView(scroll)
        showPairing()
    }

    override fun onResume() {
        super.onResume()
        refreshPending()
    }

    private fun showPairing() {
        val pairing = Graph.pairing(this)
        if (pairing == null) {
            status.text = getString(R.string.not_paired)
            port.setText(DEFAULT_PORT.toString())
            return
        }
        status.text = getString(R.string.paired, pairing.name, pairing.host.ifEmpty { getString(R.string.no_address_bonjour) }, pairing.port)
        host.setText(pairing.host)
        port.setText(pairing.port.toString())
        key.setText(pairing.key)
    }

    private fun scan() {
        val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
        GmsBarcodeScanning.getClient(this, options).startScan()
            .addOnSuccessListener { barcode ->
                val pairing = barcode.rawValue?.let(Pairing::parse)
                if (pairing == null) {
                    result.text = getString(R.string.not_a_pairing_code)
                } else {
                    paired(pairing)
                }
            }
            .addOnFailureListener { result.text = getString(R.string.scan_failed, it.message) }
    }

    private fun saveManual() {
        val existingName = Graph.pairing(this)?.name ?: "Mac"
        val pairing = Pairing.create(host.text.toString(), port.text.toString(), key.text.toString(), existingName)
        if (pairing == null) {
            result.text = getString(R.string.invalid_manual)
            return
        }
        paired(pairing)
    }

    private fun paired(pairing: Pairing) {
        Graph.savePairing(this, pairing)
        showPairing()
        test()
    }

    private fun test() {
        val pairing = Graph.pairing(this) ?: run {
            result.text = getString(R.string.pair_first)
            return
        }
        result.text = getString(R.string.testing)
        background {
            val r = Graph.sender(this, pairing).ping()
            // Manual entry doesn't know the Mac's name; take it from the reply.
            val macName = if (r.status == 200) runCatching { org.json.JSONObject(r.body).getString("name") }.getOrNull() else null
            if (macName != null && macName != pairing.name) {
                Graph.savePairing(this, pairing.copy(name = macName))
                ui { showPairing() }
            }
            val text = when {
                r.status == 200 -> getString(R.string.test_ok)
                r.status == 401 -> getString(R.string.test_wrong_key)
                r.reachable -> getString(R.string.test_unexpected, r.status)
                else -> getString(R.string.test_unreachable, r.body)
            }
            ui { result.text = text }
        }
    }

    private fun sendNow() {
        val pairing = Graph.pairing(this) ?: run {
            result.text = getString(R.string.pair_first)
            return
        }
        result.text = getString(R.string.sending)
        background {
            val report = Graph.sender(this, pairing).flush()
            if (report.remaining == 0) Retry.cancel(this)
            val text = when (report.problem) {
                null -> plural(R.plurals.sent_count, report.sent) +
                    if (report.rejected > 0) plural(R.plurals.rejected_suffix, report.rejected) else ""
                Sender.Problem.UNAUTHORIZED -> getString(R.string.wrong_key)
                Sender.Problem.UNREACHABLE -> getString(R.string.flush_unreachable, report.sent, report.remaining)
            }
            ui {
                result.text = text
                refreshPending()
            }
        }
    }

    private fun refreshPending() {
        background {
            val count = Graph.outbox(this).count()
            // Also refreshes the retry schedule after an app update.
            if (count > 0) Retry.schedule(this)
            ui { pending.text = if (count == 0) getString(R.string.nothing_pending) else plural(R.plurals.pending_count, count) }
        }
    }

    private fun plural(id: Int, count: Int) = resources.getQuantityString(id, count, count)

    private fun background(block: () -> Unit) = Thread(block).start()

    private fun ui(block: () -> Unit) = runOnUiThread { if (!isDestroyed) block() }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
