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

  // §3-1 항목 4: dispose 중 setGeoJsonSource 콜백 도착 → 게이트 동작 검증.
  //
  // _canCallMap() 게이트가 dispose() 진입 즉시 _isDisposing=true 로 막히는 구조적
  // 사실을 소스 텍스트로 검증한다. "native view만 살아있고 controller reference만
  // 죽은" 경우를 잡지 못하던 _mlCtrl? 널가드의 한계를 3겹 게이트로 보완했음.
  test(
    'dispose_sets_isDisposing_before_stream_close_to_gate_map_calls',
    () {
      // 1. _isDisposing 필드가 선언돼 있어야 한다.
      expect(
        source.contains('bool _isDisposing = false;'),
        isTrue,
        reason: '_isDisposing 플래그가 State 필드로 선언돼 있어야 한다',
      );

      // 2. dispose() 본문에서 _isDisposing = true가 스트림 close보다 앞에 있어야 한다.
      // 소스에서 dispose() 메서드 전체를 추출해 순서를 확인한다.
      final disposePattern = RegExp(
        r'void dispose\(\)\s*\{(.*?)super\.dispose\(\);',
        dotAll: true,
      );
      final disposeMatch = disposePattern.firstMatch(source);
      expect(
        disposeMatch,
        isNotNull,
        reason: 'dispose() 메서드가 nav_screen.dart에 존재해야 한다',
      );
      final disposeBody = disposeMatch!.group(1)!;
      final disposingPos = disposeBody.indexOf('_isDisposing = true');
      final streamClosePos = disposeBody.indexOf('_locationSub?.close()');
      expect(
        disposingPos,
        isNot(equals(-1)),
        reason: 'dispose()에서 _isDisposing = true 세팅이 있어야 한다',
      );
      expect(
        streamClosePos,
        isNot(equals(-1)),
        reason: 'dispose()에서 _locationSub?.close() 호출이 있어야 한다',
      );
      expect(
        disposingPos < streamClosePos,
        isTrue,
        reason:
            '_isDisposing = true 는 _locationSub?.close() 보다 먼저 세팅돼야 한다 '
            '— 비동기 콜백이 스트림 close 이후에 도달해도 게이트가 막도록',
      );

      // 3. _canCallMap() 게이트가 _isDisposing을 포함해야 한다.
      final canCallMapPattern = RegExp(
        r'bool _canCallMap\(\)\s*=>\s*([^;]+);',
        dotAll: true,
      );
      final gateMatch = canCallMapPattern.firstMatch(source);
      expect(
        gateMatch,
        isNotNull,
        reason: '_canCallMap() 메서드가 nav_screen.dart에 존재해야 한다',
      );
      final gateExpr = gateMatch!.group(1)!;
      expect(
        gateExpr.contains('_isDisposing'),
        isTrue,
        reason: '_canCallMap() 게이트가 _isDisposing 플래그를 검사해야 한다',
      );
      expect(
        gateExpr.contains('mounted'),
        isTrue,
        reason: '_canCallMap() 게이트가 mounted를 검사해야 한다',
      );
      expect(
        gateExpr.contains('_isInPip'),
        isTrue,
        reason: '_canCallMap() 게이트가 _isInPip을 검사해야 한다',
      );

      // 4. 주요 호출부들이 게이트를 경유함을 확인한다.
      // _canCallMap() 호출 수 — 게이트가 실제로 호출부에 적용됐는지 최소 개수 보장.
      final gateCallCount = '_canCallMap()'.allMatches(source).length;
      // _canCallMap 정의 1회 + 적용 최소 9곳(함수 진입부+인라인 합계)
      expect(
        gateCallCount,
        greaterThanOrEqualTo(10),
        reason: '_canCallMap()이 정의 포함 최소 10회 이상 등장해야 한다 '
            '(정의 1 + 호출부 9+). 현재: $gateCallCount',
      );
    },
  );
}
