// S5 — 정차 모드에 따른 locationStreamProvider GPS 정확도/거리필터 전환 +
// NavStateNotifier 재구독 안전성 회귀 가드.
//
// 배경: HANDOFF_0807_S5_stationary_mode.md §5. stationaryModeProvider가
// 바뀌면 Riverpod가 locationStreamProvider를 재생성한다(기존
// Geolocator.getPositionStream 구독이 끊기고 새로 시작됨) — 이 테스트는
// (a) 정차/이동 각 상태에서 실제로 다른 accuracy/distanceFilter로 구독하는지,
// (b) 재구독 전후로 NavStateNotifier가 예외 없이 동작하는지(재구독 직후
// fix 처리 경로에 널 참조·속도 스파이크가 없는지)를 검증한다.
//
// 구현 선택: 실제 geolocator 플러그인의 EventChannel/MethodChannel을 직접
// 모킹해 locationStreamProvider·NavStateNotifier 양쪽 모두 오버라이드 없이
// 실물 그대로 구동한다(nav_screen_tour_finalize_test.dart와 동일하게 host
// VM에서는 GeolocatorPlatform.instance가 geolocator_platform_interface의
// MethodChannelGeolocator로 남아있음 — 플랫폼별 구현(geolocator_android 등)은
// 플러그인 레지스트런트를 통해서만 교체되고 flutter test는 이를 실행하지
// 않는다). NavStateNotifier의 _onFix/_tickSpeed는 private이라 소스가 다른
// 파일에서는 이 경로 외에 직접 구동할 방법이 없다.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yurunavi/features/map/providers/map_providers.dart';
import 'package:yurunavi/features/navigation/providers/nav_state_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _geoMethodChannel = MethodChannel('flutter.baseflow.com/geolocator');
const _geoEventChannel =
    EventChannel('flutter.baseflow.com/geolocator_updates');

Map<String, dynamic> _positionMap({
  required double lat,
  required double lng,
  required double speed,
  double heading = 0,
}) =>
    {
      'latitude': lat,
      'longitude': lng,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'altitude': 0.0,
      'altitude_accuracy': 0.0,
      'accuracy': 5.0,
      'heading': heading,
      'heading_accuracy': 0.0,
      'speed': speed,
      'speed_accuracy': 0.0,
      'floor': null,
      'is_mocked': false,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final listenArgs = <Map<Object?, Object?>>[];
  var cancelCount = 0;
  MockStreamHandlerEventSink? currentSink;

  setUp(() {
    listenArgs.clear();
    cancelCount = 0;
    currentSink = null;

    messenger.setMockMethodCallHandler(_geoMethodChannel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return 2; // LocationPermission.whileInUse
        case 'getLastKnownPosition':
          return null;
        default:
          return null;
      }
    });

    messenger.setMockStreamHandler(
      _geoEventChannel,
      MockStreamHandler.inline(
        onListen: (args, events) {
          listenArgs.add(args as Map<Object?, Object?>);
          currentSink = events;
        },
        onCancel: (args) {
          cancelCount++;
        },
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_geoMethodChannel, null);
    messenger.setMockStreamHandler(_geoEventChannel, null);
  });

  test(
    'stationaryModeProvider 플립 시 accuracy/distanceFilter가 전환되고 '
    'NavStateNotifier가 재구독 직후 예외·속도스파이크 없이 동작한다',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // navStateProvider를 실제 앱과 동일하게 "구독 상태"로 유지한다
      // (nav_screen.dart/route_progress_provider.dart가 항상 listen 중인
      // 상태를 재현). container.read(...)만으로는 내부 ref.listen 콜백이
      // 실제로 값 갱신을 받지 못함을 실측 확인했다 — 외부 리스너가 없으면
      // Riverpod가 이 provider의 알림 스케줄을 펌프하지 않는다.
      container.listen<NavigationState?>(
          navStateProvider, (_, _) {}, fireImmediately: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(listenArgs, hasLength(1), reason: '최초 구독 1회만 발생해야 한다');
      expect(listenArgs[0]['distanceFilter'], 0,
          reason: '이동 중 기본값은 distanceFilter 0을 유지해야 한다');
      expect(
        listenArgs[0]['accuracy'],
        LocationAccuracy.bestForNavigation.index,
        reason: '이동 중 기본 정확도는 bestForNavigation이어야 한다',
      );

      // 이동 중 fix 2건 주입 (speed 단위는 m/s).
      currentSink!.success(_positionMap(lat: 37.0, lng: 127.0, speed: 10.0));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      currentSink!
          .success(_positionMap(lat: 37.0005, lng: 127.0005, speed: 10.0));
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final beforeState = container.read(navStateProvider);
      expect(beforeState, isNotNull);
      expect(beforeState!.speedKmh.isFinite, isTrue);
      expect(beforeState.speedKmh, greaterThan(0),
          reason: '재구독 전 정상 이동 상태(양수 속도)여야 다음 검증이 의미있다');

      // 정차 모드로 전환. 실제로는 StationaryDetector가 10초 지속 후
      // 갱신하지만, 이 테스트는 "전환이 일어났을 때" 재구독 메커니즘 자체의
      // 안전성을 검증하는 것이 목적이므로 플래그를 직접 뒤집는다(타이밍
      // 시뮬레이션은 stationary_detector_test.dart가 이미 커버).
      container.read(stationaryModeProvider.notifier).state = true;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cancelCount, greaterThanOrEqualTo(1),
          reason: '이전 EventChannel 구독이 재구독 전에 취소돼야 한다');
      expect(listenArgs, hasLength(2), reason: '재구독으로 두 번째 listen이 발생해야 한다');
      expect(listenArgs[1]['distanceFilter'], 15,
          reason: '정차 중엔 distanceFilter 15로 낮춰야 한다(HANDOFF_0807_S5 §5)');
      expect(
        listenArgs[1]['accuracy'],
        LocationAccuracy.high.index,
        reason: '정차 중엔 accuracy를 한 단계 낮춘 high여야 한다',
      );

      // 재구독 직후 fix 처리 경로 — 예외 없이 동작해야 한다(널 참조·상태
      // 불일치 없음).
      expect(
        () => currentSink!
            .success(_positionMap(lat: 37.001, lng: 127.001, speed: 0.5)),
        returnsNormally,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final afterState = container.read(navStateProvider);
      expect(afterState, isNotNull);
      expect(afterState!.speedKmh.isFinite, isTrue,
          reason: '재구독 직후 speedKmh가 NaN/Infinity로 튀면 안 된다');
      expect(afterState.speedKmh, greaterThanOrEqualTo(0));
      // 재구독 직후 잔여 상태(_posBuffer/_vPrev 등)로 인한 속도 스파이크가
      // 없어야 한다 — 새 fix가 저속(0.5m/s)이므로 결과도 낮은 범위에 있어야
      // 한다.
      expect(afterState.speedKmh, lessThan(50),
          reason: '재구독 직후 저속 fix가 비정상적으로 고속 스파이크를 만들면 안 된다');

      // 정차 해제(속도 회복) — 다시 이동 중 기본 설정으로 되돌아가고, 세 번째
      // 재구독도 예외 없이 처리돼야 한다.
      container.read(stationaryModeProvider.notifier).state = false;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(listenArgs, hasLength(3), reason: '정차 해제로 세 번째 재구독이 발생해야 한다');
      expect(listenArgs[2]['distanceFilter'], 0);
      expect(listenArgs[2]['accuracy'], LocationAccuracy.bestForNavigation.index);

      expect(
        () => currentSink!
            .success(_positionMap(lat: 37.002, lng: 127.002, speed: 12.0)),
        returnsNormally,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final finalState = container.read(navStateProvider);
      expect(finalState, isNotNull);
      expect(finalState!.speedKmh.isFinite, isTrue);
    },
  );
}
