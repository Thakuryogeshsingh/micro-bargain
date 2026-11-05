package com.microbargain.micro_bargain

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Shown after a crash (runs in its own process, see the manifest): the reason, with Share and Restart. */
class CrashActivity : Activity() {
    companion object {
        const val EXTRA_REPORT = "report"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val report = intent.getStringExtra(EXTRA_REPORT) ?: "Unknown error"
        val pad = (16 * resources.displayMetrics.density).toInt()

        val title = TextView(this).apply {
            text = "ऐप में गड़बड़ हुई 😔\nनीचे \"शेयर करें\" दबाकर यह जानकारी डेवलपर को भेजें।"
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.BLACK)
        }
        val details = TextView(this).apply {
            text = report
            textSize = 11f
            setTextIsSelectable(true)
            typeface = Typeface.MONOSPACE
            setTextColor(Color.DKGRAY)
        }
        val share = Button(this).apply {
            text = "शेयर करें (WhatsApp)"
            setOnClickListener {
                startActivity(Intent.createChooser(
                    Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, report), "Share"))
            }
        }
        val restart = Button(this).apply {
            text = "ऐप फिर से खोलें"
            setOnClickListener {
                startActivity(Intent(this@CrashActivity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                finish()
            }
        }
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad * 2, pad, pad)
            setBackgroundColor(Color.WHITE)
            addView(title)
            addView(share)
            addView(restart)
            addView(details)
        }
        setContentView(ScrollView(this).apply { addView(column) })
    }
}
