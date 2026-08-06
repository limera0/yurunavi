package com.westinx.yurunavi

import android.os.Debug
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * GPU/전체 메모리 주기 스냅샷 채널 (메모리·GPU 압박 대응 청크6 B-2, 2026-08-06).
 *
 * 배경: `loop/repro_s1b/sample.sh`가 `dumpsys meminfo`의 Graphics/EGL mtrack·GL mtrack을
 * 찍어 M32 실기기 재현 실험에 썼는데, 그 실험 자체가 마스터 지시로 취소됐다. 같은
 * 종류의 정보를 앱 스스로 주기적으로 남기면, 마스터의 실사용 실주행에서 자연스럽게
 * 시계열 표본이 쌓인다. `dumpsys` shell 명령 실행 권한 없이, 자기 프로세스에 대해
 * `android.os.Debug` API만으로 얻을 수 있는 근사치(`summary.graphics`,
 * `summary.total-pss`)만 사용한다.
 *
 * `NativeLogBridge`(logcat 펌프, EventChannel)와는 무관한 별개의 MethodChannel
 * request/response 경로다.
 */
class GpuMemBridge(messenger: BinaryMessenger) {

    companion object {
        private const val CHANNEL = "com.westinx.yurunavi/gpu_mem"
    }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "snapshot") {
                result.success(snapshot())
            } else {
                result.notImplemented()
            }
        }
    }

    /** 얻을 수 있는 값만 채워 반환한다 — 일부(또는 전부) 못 얻어도 예외로 앱을 죽이지 않는다. */
    private fun snapshot(): Map<String, String> {
        val out = mutableMapOf<String, String>()
        try {
            val memInfo = Debug.MemoryInfo()
            Debug.getMemoryInfo(memInfo)
            memInfo.getMemoryStat("summary.graphics")
                ?.takeIf { it.isNotBlank() }
                ?.let { out["graphics"] = it }
            memInfo.getMemoryStat("summary.total-pss")
                ?.takeIf { it.isNotBlank() }
                ?.let { out["totalPss"] = it }
        } catch (e: Exception) {
            // 계측 실패가 앱을 죽이면 안 된다 — 여기까지 채운 값만이라도 반환
        }
        return out
    }
}
