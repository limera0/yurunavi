// 회귀 가드: nav_screen.dart의 dispose() 안전망이 _exitNav()를 거치지 않고
// 트리거돼도(예: 부모 네비게이터 리셋 등 비정상 종료) 예외 없이 완료되는지
// 확인한다.
//
// 배경(HIGH severity 감사 발견, 2026-07-18): _finalizeAndPersistTour()가
// 과거 `ref.read(navStateProvider)`로 종료 좌표를 구했는데, Riverpod의
// ConsumerStatefulElement가 State.dispose()보다 먼저 자신의 구독을 정리하는
// 순서 때문에 dispose() 경로에서 이 ref.read()가 StateError를 던졌다(감사가
// 이 프로젝트의 정확한 flutter_riverpod 버전으로 최소 재현 위젯 테스트로
// 실측 확인). 수정 후에는 TourRecorder.lastPos(ref/context 의존 없음)로
// 종료 좌표를 구하므로 이 경로에서 ref를 전혀 건드리지 않는다 — 이 테스트는
// 그 사실을 실제 NavScreen 위젯의 mount→GPS fix→비정상 unmount 시퀀스로
// 고정(lock in)한다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus_platform_interface/messages.g.dart';
import 'package:yurunavi/features/navigation/presentation/nav_screen.dart';
import 'package:yurunavi/features/navigation/providers/nav_state_provider.dart';

/// route_progress_arrival_test.dart 등 기존 테스트와 동일한 패턴 — 실제
/// Geolocator/locationStreamProvider 구독 없이 상태만 수동으로 밀어넣는다.
class _FakeNavStateNotifier extends NavStateNotifier {
  @override
  NavigationState? build() => null;
}

NavigationState _fixAt(LatLng pos) => NavigationState(
      pos: pos,
      speedKmh: 12,
      moving: true,
      headingDeg: 0,
      firstFix: true,
      fixAt: DateTime.now(),
      stale: false,
    );

const _geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
const _ttsChannel = MethodChannel('flutter_tts');
final _wakelockToggleChannel = BasicMessageChannel<Object?>(
  'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
  WakelockPlusApi.pigeonChannelCodec,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    // _startLocation()의 권한 체크를 통과시켜 navStateProvider 구독까지
    // 도달하게 만든다.
    messenger.setMockMethodCallHandler(_geolocatorChannel, (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
          return 2; // LocationPermission.whileInUse
        default:
          return null;
      }
    });

    // _initTts()가 만드는 FlutterTts 채널 호출을 전부 무해하게 처리.
    messenger.setMockMethodCallHandler(_ttsChannel, (call) async => 1);

    // WakelockPlus.enable()(initState)/.disable()(dispose) 둘 다 이 Pigeon
    // 채널을 쓴다.
    messenger.setMockDecodedMessageHandler<Object?>(
      _wakelockToggleChannel,
      (Object? message) async => <Object?>[null],
    );

    // SystemChrome.setSystemUIOverlayStyle()도 initState/dispose 양쪽에서
    // 호출됨 — test/core/widgets/slider_start_button_test.dart와 동일 패턴.
    messenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_geolocatorChannel, null);
    messenger.setMockMethodCallHandler(_ttsChannel, null);
    messenger.setMockDecodedMessageHandler<Object?>(
        _wakelockToggleChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'GPS fix 수신 후 _exitNav() 없이(비정상 unmount로) 종료돼도 '
    'dispose() 안전망이 예외를 던지지 않는다',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          navStateProvider.overrideWith(() => _FakeNavStateNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: NavScreen(destination: LatLng(37.0, 127.0)),
          ),
        ),
      );

      // _startLocation()의 Geolocator await 체인 + ref.listenManual 구독이
      // 진행되도록 몇 프레임 흘려보낸다. pumpAndSettle()은 nav_screen의
      // _pulseCtrl이 무한 반복(repeat(reverse: true))이라 타임아웃되므로
      // 쓰지 않는다.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // 실 GPS fix 1건 주입 — TourRecorder.start()가 호출되어
      // _tourRecorderStarted=true / TourRecorder.lastPos가 채워진다(안전망이
      // 스킵되지 않고 실제로 트리거되게 하기 위한 전제조건).
      container.read(navStateProvider.notifier).state =
          _fixAt(const LatLng(37.001, 127.001));
      await tester.pump(const Duration(milliseconds: 20));

      // _exitNav()(Navigator.pop 경유)를 거치지 않고 위젯 트리를 통째로
      // 교체 — 부모 네비게이터 리셋 등 비정상 종료 경로를 흉내낸다.
      // NavScreen의 dispose()가 바로 이 시점에 호출된다.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));

      expect(tester.takeException(), isNull);
    },
  );
}
