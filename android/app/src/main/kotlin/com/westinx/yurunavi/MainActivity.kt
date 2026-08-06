package com.westinx.yurunavi

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
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
    private val navFloatingChannel = "com.westinx.yurunavi/nav_floating"

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

        // 플로팅 오버레이 채널 (S3b 청크2, 2026-08-06)
        // SYSTEM_ALERT_WINDOW 권한은 AndroidManifest에 이미 선언됨.
        // 권한 부여는 런타임이 아니라 시스템 설정 화면으로 보내야 하므로
        // canDrawOverlays 조회/설정화면 인텐트는 Dart 쪽에서 처리한다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, navFloatingChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }
                    "openOverlaySettings" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:$packageName")
                        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
                        startActivity(intent)
                        result.success(null)
                    }
                    "show" -> {
                        val iconType = call.argument<String>("iconType") ?: "nav_straight"
                        val distText = call.argument<String>("distanceText") ?: ""
                        sendOverlayIntent(FloatingOverlayService.ACTION_SHOW, iconType, distText)
                        result.success(null)
                    }
                    "update" -> {
                        val iconType = call.argument<String>("iconType") ?: "nav_straight"
                        val distText = call.argument<String>("distanceText") ?: ""
                        sendOverlayIntent(FloatingOverlayService.ACTION_UPDATE, iconType, distText)
                        result.success(null)
                    }
                    "hide" -> {
                        startService(Intent(this, FloatingOverlayService::class.java).apply {
                            action = FloatingOverlayService.ACTION_HIDE
                        })
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sendOverlayIntent(action: String, iconType: String, distText: String) {
        val intent = Intent(this, FloatingOverlayService::class.java).apply {
            this.action = action
            putExtra(FloatingOverlayService.EXTRA_ICON, iconType)
            putExtra(FloatingOverlayService.EXTRA_TEXT, distText)
        }
        startService(intent)
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
        // 선택: e2e_course_idx(0=시골길/1=지방도로/2=국도) — 없으면 Dart 쪽 기본값(국도) 유지.
        val courseIdx = extras.getString("e2e_course_idx")?.toDoubleOrNull()
        // 선택: e2e_no_autostart=true면 경로 계산까지만 하고 코스 비교 시트에서 멈춘다
        // (3코스 비교 스크린샷 검증용, 1.0=true/그 외=false로 Dart에 bool 전달).
        val noAutostart = if (extras.getBoolean("e2e_no_autostart", false)) 1.0 else 0.0
        val out = mutableMapOf("lat" to lat, "lon" to lon, "noAutostart" to noAutostart)
        if (courseIdx != null) out["courseIdx"] = courseIdx
        return out
    }
}
