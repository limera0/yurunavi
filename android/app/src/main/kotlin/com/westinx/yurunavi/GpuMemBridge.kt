package com.westinx.yurunavi

import android.os.Debug
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
 *
 * `cmaFree`/`cmaTotal`(2026-08-14, `RECON_0814_memory_management_research.md` 후속):
 * `/proc/meminfo`의 커널 CMA(연속메모리할당자) 풀 크기. flutter/flutter#187905가
 * 지목한 실패 모드("시스템 RAM은 멀쩡한데 CmaFree만 바닥나며 Impeller-Vulkan 렌더러가
 * 멈추고 글리프 아틀라스가 깨짐")를 감지하기 위한 것 — `summary.graphics`/`total-pss`는
 * 이 신호를 반영 못 한다는 게 그 이슈에서 확인된 사실이라 별도로 추가한다. 이 프로세스가
 * CMA를 직접 점유하는 게 아니라 커널 전역 풀이라 `/proc/meminfo`는 앱 권한 없이도 읽힌다.
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
        readProcMeminfoCma(out)
        return out
    }

    /**
     * `/proc/meminfo`에서 `CmaFree:`/`CmaTotal:` 줄만 뽑아 kB 단위 숫자만 채운다
     * (단위 `kB` 접미사는 버림 — `graphics`/`totalPss`도 단위 없는 숫자 문자열이라
     * 같은 로그 줄에서 형식을 통일해야 나중에 스크립트로 파싱하기 쉽다).
     */
    private fun readProcMeminfoCma(out: MutableMap<String, String>) {
        try {
            File("/proc/meminfo").forEachLine { line ->
                when {
                    line.startsWith("CmaFree:") ->
                        out["cmaFree"] = line.removePrefix("CmaFree:").trim().removeSuffix("kB").trim()
                    line.startsWith("CmaTotal:") ->
                        out["cmaTotal"] = line.removePrefix("CmaTotal:").trim().removeSuffix("kB").trim()
                }
            }
        } catch (e: Exception) {
            // 기기에 따라 CMA 필드 자체가 없거나 읽기 실패할 수 있다 — 무시하고 나머지 값만 반환
        }
    }
}
