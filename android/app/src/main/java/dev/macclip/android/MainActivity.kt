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
        add(button("QR kodu okut") { scan() }, top = 16)

        add(heading("Elle giriş"), top = 28)
        host = EditText(this).apply {
            hint = "Mac IP adresi (ör. 192.168.1.10)"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
        }
        add(host)
        port = EditText(this).apply {
            hint = "Port"
            inputType = InputType.TYPE_CLASS_NUMBER
        }
        add(port)
        key = EditText(this).apply {
            hint = "Anahtar"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        }
        add(key)
        add(button("Kaydet") { saveManual() })

        add(heading("Bağlantı"), top = 28)
        add(button("Bağlantıyı test et") { test() })
        result = TextView(this)
        add(result)
        pending = TextView(this)
        add(pending, top = 16)
        add(button("Şimdi gönder") { sendNow() })

        add(TextView(this).apply {
            text = "Kullanım: herhangi bir uygulamada metin veya görseli paylaşıp \"Mac'e gönder\"i seçin. " +
                "Mac'e ulaşılamazsa öğe sıraya alınır ve Wi-Fi'dayken yaklaşık 15 dakikada bir yeniden denenir."
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
            status.text = "Eşleşmemiş. Mac'teki MacClip menüsünden \"Yeniden eşleştir…\" ile QR kodunu açıp okutun."
            port.setText(DEFAULT_PORT.toString())
            return
        }
        status.text = "Eşleşmiş: ${pairing.name} (${pairing.host.ifEmpty { "adres yok, Bonjour" }}:${pairing.port})"
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
                    result.text = "Bu bir MacClip eşleşme kodu değil."
                } else {
                    paired(pairing)
                }
            }
            .addOnFailureListener { result.text = "QR okunamadı: ${it.message}. Elle girişi kullanabilirsiniz." }
    }

    private fun saveManual() {
        val existingName = Graph.pairing(this)?.name ?: "Mac"
        val pairing = Pairing.create(host.text.toString(), port.text.toString(), key.text.toString(), existingName)
        if (pairing == null) {
            result.text = "Port veya anahtar geçersiz. Anahtar, Mac'teki eşleşme penceresinde yazan 43 karakterlik metindir."
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
            result.text = "Önce eşleştirin."
            return
        }
        result.text = "Deneniyor…"
        background {
            val r = Graph.sender(this, pairing).ping()
            val text = when {
                r.status == 200 -> "Bağlantı başarılı ✓"
                r.status == 401 -> "Mac'e ulaşıldı ama anahtar uyuşmuyor. QR kodunu yeniden okutun."
                r.reachable -> "Mac'e ulaşıldı ama beklenmeyen yanıt: ${r.status}"
                else -> "Mac'e ulaşılamadı. Aynı Wi-Fi'da mısınız, MacClip açık mı?\n(${r.body})"
            }
            ui { result.text = text }
        }
    }

    private fun sendNow() {
        val pairing = Graph.pairing(this) ?: run {
            result.text = "Önce eşleştirin."
            return
        }
        result.text = "Gönderiliyor…"
        background {
            val report = Graph.sender(this, pairing).flush()
            if (report.remaining == 0) Retry.cancel(this)
            val text = when (report.problem) {
                null -> "${report.sent} öğe gönderildi" + if (report.rejected > 0) ", ${report.rejected} öğe Mac tarafından reddedildi" else ""
                Sender.Problem.UNAUTHORIZED -> "Anahtar uyuşmuyor. QR kodunu yeniden okutun."
                Sender.Problem.UNREACHABLE -> "Mac'e ulaşılamadı. ${report.sent} öğe gönderildi, ${report.remaining} öğe bekliyor."
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
            ui { pending.text = if (count == 0) "Bekleyen öğe yok" else "Bekleyen: $count öğe" }
        }
    }

    private fun background(block: () -> Unit) = Thread(block).start()

    private fun ui(block: () -> Unit) = runOnUiThread { if (!isDestroyed) block() }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
