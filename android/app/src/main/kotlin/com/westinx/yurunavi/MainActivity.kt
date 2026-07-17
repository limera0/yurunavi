package com.westinx.yurunavi

import android.content.Intent
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Debug-only E2E test harness: reads optional `e2e_dest_lat` / `e2e_dest_lon` String
 * intent extras (set via `adb shell am start ... --es e2e_dest_lat ... --es e2e_dest_lon ...`)
 * and exposes them to Flutter over a MethodChannel so an unattended virtual-GPS test
 * drive can be kicked off without simulating map taps. No new permissions or manifest
 * changes; these are just extras on the existing launcher activity. Flutter side gates
 * all use of this behind kDebugMode, so this is inert in release builds.
 */
class MainActivity : FlutterActivity() {
    private val e2eHarnessChannel = "com.westinx.yurunavi/e2e_harness"
    private val navServiceChannel = "com.westinx.yurunavi/nav_service"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, e2eHarnessChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getE2EDestination") {
                    result.success(readE2EDestinationExtras())
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, navServiceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        sendNavServiceIntent(NavForegroundService.ACTION_START, call.argument("text"))
                        result.success(null)
                    }
                    "update" -> {
                        sendNavServiceIntent(NavForegroundService.ACTION_UPDATE, call.argument("text"))
                        result.success(null)
                    }
                    "stop" -> {
                        startService(Intent(this, NavForegroundService::class.java).apply {
                            action = NavForegroundService.ACTION_STOP
                        })
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sendNavServiceIntent(action: String, text: String?) {
        val intent = Intent(this, NavForegroundService::class.java).apply {
            this.action = action
            putExtra(NavForegroundService.EXTRA_TEXT, text)
        }
        ContextCompat.startForegroundService(this, intent)
    }

    private fun readE2EDestinationExtras(): Map<String, Double>? {
        val extras: Bundle? = intent.extras
        val lat = extras?.getString("e2e_dest_lat")?.toDoubleOrNull()
        val lon = extras?.getString("e2e_dest_lon")?.toDoubleOrNull()
        if (lat == null || lon == null) return null
        return mapOf("lat" to lat, "lon" to lon)
    }
}
