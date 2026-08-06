import 'package:flutter/services.dart';

import 'file_logger.dart';

/// `com.westinx.yurunavi/native_log` EventChannel(네이티브 `NativeLogBridge.kt`)을
/// 구독해 받은 줄마다 [FileLogger.writeRaw]로 흘려보낸다.
///
/// 배경: 실주행 중 화면 서브트리가 백지로 렌더되는 버그의 유력 원인은 Flutter
/// 엔진(Impeller/Vulkan) GPU 자원 할당 실패인데, 기존 [FileLogger]는 Dart
/// `debugPrint`만 가로채 네이티브 엔진 로그는 전혀 남기지 못했다. 이 구멍을
/// 메우는 계측 브리지 — debug 전용이 아니다.
///
/// [start]는 반드시 `FileLogger.init()` 이후에 호출해야 한다(그래야 `_sink`가
/// 준비돼 있다). 채널이 없거나 에러가 나도 앱이 죽으면 안 되므로 전부
/// try/catch로 감싼다.
class NativeLogBridge {
  static const EventChannel _channel =
      EventChannel('com.westinx.yurunavi/native_log');

  static void start() {
    try {
      // 앱 생애주기 전체에 걸쳐 계속 수신 — 취소 진입점이 없어도 구독 자체는
      // 채널 내부에서 유지된다. 반환값을 들고 있을 필요가 없다.
      _channel.receiveBroadcastStream().listen(
        (event) {
          try {
            if (event is String) {
              FileLogger.writeRaw(event);
            }
          } catch (_) {
            // 계측 실패가 앱을 죽이면 안 된다
          }
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      // 채널이 없거나(구버전 네이티브) 구독 자체가 실패해도 무시하고 계속 진행
    }
  }
}
