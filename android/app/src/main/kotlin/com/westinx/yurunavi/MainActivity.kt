package com.westinx.yurunavi

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.thesparks.android_pip.PipCallbackHelper
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
    private val pipHintChannel = "com.westinx.yurunavi/nav_pip_hint"

    // enterPictureInPictureMode() only succeeds while the activity is still visible, so PiP
    // entry must be triggered from onUserLeaveHint() (fires before onPause/onStop) rather than
    // from Flutter's AppLifecycleState.paused (maps to onStop, already too late — confirmed by
    // device testing: mLastReportedPictureInPictureMode stayed false when triggered from there).
    private var pipHintMethodChannel: MethodChannel? = null

    // android_pip's onPipEntered/onPipExited/onPipMaximised Dart callbacks only fire if the
    // host Activity forwards onPictureInPictureModeChanged to this helper ("Callback helper"
    // wiring from the package README — the alternative "Activity wrapper" approach would mean
    // extending com.thesparks.android_pip.PipCallbackHelperActivityWrapper instead of
    // FlutterActivity, which we avoid here to keep this class's existing hierarchy untouched).
    private val pipCallbackHelper = PipCallbackHelper()

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipCallbackHelper.onPictureInPictureModeChanged(isInPictureInPictureMode, this)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        pipHintMethodChannel?.invokeMethod("onUserLeaveHint", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipCallbackHelper.configureFlutterEngine(flutterEngine)
        pipHintMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipHintChannel)

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
