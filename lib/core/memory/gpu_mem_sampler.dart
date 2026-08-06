import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// `com.westinx.yurunavi/gpu_mem` MethodChannel(네이티브 `GpuMemBridge.kt`)을 60초
/// 간격으로 호출해 `android.os.Debug.MemoryInfo` 기반 GPU/전체 메모리 근사치를
/// 진단로그(`YNAV_GPUMEM`)에 남긴다.
///
/// 배경: `loop/repro_s1b/sample.sh`가 `dumpsys meminfo`로 찍던 것과 같은 종류의
/// 정보를, 마스터의 실사용 실주행에서 앱 스스로 주기적으로 남겨 별도 실험 없이
/// 시계열 표본을 쌓는다(메모리·GPU 압박 대응 청크6 B-2).
///
/// [NativeLogBridge](logcat 펌프, EventChannel)와는 무관한 별개의 MethodChannel
/// request/response 경로다 — logcat을 읽지 않으므로 피드백 루프 위험이 없다.
///
/// [start]는 [FileLogger.init]이 `debugPrint`를 가로챈 이후에 호출해야
/// `YNAV_GPUMEM` 줄이 파일에 기록된다.
class GpuMemSampler {
  static const MethodChannel _channel =
      MethodChannel('com.westinx.yurunavi/gpu_mem');

  static Timer? _timer;

  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _sample());
  }

  static Future<void> _sample() async {
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('snapshot');
      if (result == null) return;
      final graphics = result['graphics'] as String?;
      final totalPss = result['totalPss'] as String?;
      if (graphics == null && totalPss == null) return;
      final parts = <String>[
        if (graphics != null) 'graphics=$graphics',
        if (totalPss != null) 'totalPss=$totalPss',
        'ts=${DateTime.now().toIso8601String()}',
      ];
      debugPrint('YNAV_GPUMEM ${parts.join(' ')}');
    } catch (_) {
      // 계측 실패가 앱을 죽이면 안 된다
    }
  }
}
