// S0: 스플래시 화면의 위치 선확보 순수 로직(acquireBootLocation) 단위 테스트.
//
// 대상은 splash_screen.dart의 위젯이 아니라 그 안의 top-level 함수
// `acquireBootLocation()`이다 — 위젯을 통째로 pump하는 방식은
// permission_handler 팝업 채널 + RoutingConfig.loadRemote()의 실제 네트워크
// 호출까지 목킹해야 해서 이 회귀 가드가 검증하려는 범위(예산 초과 시
// 타임아웃 후 진입, 실패 시 무해 통과)에 비해 과하고 플레이키해질 위험이
// 크다. 대신 geolocator MethodChannel만 목킹해 순수 로직을 직접 검증한다
// (nav_screen_tour_finalize_test.dart와 동일한 채널 목킹 패턴).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/features/auth/presentation/splash_screen.dart';

const _geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(_geolocatorChannel, null);
  });

  Map<String, dynamic> fakePositionMap(double lat, double lon) => {
        'latitude': lat,
        'longitude': lon,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'accuracy': 5.0,
        'altitude': 0.0,
        'altitude_accuracy': 0.0,
        'heading': 0.0,
        'heading_accuracy': 0.0,
        'speed': 0.0,
        'speed_accuracy': 0.0,
        'is_mocked': false,
      };

  test('getLastKnownPosition 값을 즉시 onIntermediate로 통지하고, '
      'getCurrentPosition의 더 정확한 값으로 최종 교체한다', () async {
    messenger.setMockMethodCallHandler(_geolocatorChannel, (call) async {
      switch (call.method) {
        case 'getLastKnownPosition':
          return fakePositionMap(36.0, 127.0);
        case 'getCurrentPosition':
          return fakePositionMap(36.001, 127.001);
        default:
          return null;
      }
    });

    LatLng? intermediate;
    final result = await acquireBootLocation(
      onIntermediate: (loc) => intermediate = loc,
    );

    expect(intermediate, const LatLng(36.0, 127.0));
    expect(result, const LatLng(36.001, 127.001));
  });

  test('getCurrentPosition이 예산을 넘기면 타임아웃 후 조용히 넘어가고 '
      'getLastKnownPosition 값을 그대로 반환한다(블로킹/예외 없음)', () async {
    messenger.setMockMethodCallHandler(_geolocatorChannel, (call) async {
      switch (call.method) {
        case 'getLastKnownPosition':
          return fakePositionMap(36.0, 127.0);
        case 'getCurrentPosition':
          // 절대 완료되지 않는 Future — Geolocator.getCurrentPosition()가
          // 내부적으로 .timeout(budget)을 걸어주므로 이 테스트의 짧은 budget
          // 안에 TimeoutException이 발생해야 한다.
          return Completer<dynamic>().future;
        default:
          return null;
      }
    });

    final result = await acquireBootLocation(
      budget: const Duration(milliseconds: 30),
    );

    expect(result, const LatLng(36.0, 127.0));
  });

  test('두 호출 모두 실패해도 예외 없이 null을 반환한다', () async {
    messenger.setMockMethodCallHandler(_geolocatorChannel, (call) async {
      throw PlatformException(code: 'ERROR', message: 'boom');
    });

    final result = await acquireBootLocation(
      budget: const Duration(milliseconds: 30),
    );

    expect(result, isNull);
  });

  // S0 회귀 가드 (2026-08-05 code-auditor FAIL 지적, 결함 2): _runSequence()의
  // 최초 실행 경로에서 위치 확보가 실제로 시작된 시각이 아니라 함수 진입
  // 시각(고정 t=0)을 기준으로 "남은 예산"을 계산하던 버그. 고정 지연(1.7초)
  // + 팝업 응답 시간이면 remaining이 이미 <= 0으로 계산돼, 막 시작한 확보를
  // 단 한 번도 기다리지 않고 바로 진입해버리는 죽은 코드였다. 위젯 전체를
  // pump하지 않고 그 계산/대기 규약을 뽑아낸 awaitWithinBudget()을 직접
  // 검증한다 — permission_handler 팝업 채널(별도 MethodChannel)과
  // RoutingConfig.loadRemote()의 실제 네트워크 호출까지 목킹해야 하는 전체
  // 위젯 통합 테스트는 이 회귀가 검증하려는 범위에 비해 과도하게 복잡하고
  // (AppConfig.instance 싱글턴 초기화, fake-clock과 실제 Future.delayed/
  // Future.timeout 타이머의 상호작용 등) 플레이키해질 위험이 커서 시도하지
  // 않았다 — 대신 버그의 근본 원인인 "시작 시각 앵커"를 함수 계약으로
  // 명시하고 그 계약을 여기서 직접 고정한다. `_runSequence()`의 실제 배선
  // (두 분기 각각 `DateTime.now()`를 future 생성 직전에 찍는 두 줄)은 코드
  // 리뷰로 눈에 보이게 작게 유지했다.
  group('awaitWithinBudget (결함 2 회귀 가드)', () {
    test('예산이 이미 소진된 시작 시각이면 future를 전혀 기다리지 않고 즉시 '
        'null을 반환한다 — 고정 t=0 재사용 버그를 결정론적으로 재현', () async {
      final startedAt = DateTime(2026, 1, 1);
      // "함수 진입 시각을 고정 앵커로 재사용"하던 옛 버그를 흉내: now()가
      // startedAt으로부터 이미 budget을 넘긴 시각을 반환하도록 고정한다.
      DateTime fakeNow() => startedAt.add(const Duration(seconds: 5));
      // 절대 완료되지 않는 future — 만약 구현이 remaining<=0인데도 이걸
      // await해버리면(회귀) 이 테스트는 기본 타임아웃까지 걸려 실패한다.
      final hang = Completer<LatLng?>().future;

      final result = await awaitWithinBudget(
        hang,
        startedAt: startedAt,
        now: fakeNow,
        budget: const Duration(seconds: 3),
      );

      expect(result, isNull);
    });

    test('예산이 남아있으면 그 안에서 future 결과를 그대로 반환한다', () async {
      final result = await awaitWithinBudget(
        Future.value(const LatLng(1.0, 2.0)),
        startedAt: DateTime.now(),
        budget: const Duration(seconds: 3),
      );

      expect(result, const LatLng(1.0, 2.0));
    });

    test('예산 안에서 future가 완료되지 않으면 타임아웃 후 예외 없이 null을 '
        '반환한다', () async {
      final result = await awaitWithinBudget(
        Completer<LatLng?>().future,
        startedAt: DateTime.now(),
        budget: const Duration(milliseconds: 30),
      );

      expect(result, isNull);
    });
  });
}
