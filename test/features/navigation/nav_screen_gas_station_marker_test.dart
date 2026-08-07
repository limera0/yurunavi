// S8 §2 — 주유소 경유지 마커 미표시 회귀 가드.
//
// 배경: HANDOFF_0807_S8_ui_remainder.md §2. `_initDestLayer()`가
// `widget.waypoints`(불변, nav_screen 생성 시점 고정)를 순회해 심볼을
// 찍는데 `_destLayerReady` 가드로 1회만 실행됐다. 주행 중
// `_addGasStationWaypoint()`가 추가하는 건 `_liveWaypoints`(런타임 가변
// 복사본)뿐이라 지도엔 영영 안 그려지던 버그.
//
// 구현 선택: nav_screen_stationary_gates_test.dart(S5)/
// nav_screen_dead_reckoning_gate_test.dart(S7)와 동일한 정적 소스 검사
// 패턴 — MapLibreMapController는 실제 플랫폼 채널(MethodChannel)에 의존하는
// 서드파티 컨트롤러라 순수 mock 인스턴스화가 불가능하고, _NavScreenState
// 전체를 마운트하려면 geolocator/TTS/wakelock/MapLibre 채널을 전부 모킹해야
// 하는 무거운 인프라 테스트가 된다 — "addSymbol이 실제로 불리는지"는 이
// 소스 수준의 정적 검증으로 충분히 결정론적으로 확인 가능하다(HANDOFF
// 자체가 "정적/단위 검증"을 허용).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const navScreenPath =
      'lib/features/navigation/presentation/nav_screen.dart';

  late String source;
  setUpAll(() {
    source = File(navScreenPath).readAsStringSync();
  });

  group('S8 §2 — _initDestLayer(): _liveWaypoints 순회', () {
    late String body;
    setUpAll(() {
      final pattern = RegExp(
        r'Future<void> _initDestLayer\(\) async \{(.*?)^  \}',
        dotAll: true,
        multiLine: true,
      );
      final match = pattern.firstMatch(source);
      expect(match, isNotNull, reason: '_initDestLayer()를 찾을 수 없다');
      body = match!.group(1)!;
    });

    test('widget.waypoints가 아니라 _liveWaypoints(스냅샷)를 순회한다', () {
      expect(
        body.contains('for (final wp in List<LatLng>.of(_liveWaypoints))'),
        isTrue,
        reason:
            '_initDestLayer()는 런타임 가변 복사본 _liveWaypoints를 순회해야 '
            '주행 중 추가된 경유지(주유소 등)까지 최초 실행 시점에 커버한다. '
            '단, await 사이 _addGasStationWaypoint()의 동시 mutation을 피하려면 '
            '스냅샷 복사본(List<LatLng>.of(...))을 순회해야 한다(code-auditor 지적 — '
            'ConcurrentModificationError 위험)',
      );
      expect(
        body.contains('for (final wp in widget.waypoints)'),
        isFalse,
        reason: '불변 widget.waypoints 순회로 되돌아가면 회귀',
      );
    });
  });

  group('S8 §2 — _addGasStationWaypoint(): 레이어 초기화 이후 추가분 즉시 addSymbol', () {
    late String body;
    setUpAll(() {
      final pattern = RegExp(
        r'void _addGasStationWaypoint\(GasStation s\) \{(.*?)^  \}',
        dotAll: true,
        multiLine: true,
      );
      final match = pattern.firstMatch(source);
      expect(match, isNotNull, reason: '_addGasStationWaypoint()를 찾을 수 없다');
      body = match!.group(1)!;
    });

    test('_liveWaypoints.insert 직후 addSymbol을 호출한다', () {
      final insertPos = body.indexOf(
          '_liveWaypoints.insert(insertIdx, stationLoc);');
      final addSymbolPos = body.indexOf('_mlCtrl?.addSymbol(');

      expect(insertPos, isNot(equals(-1)),
          reason: '_liveWaypoints.insert(insertIdx, stationLoc); 를 찾을 수 없다');
      expect(addSymbolPos, isNot(equals(-1)),
          reason: '_addGasStationWaypoint()가 addSymbol을 호출하지 않는다');
      expect(insertPos < addSymbolPos, isTrue,
          reason: 'addSymbol 호출은 insert 직후여야 한다(삽입 전 좌표로 그리면 안 됨)');
    });

    test('addSymbol 호출은 _canCallMap() && _destLayerReady로 게이트된다', () {
      expect(
        body.contains('if (_canCallMap() && _destLayerReady) {'),
        isTrue,
        reason:
            '레이어가 아직 초기화되지 않았으면 _initDestLayer()의 최초 실행이 '
            '_liveWaypoints를 순회하며 커버하므로, 여기서 중복 addSymbol을 '
            '하지 않도록 게이트해야 한다',
      );
    });

    test('addSymbol의 SymbolOptions은 _initDestLayer()와 동일한 경유지 아이콘 모양을 쓴다',
        () {
      final callPattern = RegExp(
        r'_mlCtrl\?\.addSymbol\(ml\.SymbolOptions\((.*?)\)\);',
        dotAll: true,
      );
      final call = callPattern.firstMatch(body);
      expect(call, isNotNull, reason: 'addSymbol(ml.SymbolOptions(...)) 호출을 찾을 수 없다');
      final args = call!.group(1)!;

      expect(args.contains('iconImage: _kWpIcon'), isTrue);
      expect(args.contains('iconSize: _kWpIconSize'), isTrue);
      expect(args.contains("iconAnchor: 'bottom'"), isTrue);
      expect(args.contains('zIndex: 5'), isTrue);
    });
  });
}
