// 회귀 가드: didChangeAppLifecycleState가 inactive/hidden 상태에서
// _maybeEnterPip()를 트리거하지 않음을 결정론적으로 검증한다.
//
// 배경(2026-08-05): 알림창 내림·스크린샷·엣지패널 조작만으로 inactive가 발화해
// 내비가 PIP로 튀어 안내가 끊기는 결함이 실확인됐다. 정상 경로는 이미
// nav_pip_hint 채널(onUserLeaveHint 포워딩)과 Auto-PIP(API 31+)가 커버하므로
// lifecycle 분기 자체를 제거했다. 이 테스트는 그 불변식을 잠근다.
//
// 구현 선택: 정적 파일 검사 방식 채택.
// _NavScreenState가 private이라 위젯 마운트 없이는 메서드를 직접 관찰할 수
// 없고, NavScreen 풀 마운트는 AndroidPIP·geolocator·TTS·wakelock 채널 모킹을
// 모두 요구해 인프라 코드 테스트가 된다. didChangeAppLifecycleState의 불변식은
// "특정 호출이 존재하지 않는다"는 구조적 사실이므로 소스 파일 직독이 가장
// 직접적이고 결정론적인 검증 수단이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const navScreenPath =
      'lib/features/navigation/presentation/nav_screen.dart';

  late String source;

  setUpAll(() {
    source = File(navScreenPath).readAsStringSync();
  });

  test(
    'didChangeAppLifecycleState_no_longer_triggers_pip_on_inactive_hidden',
    () {
      // didChangeAppLifecycleState 메서드 본문만 추출한다.
      // 패턴: 오버라이드 선언부터 다음 @override 또는 메서드 선언 이전까지.
      final methodPattern = RegExp(
        r'void didChangeAppLifecycleState\(AppLifecycleState state\)\s*\{([^}]*)\}',
        dotAll: true,
      );
      final match = methodPattern.firstMatch(source);
      expect(
        match,
        isNotNull,
        reason: 'didChangeAppLifecycleState 메서드가 nav_screen.dart에 존재해야 한다',
      );

      final body = match!.group(1)!;

      // 핵심 불변식: 메서드 본문에 _maybeEnterPip 호출이 없어야 한다.
      expect(
        body.contains('_maybeEnterPip'),
        isFalse,
        reason:
            'didChangeAppLifecycleState가 _maybeEnterPip()를 직접 호출해서는 안 된다. '
            'PIP 진입은 nav_pip_hint 채널과 Auto-PIP가 전담한다.',
      );

      // 부가 검증: debugPrint 진단 로그는 유지돼야 한다.
      expect(
        body.contains("debugPrint('YNAV_LIFECYCLE"),
        isTrue,
        reason: 'YNAV_LIFECYCLE 진단 로그는 유지돼야 한다',
      );
    },
  );
}
