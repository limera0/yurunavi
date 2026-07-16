package com.westinx.gpsinjector

import android.app.Activity
import android.location.Location
import android.location.LocationManager
import android.location.provider.ProviderProperties
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.widget.TextView
import java.io.File

/**
 * 실기기 GPS 스푸핑 전용 계측 도구. yurunavi 본 앱과 무관한 별도 applicationId.
 *
 * /sdcard/Android/data/com.westinx.gpsinjector/files/<routefile> 에 미리 push해둔
 * CSV(seq,lat,lon,speed_mps,bearing_deg,accuracy_m,delay_ms_before_this_point)를
 * 읽어 LocationManager test-provider "gps"로 실시간 재생한다. delay_ms만큼 실제로
 * sleep한 뒤 다음 포인트를 주입하므로, 목표 앱(yurunavi) 쪽에서 봤을 때 실제
 * 주행처럼 시간 간격이 보존된다 (adb shell cmd location providers는 speed/bearing
 * 필드를 노출하지 않아 이 앱을 새로 만들었음 — 자세한 배경은 커밋 메시지 참조).
 *
 * 실행: adb shell am start -n com.westinx.gpsinjector/.MainActivity \
 *         --es routefile <name>.csv --ez autostart true
 * 진행 로그: logcat -s GPSINJ
 */
class MainActivity : Activity() {

    private lateinit var statusView: TextView
    private var playThread: Thread? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        statusView = TextView(this).apply {
            textSize = 14f
            setPadding(24, 24, 24, 24)
            text = "GPS Injector idle"
        }
        setContentView(statusView)
        handleIntent()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent()
    }

    private fun handleIntent() {
        val routeFile = intent.getStringExtra("routefile") ?: return
        val autostart = intent.getBooleanExtra("autostart", true)
        if (!autostart) return
        startPlayback(routeFile)
    }

    private fun startPlayback(routeFile: String) {
        playThread?.interrupt()
        val lm = getSystemService(LOCATION_SERVICE) as LocationManager
        // GPS_PROVIDER만 모킹하면 안드로이드가 실측(mocked=false) fix를 주기적으로
        // 섞어 넣는 게 실측 확인됨(YNAV_FIX 진단 로그로 확정: ~60-100초 간격, 항상
        // 동일한 실좌표, 이 기기의 실제 물리적 위치로 추정 — Wi-Fi 기반 정확도
        // 20m). GPS_PROVIDER+NETWORK_PROVIDER 모킹 및 Geolocator
        // forceLocationManager(Play Services 우회)까지 다 해봐도 뚫고 들어왔다 —
        // Android 12+(API 31+)에서 추가된 LocationManager.FUSED_PROVIDER("fused")가
        // GPS/NETWORK와 별개의 OS 레벨 3번째 provider라서 그 경로로 실측 위치가
        // 새는 것으로 결론. 세 provider 모두 동일 좌표로 모킹해 어떤 경로로 요청이
        // 들어와도 실측 신호 자체가 없게 만든다.
        val providers = buildList {
            add(LocationManager.GPS_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
            if (Build.VERSION.SDK_INT >= 31) add(LocationManager.FUSED_PROVIDER)
        }

        for (provider in providers) {
            try {
                lm.removeTestProvider(provider)
            } catch (_: Exception) {
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    lm.addTestProvider(
                        provider,
                        ProviderProperties.Builder()
                            .setHasNetworkRequirement(false)
                            .setHasSatelliteRequirement(true)
                            .setHasAltitudeSupport(true)
                            .setHasSpeedSupport(true)
                            .setHasBearingSupport(true)
                            .setPowerUsage(ProviderProperties.POWER_USAGE_HIGH)
                            .setAccuracy(ProviderProperties.ACCURACY_FINE)
                            .build()
                    )
                } else {
                    @Suppress("DEPRECATION")
                    lm.addTestProvider(
                        provider, false, true, false, false, true, true, true, 1, 1
                    )
                }
                lm.setTestProviderEnabled(provider, true)
            } catch (e: SecurityException) {
                log("ERROR mock_location permission not granted: ${e.message}")
                runOnUiThread { statusView.text = "ERROR: mock_location not allowed" }
                return
            }
        }

        val file = File(getExternalFilesDir(null), routeFile)
        if (!file.exists()) {
            log("ERROR route file not found: ${file.absolutePath}")
            runOnUiThread { statusView.text = "ERROR: ${file.absolutePath} missing" }
            return
        }

        val rows = file.readLines().drop(1).filter { it.isNotBlank() }
        log("START route=$routeFile points=${rows.size}")
        runOnUiThread { statusView.text = "Playing $routeFile (${rows.size} pts)" }

        playThread = Thread {
            try {
                for ((i, line) in rows.withIndex()) {
                    val parts = line.split(",")
                    val seq = parts[0]
                    val lat = parts[1].toDouble()
                    val lon = parts[2].toDouble()
                    val speedMps = parts[3].toFloat()
                    val bearingDeg = parts[4].toFloat()
                    val accuracyM = parts[5].toFloat()
                    val delayMs = parts[6].toLong()

                    if (delayMs > 0) Thread.sleep(delayMs)
                    if (Thread.currentThread().isInterrupted) break

                    for (provider in providers) {
                        val loc = Location(provider).apply {
                            latitude = lat
                            longitude = lon
                            accuracy = accuracyM
                            speed = speedMps
                            bearing = bearingDeg
                            time = System.currentTimeMillis()
                            elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                        }
                        lm.setTestProviderLocation(provider, loc)
                    }
                    log("PT seq=$seq lat=$lat lon=$lon spd=$speedMps brg=$bearingDeg i=${i + 1}/${rows.size}")
                    runOnUiThread {
                        statusView.text = "route=$routeFile ${i + 1}/${rows.size} spd=${speedMps}m/s"
                    }
                }
                log("DONE route=$routeFile")
                runOnUiThread { statusView.text = "DONE $routeFile" }
            } catch (e: InterruptedException) {
                log("INTERRUPTED route=$routeFile")
            } catch (e: Exception) {
                log("ERROR during playback: $e")
            }
        }
        playThread?.start()
    }

    private fun log(msg: String) {
        Log.i("GPSINJ", msg)
    }
}
