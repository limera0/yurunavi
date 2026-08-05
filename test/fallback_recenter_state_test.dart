// S0 회귀 가드 (2026-08-05 code-auditor FAIL 지적, 결함 1):
// FallbackRecenterState는 "폴백 좌표로 열렸는가"와 "카메라가 실측 fix로
// 보정됐는가"를 분리한 순수 상태기계다. 과거 버그는 이 둘을
// `_openedAtFallback` 하나로 겹쳐 게이트를 걸어서, boot-seed로 이미
// _lastKnown이 채워진 세션(=_openedAtFallback == false)에서 그 이후 도착하는
// 진짜 첫 GPS fix가 컨트롤러 준비 전 레이스를 타면 카메라가 세션 내내
// 부트 시점 좌표에 고정되는 회귀였다. 위젯/MapLibre 플랫폼뷰 없이 순수
// 로직만으로 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/features/map/presentation/main_map_screen.dart';

void main() {
  group('FallbackRecenterState', () {
    test('컨트롤러 미준비 상태에서는 항상 보류한다(폴백으로 열렸는지와 무관) '
        '— 결함 1의 핵심 회귀 가드', () {
      final s = FallbackRecenterState();
      const loc = LatLng(37.5, 127.0);

      // boot-seed로 이미 실제 위치가 시드돼 있던 세션(과거 버그에서
      // _openedAtFallback == false였을 상황)이라도, 컨트롤러가 아직
      // 준비되지 않았으면 fix를 보류해야 한다.
      final immediate = s.onFixArrived(loc, ctrlReady: false);

      expect(immediate, isNull, reason: '컨트롤러 미준비 시 즉시 적용값을 반환하면 안 된다');
      expect(s.pending, loc);
      expect(s.corrected, isFalse);
    });

    test('onMapCreated에서 보류값을 소비해 적용하고 보정됨으로 전환한다', () {
      final s = FallbackRecenterState();
      const loc = LatLng(37.5, 127.0);
      s.onFixArrived(loc, ctrlReady: false);

      final applied = s.consumePendingOnMapCreated();

      expect(applied, loc);
      expect(s.corrected, isTrue);
      expect(s.pending, isNull, reason: '적용 후에는 보류값을 비워야 한다');
    });

    test('보류값이 없으면 onMapCreated는 아무것도 반환하지 않는다', () {
      final s = FallbackRecenterState();
      expect(s.consumePendingOnMapCreated(), isNull);
      expect(s.corrected, isFalse);
    });

    test('컨트롤러가 이미 준비돼 있으면 즉시 적용값을 반환하고 곧바로 보정됨으로 '
        '전환한다(보류를 거치지 않음)', () {
      final s = FallbackRecenterState();
      const loc = LatLng(37.5, 127.0);

      final immediate = s.onFixArrived(loc, ctrlReady: true);

      expect(immediate, loc);
      expect(s.corrected, isTrue);
      expect(s.pending, isNull);
    });

    test('카메라가 한 번 실측 fix로 보정된 뒤에는 이후 보류값이 있어도 '
        'onMapCreated가 다시 잡아채지 않는다', () {
      final s = FallbackRecenterState();
      // 첫 fix: 컨트롤러 준비됨 → 즉시 보정.
      s.onFixArrived(const LatLng(37.5, 127.0), ctrlReady: true);
      expect(s.corrected, isTrue);

      // 방어적 시나리오: 그 뒤에 컨트롤러 미준비 상태로 또 다른 fix가
      // onFixArrived를 탄다 해도(정상 흐름에서는 onMapCreated 이후
      // _mlCtrl이 다시 null이 되지 않으므로 사실상 일어나지 않는다),
      // consumePendingOnMapCreated()는 이미 corrected == true이므로
      // 그 값을 잡아채 적용하지 않아야 한다.
      s.onFixArrived(const LatLng(38.0, 128.0), ctrlReady: false);
      final applied = s.consumePendingOnMapCreated();

      expect(applied, isNull);
    });

    test('컨트롤러 미준비 상태에서 fix가 여러 번 도착하면 가장 최근 좌표가 '
        '보류값으로 남는다(getLastKnownPosition → 이후 실측 GPS fix 순서 반영)', () {
      final s = FallbackRecenterState();
      s.onFixArrived(const LatLng(37.0, 127.0), ctrlReady: false); // last-known
      s.onFixArrived(const LatLng(37.111, 127.111), ctrlReady: false); // 실측 GPS

      expect(s.pending, const LatLng(37.111, 127.111));
    });
  });
}
