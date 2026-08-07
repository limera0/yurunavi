// S5 — 정차 모드 게이트(재탐색/앰비언트 POI페치/카메라추종) 회귀 가드.
//
// 배경: HANDOFF_0807_S5_stationary_mode.md — 속도 5km/h 미만이 10초 지속되면
// "정차 모드"에 진입, isStationaryProvider가 true인 동안 nav_screen.dart의
// 재탐색 트리거·앰비언트 POI 페치·카메라 추종을 스킵한다(정차 중 GPS 지터로
// 인한 YNAV_REROUTE 폭주(분당 최대 151건 실측)와 배터리 소모 억제).
//
// 구현 선택: 정적 소스 검사 방식(nav_lifecycle_test.dart와 동일 판단 — 이
// 파일 상단 주석 참조). _NavScreenState가 private이고 풀 위젯 마운트는
// geolocator·TTS·wakelock·MapLibre 채널을 모두 모킹해야 하는 인프라 테스트가
// 되므로, "특정 호출이 특정 조건에서 스킵된다"는 구조적 불변식은 소스 직독이
// 가장 직접적이고 결정론적이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const navScreenPath =
      'lib/features/navigation/presentation/nav_screen.dart';

  late String source;
  setUpAll(() {
    source = File(navScreenPath).readAsStringSync();
  });

  group('S5 — _startLocation() 리스너: 카메라추종/앰비언트POI 정차 게이트', () {
    // navStateProvider 리스너 콜백 본문 추출 — fireImmediately: true 인자
    // 직전까지.
    late String listenerBody;
    setUpAll(() {
      final pattern = RegExp(
        r'_locationSub = ref\.listenManual<NavigationState\?>\(\s*'
        r'navStateProvider,\s*'
        r'\(_, next\) \{(.*?)\},\s*'
        r'fireImmediately: true,',
        dotAll: true,
      );
      final match = pattern.firstMatch(source);
      expect(
        match,
        isNotNull,
        reason:
            '_startLocation()의 navStateProvider ref.listenManual 콜백을 찾을 수 없다 '
            '— 구조가 바뀌었으면 이 테스트의 정규식도 함께 갱신할 것',
      );
      listenerBody = match!.group(1)!;
    });

    test('isStationaryProvider를 읽어 로컬 변수로 확정한다', () {
      expect(
        listenerBody.contains('ref.read(isStationaryProvider)'),
        isTrue,
        reason: '정차 모드 판정을 매 틱 ref.read(isStationaryProvider)로 읽어야 한다',
      );
    });

    test('_recenter(...) 호출이 !isStationary 가드 안에 있다', () {
      final ifPos = listenerBody.indexOf('if (!isStationary');
      final recenterPos = listenerBody.indexOf('_recenter(');
      expect(ifPos, isNot(equals(-1)),
          reason: '"if (!isStationary" 가드가 리스너 본문에 있어야 한다');
      expect(recenterPos, isNot(equals(-1)),
          reason: '_recenter(...) 호출이 리스너 본문에 있어야 한다');

      // 가드의 if 블록이 _recenter 호출을 감싸는지 — 같은 if 문의 중괄호
      // 블록 안에서 가드 시작 직후에 _recenter가 등장해야 한다(가드와
      // _recenter 사이에 다른 최상위 return/블록 종료가 없어야 함을
      // 근사적으로 확인: 가드 이후 첫 '}'가 _recenter 호출보다 뒤에 있어야
      // 한다).
      final afterGuard = listenerBody.substring(ifPos);
      final recenterInGuard = afterGuard.indexOf('_recenter(');
      final closeBraceBeforeRecenter =
          afterGuard.substring(0, recenterInGuard).lastIndexOf('}');
      expect(
        closeBraceBeforeRecenter,
        equals(-1),
        reason:
            '_recenter(...) 호출 전에 블록이 먼저 닫히면 안 된다 — '
            '!isStationary 가드 밖으로 빠져나온 것',
      );
    });

    test(
      '_ensureLocationMarker(...)는 isStationary와 무관하게 항상 호출된다 '
      '(파란 점은 정차 중에도 최신 위치/방향 유지)',
      () {
        // _recenter 가드 블록이 끝난 뒤(다음 statement)에 조건 없이 등장해야
        // 한다 — _ensureLocationMarker 호출 앞에 'if (!isStationary'가
        // 다시 나오지 않는지 확인.
        final markerPos = listenerBody.indexOf('_ensureLocationMarker(');
        expect(markerPos, isNot(equals(-1)),
            reason: '_ensureLocationMarker(...) 호출이 리스너 본문에 있어야 한다');

        final beforeMarker = listenerBody.substring(0, markerPos);
        // _ensureLocationMarker 호출문 자체가 조건문(if) 안에 있지 않아야
        // 한다 — 직전 non-whitespace 토큰이 세미콜론 또는 '}'여야 한다
        // (조건식 열기 괄호 '(' 직후가 아니어야 함).
        final trimmed = beforeMarker.trimRight();
        expect(
          trimmed.endsWith(';') || trimmed.endsWith('}'),
          isTrue,
          reason:
              '_ensureLocationMarker(...) 호출 직전이 문장/블록 종료여야 한다 '
              '— 조건문 안에 들어가 있으면 안 된다. 직전 문자열: '
              '"${trimmed.substring(trimmed.length - 30 < 0 ? 0 : trimmed.length - 30)}"',
        );
      },
    );

    test('unawaited(_maybeFetchAmbientPois()) 호출이 !isStationary 가드 뒤에 있다', () {
      final guardPattern = 'if (!isStationary) unawaited(_maybeFetchAmbientPois());';
      expect(
        listenerBody.contains(guardPattern),
        isTrue,
        reason:
            'unawaited(_maybeFetchAmbientPois()) 호출은 '
            '"if (!isStationary) unawaited(_maybeFetchAmbientPois());" '
            '형태의 단일문 가드여야 한다 (현재 소스와 정확히 일치해야 함)',
      );
    });
  });

  group('S5 — _triggerReroute(): 정차 중 디바운스 타이머 등록 차단', () {
    late String body;
    setUpAll(() {
      final pattern = RegExp(
        r'void _triggerReroute\(\)\s*\{(.*?)^  \}',
        dotAll: true,
        multiLine: true,
      );
      final match = pattern.firstMatch(source);
      expect(match, isNotNull, reason: '_triggerReroute()를 찾을 수 없다');
      body = match!.group(1)!;
    });

    test('isStationary면 _offRouteDebounce 타이머 등록 전에 리턴한다', () {
      final gatePos = body.indexOf('if (ref.read(isStationaryProvider)) return;');
      final timerPos = body.indexOf('_offRouteDebounce ??=');
      expect(gatePos, isNot(equals(-1)),
          reason:
              '"if (ref.read(isStationaryProvider)) return;" 가드가 '
              '_triggerReroute()에 있어야 한다');
      expect(timerPos, isNot(equals(-1)),
          reason: '_offRouteDebounce ??= Timer(...) 등록부가 있어야 한다');
      expect(
        gatePos < timerPos,
        isTrue,
        reason: 'isStationary 가드가 디바운스 타이머 등록보다 앞서야 한다 '
            '— 정차 중엔 타이머 자체를 등록하지 않아야 재탐색 폭주가 막힌다',
      );
    });
  });

  group('S5 — offsetOrigin 재탐색 origin 오프셋 40m → 50m', () {
    test('_reroute()의 offsetOrigin 호출이 50을 쓴다', () {
      expect(
        source.contains(
            "offsetOrigin(origin.latitude, origin.longitude, heading, 50)"),
        isTrue,
        reason:
            '_reroute()와 _openCourseSheet() 두 곳 모두 offsetOrigin(..., 50) '
            '이어야 한다(정확한 호출부 구분은 카운트로 확인)',
      );
      // 두 호출부 모두 40이 아닌 50으로 바뀌었는지 — 정확히 2회 등장.
      final matches =
          'offsetOrigin(origin.latitude, origin.longitude, heading, 50)'
              .allMatches(source)
              .length;
      expect(
        matches,
        equals(2),
        reason:
            '_reroute():835 부근, _openCourseSheet():1684 부근 두 호출부 '
            '모두 50으로 바뀌어야 한다. 현재 일치 횟수: $matches',
      );
      expect(
        source.contains('offsetOrigin(origin.latitude, origin.longitude, heading, 40)'),
        isFalse,
        reason: '재탐색 origin 오프셋에 40m 리터럴이 더 이상 남아있으면 안 된다',
      );
    });
  });

  group('S5 — _addGasStationWaypoint(): 의도적으로 게이트하지 않음(결정 기록)', () {
    test('사용자 명시적 트리거이므로 isStationary 게이트를 적용하지 않는다는 결정 주석이 남아있다', () {
      final idx = source.indexOf('_addGasStationWaypoint(GasStation s)');
      expect(idx, isNot(equals(-1)),
          reason: '_addGasStationWaypoint(...)를 찾을 수 없다');
      final end = source.indexOf('\n  }', idx);
      final body = source.substring(idx, end);
      expect(
        body.contains('HANDOFF_0807_S5'),
        isTrue,
        reason:
            '_addGasStationWaypoint()가 reroute를 게이트하지 않는 결정의 근거 주석이 '
            '남아있어야 한다(리뷰어가 의도된 선택임을 알 수 있도록)',
      );
      // 게이트 없이 무조건 _reroute를 호출해야 한다 — silent: true 인자 유지.
      expect(
        body.contains('_reroute(currentPos, silent: true);'),
        isTrue,
        reason: '_reroute(currentPos, silent: true) 호출 자체는 무조건 실행돼야 한다',
      );
    });
  });
}
