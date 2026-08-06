package com.westinx.yurunavi

import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * 네이티브(Kotlin/Flutter 엔진) 프로세스 로그를 EventChannel로 Dart에 흘려보낸다.
 *
 * 배경: 실주행 중 화면 서브트리가 백지로 렌더되는 버그의 유력 원인은 Flutter 엔진
 * (Impeller/Vulkan)의 GPU 자원 할당 실패인데, 기존 FileLogger는 Dart debugPrint만
 * 가로채 네이티브 엔진 로그(logcat)는 전혀 남기지 못했다. 이 브리지는 자기 프로세스
 * (자기 pid)의 logcat만 백그라운드 데몬 스레드로 읽어 allowlist 키워드에 매치되는
 * 줄만 Dart로 전달한다.
 *
 * 자기 pid 로그는 READ_LOGS 권한 없이도 읽을 수 있다(추가 권한/매니페스트 변경 없음).
 * 이 계측은 debug 전용이 아니다 — 마스터의 release 실주행에서 캡처돼야 의미가
 * 있으므로 kDebugMode 게이팅을 하지 않는다(Dart 쪽도 마찬가지).
 */
class NativeLogBridge(messenger: BinaryMessenger) {

    companion object {
        private const val CHANNEL = "com.westinx.yurunavi/native_log"

        /** 이 중 하나라도 포함된 로그 줄만 통과시킨다. `flutter` 태그 전체 허용은 절대 금지
         *  (debugPrint → logcat → 이 펌프 → EventChannel → debugPrint 무한 증폭 루프가 된다). */
        private val KEYWORDS = listOf(
            "Impeller", "impeller", "Vulkan", "vulkan", "glyph", "atlas",
            "GL_OUT_OF_MEMORY", "OutOfMemory", "onTrimMemory", "lowmemorykiller",
            "Surface", "EGL"
        )
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    init {
        EventChannel(messenger, CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        startLogPump()
    }

    /** 앱 프로세스 종료 시 자연 종료되는 데몬 스레드 하나로 충분 — 정지/재개 관리는 하지 않는다. */
    private fun startLogPump() {
        val thread = Thread({
            try {
                val pid = Process.myPid()
                val process = ProcessBuilder("logcat", "-v", "threadtime", "--pid=$pid")
                    .redirectErrorStream(true)
                    .start()
                val reader = BufferedReader(InputStreamReader(process.inputStream))
                while (true) {
                    val line = reader.readLine() ?: break
                    if (KEYWORDS.any { line.contains(it) }) {
                        val captured = line
                        mainHandler.post { eventSink?.success(captured) }
                    }
                }
            } catch (e: Exception) {
                // 계측 실패가 앱을 죽이면 안 된다 — 조용히 종료
            }
        }, "ynav-native-log-pump")
        thread.isDaemon = true
        thread.start()
    }
}
