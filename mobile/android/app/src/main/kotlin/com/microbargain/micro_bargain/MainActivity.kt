package com.microbargain.micro_bargain

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import java.io.PrintWriter
import java.io.StringWriter
import kotlin.system.exitProcess

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashScreen()
        super.onCreate(savedInstanceState)
        reportLastExit()
    }

    private fun header(): String {
        val version = packageManager.getPackageInfo(packageName, 0).versionName
        return "Micro Bargain $version · ${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
    }

    private fun showReport(report: String) {
        startActivity(
            Intent(applicationContext, CrashActivity::class.java)
                .putExtra(CrashActivity.EXTRA_REPORT, report)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    /** A Java/Kotlin crash shows its reason on a separate screen (own process) that the user can share. */
    private fun installCrashScreen() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val trace = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
                markReported()
                showReport("${header()}\n\n$trace")
                android.os.Process.killProcess(android.os.Process.myPid())
                exitProcess(10)
            } catch (_: Throwable) {
                previous?.uncaughtException(thread, error)
            }
        }
    }

    private fun markReported() {
        getSharedPreferences("crash_report", Context.MODE_PRIVATE).edit().putLong("shown_until", System.currentTimeMillis()).commit()
    }

    /** Native crashes and freezes can't be caught in-process; Android 11+ tells us about them on the next start. */
    private fun reportLastExit() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val prefs = getSharedPreferences("crash_report", Context.MODE_PRIVATE)
            val shownUntil = prefs.getLong("shown_until", 0)
            val exit = (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager)
                .getHistoricalProcessExitReasons(packageName, 0, 5)
                .firstOrNull { it.processName == packageName } ?: return
            if (exit.timestamp <= shownUntil) return
            val kind = when (exit.reason) {
                ApplicationExitInfo.REASON_CRASH_NATIVE -> "NATIVE CRASH"
                ApplicationExitInfo.REASON_CRASH -> "CRASH"
                ApplicationExitInfo.REASON_ANR -> "FREEZE (ANR)"
                else -> return
            }
            prefs.edit().putLong("shown_until", exit.timestamp).apply()
            val trace = try {
                exit.traceInputStream?.use { stream ->
                    val bytes = stream.readBytes()
                    if (exit.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                        Tombstone.describe(bytes)
                    } else {
                        String(bytes, Charsets.UTF_8).take(20000) // ANR traces are text
                    }
                } ?: ""
            } catch (_: Throwable) {
                ""
            }
            showReport("${header()}\n\n$kind: ${exit.description ?: ""}\n\n$trace".take(60000))
        } catch (_: Throwable) {
            // Reporting must never break the app.
        }
    }
}
