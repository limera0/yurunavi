import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// `com.westinx.yurunavi/ideograph_fonts` MethodChannel(네이티브
/// `IdeographFontBridge.kt`) 래퍼 — 한글을 지원하는 시스템 폰트 목록을 조회한다.
///
/// O1 청크3 (지도 표의문자 폰트 선택 UI): `maplibre_gl` 포크가 추가한
/// `localIdeographFontFamily` 옵션에 넘길 후보 목록을 얻는 용도다. Android
/// 전용 — iOS는 채널 자체가 없으므로 플랫폼 체크를 먼저 하고 호출하지 않는다.
/// 네이티브 열거가 실패하거나(파일 없음/파싱 예외) 채널 호출 자체가 실패해도
/// 이 기능이 앱 전체를 죽이면 안 되므로 항상 빈 리스트로 폴백한다.
class IdeographFontService {
  static const MethodChannel _channel =
      MethodChannel('com.westinx.yurunavi/ideograph_fonts');

  Future<List<String>> listKoreanFonts() async {
    if (!Platform.isAndroid) return const [];
    try {
      final result = await _channel
          .invokeMethod<List<dynamic>>('listKoreanFonts')
          .timeout(const Duration(seconds: 5));
      if (result == null) return const [];
      return result.whereType<String>().toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    } on TimeoutException {
      return const [];
    } catch (_) {
      return const [];
    }
  }
}
