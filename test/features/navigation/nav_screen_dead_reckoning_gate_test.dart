// S7 — 터널 dead reckoning 중 재탐색 억제 게이트 회귀 가드.
//
// 배경: HANDOFF_0807_S7_tunnel_dead_reckoning.md §5. 터널 안에서 GPS가
// 끊기면 RouteProgressNotifier가 최근 1분 평균속도×1.05로 경로 shape를 따라
// 위치를 추정(dead reckoning)한다 — 이 추정치는 실측이 아니므로, 이 동안의
// offRoute 판정을 근거로 재탐색을 걸면 안 된다(추정 오차로 인한 불필요한
// 재탐색 폭주 방지).
//
// 구현 선택: nav_screen_stationary_gates_test.dart(S5)와 동일한 정적 소스
// 검사 패턴 — _NavScreenState가 private이고 풀 위젯 마운트는 geolocator·
// TTS·wakelock·MapLibre 채널을 모두 모킹해야 하는 인프라 테스트가 되므로,
// "특정 호출이 특정 조건에서 스킵된다"는 구조적 불변식은 소스 직독이 가장
// 직접적이고 결정론적이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const navScreenPath =
      'lib/features/navigation/presentation/nav_screen.dart';

  late String source;
  setUpAll(() {
    source = File(navScreenPath).readAsStringSync();
  });

  group('S7 — _triggerReroute(): dead reckoning 중 스킵', () {
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

    test(
      'deadReckoning==true면 _offRouteDebounce 타이머 등록 전에 리턴한다 '
      '(isStationary 가드 바로 옆)',
      () {
        final stationaryGatePos =
            body.indexOf('if (ref.read(isStationaryProvider)) return;');
        final drGatePos = body.indexOf(
            'if (ref.read(routeProgressProvider)?.deadReckoning == true) return;');
        final timerPos = body.indexOf('_offRouteDebounce ??=');

        expect(stationaryGatePos, isNot(equals(-1)),
            reason: 'S5의 isStationary 가드가 여전히 있어야 한다(S7이 그 옆에 추가됨)');
        expect(drGatePos, isNot(equals(-1)),
            reason:
                '"if (ref.read(routeProgressProvider)?.deadReckoning == true) return;" '
                '가드가 _triggerReroute()에 있어야 한다');
        expect(timerPos, isNot(equals(-1)),
            reason: '_offRouteDebounce ??= Timer(...) 등록부가 있어야 한다');

        expect(
          stationaryGatePos < drGatePos,
          isTrue,
          reason: 'S7 가드는 S5 isStationary 가드 바로 다음에 와야 한다(HANDOFF 지정 위치)',
        );
        expect(
          drGatePos < timerPos,
          isTrue,
          reason:
              'deadReckoning 가드가 디바운스 타이머 등록보다 앞서야 한다 — '
              '추정 위치 기반 오탐으로 타이머 자체를 등록하지 않아야 한다',
        );
      },
    );
  });
}
