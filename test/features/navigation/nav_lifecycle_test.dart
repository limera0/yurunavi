// 회귀 가드: S3b 청크1 — PIP 폐기 후 dispose-race 게이트 불변식 검증.
//
// 배경(2026-08-05): 알림창 내림·스크린샷·엣지패널 조작만으로 inactive가 발화해
// 내비가 PIP로 튀어 안내가 끊기는 결함이 실확인됐다. S3 청크1에서 lifecycle
// 분기 자체를 제거했고, S3b 청크1에서 PIP 코드 전량을 폐기했다.
// didChangeAppLifecycleState는 청크2(플로팅 오버레이)에서 재활용 예정이므로
// 오버라이드 자체가 남아있는지만 검증한다.
//
// 구현 선택: 정적 파일 검사 방식 채택.
// _NavScreenState가 private이라 위젯 마운트 없이는 메서드를 직접 관찰할 수
// 없고, NavScreen 풀 마운트는 geolocator·TTS·wakelock 채널 모킹을
// 모두 요구해 인프라 코드 테스트가 된다. 불변식은 "특정 호출이 존재하지 않는다"는
// 구조적 사실이므로 소스 파일 직독이 가장 직접적이고 결정론적인 검증 수단이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const navScreenPath =
      'lib/features/navigation/presentation/nav_screen.dart';

  // ── S3b 청크3: 플로팅 오버레이 라이프사이클 회귀 가드 ────────────────────────
  //
  // 구현 선택: 정적 소스 검사 방식.
  //
  // _NavScreenState가 private이고 NavScreen 풀 마운트는 geolocator·TTS·
  // wakelock·MapLibre 채널을 모두 모킹해야 하므로 인프라 테스트가 된다.
  // 불변식("inactive/detached에 반응 없음", "paused/hidden에 show 호출")은
  // 구조적 사실이므로 소스 직독이 가장 직접적이고 결정론적이다.
  // (기존 테스트와 동일한 판단 — 파일 상단 주석 참조)
  //
  // 사례 (f) — dispose-race 스킵 이유:
  //   NavFloatingOverlay.detach() → hide() 는 dispose() 에서
  //   _isDisposing=true 세팅 전에 호출된다(순서 고정: 소스 L418 vs L421).
  //   Dart 래퍼에 별도 "이미 disposing" 게이트는 없으나, hide() 자체가
  //   Platform.isAndroid 가드로 시작하고 MethodChannel 예외를 모두 catch하므로
  //   스트레이 콜백이 throw할 경로가 없다. 테스트 없이 코드 주석으로 대체한다.

  group('S3b 청크3 — 플로팅 오버레이 라이프사이클 불변식', () {
    late String source;
    setUpAll(() {
      source = File(navScreenPath).readAsStringSync();
    });

    // ─── 사례 (a) paused → show ───────────────────────────────────────────────
    test(
      'paused_state_calls_floating_overlay_show',
      () {
        // didChangeAppLifecycleState 블록 추출
        final lifecycleBlockPattern = RegExp(
          r'void didChangeAppLifecycleState\(AppLifecycleState state\)(.*?)^  \}',
          dotAll: true,
          multiLine: true,
        );
        final match = lifecycleBlockPattern.firstMatch(source);
        expect(
          match,
          isNotNull,
          reason: 'didChangeAppLifecycleState가 nav_screen.dart에 있어야 한다',
        );
        final body = match!.group(1)!;

        // paused 케이스 직후에 NavFloatingOverlay.show 호출이 있어야 한다.
        expect(
          body.contains('AppLifecycleState.paused'),
          isTrue,
          reason: 'paused 케이스가 존재해야 한다',
        );
        // paused와 show는 같은 switch arm에서 fall-through로 묶여야 한다.
        // paused 이후 show() 등장 순서를 인덱스로 확인한다.
        final pausedPos = body.indexOf('AppLifecycleState.paused');
        final showPos = body.indexOf('NavFloatingOverlay.show');
        expect(
          showPos,
          isNot(equals(-1)),
          reason: 'NavFloatingOverlay.show() 호출이 lifecycle 블록 내에 있어야 한다',
        );
        expect(
          pausedPos < showPos,
          isTrue,
          reason: 'paused case가 NavFloatingOverlay.show() 호출보다 앞에 있어야 한다',
        );
      },
    );

    // ─── 사례 (b) hidden → show ───────────────────────────────────────────────
    test(
      'hidden_state_calls_floating_overlay_show',
      () {
        final lifecycleBlockPattern = RegExp(
          r'void didChangeAppLifecycleState\(AppLifecycleState state\)(.*?)^  \}',
          dotAll: true,
          multiLine: true,
        );
        final match = lifecycleBlockPattern.firstMatch(source);
        expect(match, isNotNull);
        final body = match!.group(1)!;

        expect(
          body.contains('AppLifecycleState.hidden'),
          isTrue,
          reason: 'hidden 케이스가 존재해야 한다',
        );
        final hiddenPos = body.indexOf('AppLifecycleState.hidden');
        final showPos = body.indexOf('NavFloatingOverlay.show');
        expect(showPos, isNot(equals(-1)));
        // hidden은 paused와 fall-through로 묶여 있어 hidden < show 이거나
        // hidden과 paused가 인접해 모두 show 앞에 위치해야 한다.
        // hidden이 show보다 앞에 있으면 충분하다.
        expect(
          hiddenPos < showPos,
          isTrue,
          reason:
              'hidden case가 NavFloatingOverlay.show() 호출보다 앞에 있어야 한다 '
              '(fall-through arm 공유)',
        );
      },
    );

    // ─── 사례 (c) resumed → hide ─────────────────────────────────────────────
    test(
      'resumed_state_calls_floating_overlay_hide',
      () {
        final lifecycleBlockPattern = RegExp(
          r'void didChangeAppLifecycleState\(AppLifecycleState state\)(.*?)^  \}',
          dotAll: true,
          multiLine: true,
        );
        final match = lifecycleBlockPattern.firstMatch(source);
        expect(match, isNotNull);
        final body = match!.group(1)!;

        expect(
          body.contains('AppLifecycleState.resumed'),
          isTrue,
          reason: 'resumed 케이스가 존재해야 한다',
        );
        expect(
          body.contains('NavFloatingOverlay.hide'),
          isTrue,
          reason: 'NavFloatingOverlay.hide() 호출이 lifecycle 블록 내에 있어야 한다',
        );
        final resumedPos = body.indexOf('AppLifecycleState.resumed');
        final hidePos = body.indexOf('NavFloatingOverlay.hide');
        expect(
          resumedPos < hidePos,
          isTrue,
          reason: 'resumed case가 NavFloatingOverlay.hide() 호출보다 앞에 있어야 한다',
        );
      },
    );

    // ─── 사례 (d) inactive → no-op  [S3 회귀 핵심 불변식] ───────────────────
    test(
      'inactive_state_must_not_call_show_or_hide — S3_regression_guard',
      () {
        // inactive arm에서 break만 있고 show/hide 호출이 없어야 한다.
        // inactive case 이후 첫 번째 break까지의 구간에 show/hide가 없는지 확인.
        final lifecycleBlockPattern = RegExp(
          r'void didChangeAppLifecycleState\(AppLifecycleState state\)(.*?)^  \}',
          dotAll: true,
          multiLine: true,
        );
        final match = lifecycleBlockPattern.firstMatch(source);
        expect(match, isNotNull);
        final body = match!.group(1)!;

        final inactivePos = body.indexOf('AppLifecycleState.inactive');
        expect(
          inactivePos,
          isNot(equals(-1)),
          reason: 'inactive 케이스가 lifecycle switch에 존재해야 한다',
        );

        // inactive 케이스 이후 구간 추출 (switch 블록 끝까지)
        final afterInactive = body.substring(inactivePos);

        // inactive arm 안에 show() 또는 hide() 직접 호출이 없어야 한다.
        // break 전에 NavFloatingOverlay 호출이 있으면 실패.
        final breakPos = afterInactive.indexOf('break;');
        expect(
          breakPos,
          isNot(equals(-1)),
          reason: 'inactive case에 break;가 있어야 한다 (no-op 확인)',
        );
        final inactiveArm = afterInactive.substring(0, breakPos);
        expect(
          inactiveArm.contains('NavFloatingOverlay.show'),
          isFalse,
          reason:
              'inactive arm에서 NavFloatingOverlay.show()를 호출해서는 안 된다 '
              '— S3 "알림창 내림 오검출" 회귀 방지',
        );
        expect(
          inactiveArm.contains('NavFloatingOverlay.hide'),
          isFalse,
          reason:
              'inactive arm에서 NavFloatingOverlay.hide()를 호출해서는 안 된다 '
              '— S3 회귀 방지',
        );
      },
    );

    // ─── 사례 (e) detached → no-op ────────────────────────────────────────────
    test(
      'detached_state_must_not_call_show_or_hide',
      () {
        final lifecycleBlockPattern = RegExp(
          r'void didChangeAppLifecycleState\(AppLifecycleState state\)(.*?)^  \}',
          dotAll: true,
          multiLine: true,
        );
        final match = lifecycleBlockPattern.firstMatch(source);
        expect(match, isNotNull);
        final body = match!.group(1)!;

        final detachedPos = body.indexOf('AppLifecycleState.detached');
        expect(
          detachedPos,
          isNot(equals(-1)),
          reason: 'detached 케이스가 lifecycle switch에 존재해야 한다',
        );

        // detached가 inactive와 같은 fall-through arm에 묶여 있고,
        // 두 케이스 사이에 NavFloatingOverlay 호출이 없어야 한다.
        // detached 이후부터 break까지의 구간에 show/hide가 없는지 확인.
        final afterDetached = body.substring(detachedPos);
        final breakPos = afterDetached.indexOf('break;');
        expect(
          breakPos,
          isNot(equals(-1)),
          reason: 'detached case에 break;가 있어야 한다 (no-op 확인)',
        );
        final detachedArm = afterDetached.substring(0, breakPos);
        expect(
          detachedArm.contains('NavFloatingOverlay.show'),
          isFalse,
          reason: 'detached arm에서 NavFloatingOverlay.show()를 호출해서는 안 된다',
        );
        expect(
          detachedArm.contains('NavFloatingOverlay.hide'),
          isFalse,
          reason: 'detached arm에서 NavFloatingOverlay.hide()를 호출해서는 안 된다',
        );
      },
    );
  });

  // ── _currentGuidance() km/m 단위 계약 고정 ───────────────────────────────
  //
  // _currentGuidance()와 _TurnStep._formatDist()는 둘 다 private이므로
  // 외부 테스트에서 직접 호출할 수 없다. 위젯 풀 마운트는 geolocator·TTS·
  // wakelock·MapLibre 채널을 모두 모킹해야 하므로 이 단일 계약 검증을 위해
  // 프로덕션 코드에 테스트 전용 backdoor를 추가하는 것은 하드룰 위반이다.
  //
  // 대신 소스 텍스트로 단위 계약을 고정한다:
  //   "_cardRemainingM / 1000" → _formatDist(km) 호출 패턴이 코드에 존재하는지,
  //   _formatDist가 km 단위를 받아 < 1.0 이면 m 변환(×1000), ≥ 1.0 이면 km 표시함을
  //   소스 리터럴로 확인한다.
  group('_currentGuidance km/m 단위 계약 고정 (소스 검사)', () {
    late String source;
    setUpAll(() {
      source = File(navScreenPath).readAsStringSync();
    });

    test(
      'currentGuidance_divides_cardRemainingM_by_1000_before_formatDist',
      () {
        // _cardRemainingM / 1000 을 _formatDist에 넘기는 표현이 있어야 한다.
        // 이 패턴이 깨지면 "m를 km로 넘기는" 단위 버그가 재도입된 것이다.
        expect(
          source.contains('_formatDist(_cardRemainingM / 1000)'),
          isTrue,
          reason:
              '_currentGuidance()가 _cardRemainingM을 /1000 변환 후 '
              '_formatDist에 넘겨야 한다. 이 변환이 사라지면 단위 오류.',
        );
      },
    );

    test(
      'formatDist_converts_sub_1km_to_meters_and_above_1km_appends_km_suffix',
      () {
        // _TurnStep._formatDist 구현 불변식:
        // km < 1.0 이면 ×1000 반올림 + 'm' 접미사
        // km ≥ 1.0 이면 소수점1자리 + 'km' 접미사
        expect(
          source.contains("return '\${(km * 1000).round()}m';"),
          isTrue,
          reason:
              '_formatDist가 km<1.0 구간에서 m 변환을 해야 한다 '
              '(km 단위 입력 → m 문자열 출력)',
        );
        expect(
          source.contains("return '\${km.toStringAsFixed(1)}km';"),
          isTrue,
          reason:
              '_formatDist가 km≥1.0 구간에서 km 접미사를 붙여야 한다',
        );
      },
    );
  });


  late String source;

  setUpAll(() {
    source = File(navScreenPath).readAsStringSync();
  });

  test(
    'pip_code_fully_removed_from_nav_screen',
    () {
      // S3b 청크1 불변식: PIP 관련 심볼이 소스에 남지 않아야 한다.
      expect(
        source.contains('android_pip'),
        isFalse,
        reason: 'android_pip import가 nav_screen.dart에 남아있어서는 안 된다',
      );
      expect(
        source.contains('AndroidPIP'),
        isFalse,
        reason: 'AndroidPIP 참조가 nav_screen.dart에 남아있어서는 안 된다',
      );
      expect(
        source.contains('_isInPip'),
        isFalse,
        reason: '_isInPip 필드가 nav_screen.dart에 남아있어서는 안 된다',
      );
      expect(
        source.contains('_pipHintChannel'),
        isFalse,
        reason: '_pipHintChannel이 nav_screen.dart에 남아있어서는 안 된다',
      );
      expect(
        source.contains('_maybeEnterPip'),
        isFalse,
        reason: '_maybeEnterPip()이 nav_screen.dart에 남아있어서는 안 된다',
      );
      expect(
        source.contains('_buildPipCompactView'),
        isFalse,
        reason: '_buildPipCompactView()가 nav_screen.dart에 남아있어서는 안 된다',
      );
    },
  );

  // §3-1 항목 4: dispose 중 setGeoJsonSource 콜백 도착 → 게이트 동작 검증.
  //
  // _canCallMap() 게이트가 dispose() 진입 즉시 _isDisposing=true 로 막히는 구조적
  // 사실을 소스 텍스트로 검증한다. "native view만 살아있고 controller reference만
  // 죽은" 경우를 잡지 못하던 _mlCtrl? 널가드의 한계를 게이트로 보완했음.
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

      // 3. _canCallMap() 게이트가 _isDisposing과 mounted를 포함해야 한다.
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
      // S3b 청크1: _isInPip은 폐기됐으므로 게이트에서 제거됐어야 한다.
      expect(
        gateExpr.contains('_isInPip'),
        isFalse,
        reason: '_canCallMap() 게이트에서 _isInPip 조건이 제거됐어야 한다 (S3b 청크1)',
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
