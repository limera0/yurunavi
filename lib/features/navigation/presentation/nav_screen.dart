import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show sin, cos, sqrt, asin;

import 'package:http/http.dart' as http;

import 'package:android_pip/android_pip.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/course_sheet.dart';
import '../../../core/widgets/daylight_bar.dart';
import '../../../services/exit_landmark_service.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/native_engine.dart';
import '../../../services/nav_foreground_service.dart';
import '../../../services/poi_icon_renderer.dart';
import '../../../services/poi_service.dart';
import '../../../services/tour_log_service.dart';
import '../../../services/voice_pack_service.dart';
import '../../../models/map_language.dart';
import '../../../models/poi.dart';
import '../../../services/routing_service.dart';
import '../../map/providers/map_providers.dart';
import '../../map/style_language_transform.dart';
import '../../settings/providers/settings_providers.dart';
import '../providers/nav_state_provider.dart';
import '../providers/route_progress_provider.dart';
import '../guidance_profile.dart';
import '../tour_recorder.dart';
import '../voice_engine.dart';
import '../../route/offset_origin.dart';

/// Camera-framing default only — never treated as the rider's location.
/// The real position arrives from the GPS stream below.
const LatLng _kInitialMapView = LatLng(37.5665, 126.9780);

/// 도착배너 종료버튼 지오펜스+속도 게이트 순수 판정 (테스트용으로 분리).
bool exitGateOpen({
  required double distanceM,
  required double speedKmh,
  double geofenceM = 30.0,
  double speedLimitKmh = 30.0,
}) =>
    distanceM <= geofenceM && speedKmh <= speedLimitKmh;

enum WaypointPassageEvent { none, arrived, passed }

/// 경유지 통과/도착 판정 순수 로직 (테스트용으로 분리). 정차 시엔 지오펜스
/// 진입 즉시 "도착"으로 처리하고, 주행 중 지나치는 경우엔 지오펜스 진입
/// 즉시가 아니라 지금까지 관측된 최근접 거리([closestDistM])보다
/// [passedMarginM] 이상 멀어진 뒤에야 "통과"로 판정한다 — 경유지 '주변'
/// 몇 미터에 들어서기만 해도(아직 도달 전이어도) 바로 통과 처리되던 문제
/// 수정(2026-07-15 밤 라이딩 회귀). 호출자는 반환된 closestDistM을 다음
/// 호출의 [closestDistM] 인자로 그대로 넘기고, arrived/passed가 나오면
/// null로 리셋해 다음 경유지에 대해 새로 추적을 시작해야 한다.
({WaypointPassageEvent event, double? closestDistM}) waypointPassageEvent({
  required double distM,
  required double speedKmh,
  required double? closestDistM,
  double arrivalM = 40.0,
  double stopSpeedKmh = 8.0,
  double passedMarginM = 10.0,
}) {
  if (distM <= arrivalM && speedKmh <= stopSpeedKmh) {
    return (event: WaypointPassageEvent.arrived, closestDistM: null);
  }
  if (distM > arrivalM && closestDistM == null) {
    return (event: WaypointPassageEvent.none, closestDistM: null);
  }
  if (closestDistM == null || distM < closestDistM) {
    return (event: WaypointPassageEvent.none, closestDistM: distM);
  }
  if (distM - closestDistM >= passedMarginM) {
    return (event: WaypointPassageEvent.passed, closestDistM: null);
  }
  return (event: WaypointPassageEvent.none, closestDistM: closestDistM);
}

/// exit(type 20/21) 카드 라벨 선택 순수 로직 (테스트용으로 분리, exitGateOpen/
/// waypointPassageEvent와 동일한 패턴). [_TurnStep._labelForType]에 그대로
/// 위임 — 구조물(다리/터널)이 인접해 있으면 그 종류를 반영한 라벨로,
/// 없으면 기존 일반 "우측/좌측으로 진출" 라벨로 폴백한다.
String turnStepLabelForType(
  int type, {
  int? roundaboutExitCount,
  bool isFinalDestination = true,
  StructureType? nearbyStructure,
}) =>
    _TurnStep._labelForType(
        type, roundaboutExitCount, isFinalDestination, nearbyStructure);

class NavScreen extends ConsumerStatefulWidget {
  final LatLng? destination;
  final List<LatLng> waypoints;
  final List<LatLng> routePolyline;
  final List<ManeuverStep> maneuvers;
  // Valhalla time은 낙관적 추정치 (~57-88 km/h 기준). TODO: 실효속도 보정 적용
  final int durationMin;

  const NavScreen({
    super.key,
    this.destination,
    this.waypoints = const [],
    this.routePolyline = const [],
    this.maneuvers = const [],
    this.durationMin = 0,
  });

  @override
  ConsumerState<NavScreen> createState() => _NavScreenState();
}

class _NavScreenState extends ConsumerState<NavScreen>
    with SingleTickerProviderStateMixin {
  ml.MapLibreMapController? _mlCtrl;
  bool _styleLoaded = false;

  String? _rawStyle;
  String? _styleJson;

  bool _locLayerReady = false;
  bool _destLayerReady = false;
  static const String _kDestIcon = 'pointer_red';
  // 기존 1.5 × 0.7 = 1.05 (핀 이미지 96px 기준, 화면상 96×1.05 ≈ 100.8px).
  static const double _kDestIconSize = 1.05;
  static const String _kWpIcon = 'pointer_yellow';
  // pointer_yellow도 pointer_red와 동일 96px 에셋 — 동일 0.7 배율 적용.
  static const double _kWpIconSize = 1.05;
  static const String _kArrowIcon = 'nav_arrow';
  // 화살표는 핀보다 눈에 띄게 크게 — 핀 배율(0.7) 대비 약 1.43배.
  static const double _kArrowIconSize = 1.0;

  static const _navRouteSourceId = 'nav-route-source';
  static const _navRouteLayerId  = 'nav-route-layer';
  static const _navRouteTraveledSourceId = 'nav-route-traveled-source';
  static const _navRouteTraveledLayerId  = 'nav-route-traveled-layer';
  // 코스 재선택 시트(재탐색 버튼)에서 선택 안 된 코스를 회색으로 비교
  // 표시하는 레이어 — main_map_screen.dart의 route-bg-source/layer와 동일한
  // 목적, nav_screen에는 지금까지 이 레이어가 없어서 재탐색 시 선택된 경로만
  // 보이고 나머지 두 코스와 비교가 안 되던 버그를 고친다.
  static const _navRouteBgSourceId = 'nav-route-bg-source';
  static const _navRouteBgLayerId  = 'nav-route-bg-layer';
  static const _navLocSourceId = 'nav-loc-source';
  static const _navLocLayerId  = 'nav-loc-layer';
  // 13-1b: 줌 레벨 기준으로 항상 켜져 있는 POI 레이어 (도착배너용 _arrivalPois와
  // 무관한 완전히 별개 기능).
  static const _navPoiSourceId = 'nav-poi-source';
  static const _navPoiLayerId  = 'nav-poi-layer';

  bool _isManualMode = false;
  // 재탐색 버튼으로 진입하는 "경로 전체 보기" 오버뷰 + 코스 재선택 시트 상태.
  // _isManualMode와 별개 플래그로 둔다 — 10초 자동복귀 타이머/배너는 이 흐름에
  // 맞지 않음 (RECON_reroute_button.md §3). 진입/종료는 시트 자신의
  // onStart/onClose 콜백이 담당한다 (버튼 재탭 토글 아님).
  bool _showCourseSheet = false;
  Timer? _recenterTimer;
  ProviderSubscription<NavigationState?>? _locationSub;

  // 투어 기록(주행 이력) — 첫 GPS fix에 시작, 실제 종료 경로(_exitNav)에서
  // 마무리+저장된다. dispose()의 안전망도 이 플래그로 중복 저장을 막는다.
  final _tourRecorder = TourRecorder();
  bool _tourRecorderStarted = false;
  bool _tourFinalizeStarted = false; // idempotency guard — see _finalizeAndPersistTour below

  // ETA — widget.durationMin 초기값, 재탐색 시 갱신
  int _durationMin = 0;

  // 다중 경유지 통과 판정 — Organic Maps의 단조증가 m_passedIdx 패턴 채택:
  // 경유지별 상태 플래그 대신 "몇 번째까지 통과했는지"만 카운트하고, 재탐색 시
  // widget.waypoints를 이 인덱스부터 슬라이스해 이미 통과한 경유지를 구조적으로
  // 배제한다 (별도 필터링 불필요).
  int _passedWaypointCount = 0;
  static const _kWaypointArrivalM = 40.0;   // 경유지 통과 판정 지오펜스 반경(m)
  static const _kWaypointStopSpeedKmh = 8.0; // 이 이하면 "정차"로 간주(도착 vs 통과 구분)
  static const _kWaypointPassedMarginM = 10.0; // 최근접점 대비 이만큼 멀어져야 "통과"
  // 현재 미통과 경유지에 대해 지금까지 관측된 최근접 거리(m). 지오펜스 진입
  // 즉시가 아니라 이 최근접점보다 _kWaypointPassedMarginM 이상 멀어졌을 때만
  // "통과"로 판정한다 — 경유지에 도달하기 전(접근 중)에 통과 이벤트가 먼저
  // 나가버리는 문제(2026-07-15 밤 라이딩 회귀) 수정. 경유지 인덱스가 바뀌면
  // (통과 처리 시) null로 리셋.
  double? _waypointClosestDistM;

  // 도착 감지
  bool _arrived = false;
  bool _saidArrival = false; // 'arrival' 음성 전용 래치 (배너/POI와 별도 트리거)
  bool _arrivalBannerVisible = false;
  List<({String name, String type})> _arrivalPois = const [];
  // 도착배너 종료버튼 지오펜스+속도 게이트 (feat/arrival-fix SPEC_arrival_v2 포팅 —
  // 정차(속도<1.0) 게이트는 실 GPS에서 안 걸려 폐기됐던 전례가 있어 채택하지 않음).
  static const _kExitGeofenceM = 30.0;  // 종료버튼 노출 지오펜스 반경(폴리라인 잔여거리 기준, m)
  static const _kExitSpeedKmh = 30.0;   // 종료버튼 노출 속도 상한(km/h)
  bool _canExit = false;
  // _canExit이 true가 된 뒤 10초 경과 시 자동 종료 — 게이트가 다시 닫히거나
  // 배너를 직접 닫으면 반드시 취소해야 한다(주행 중 화면이 갑자기 꺼지면 안 됨).
  Timer? _exitAutoCloseTimer;

  // 음성 안내
  FlutterTts? _tts;
  VoicePackService? _vps;
  int _lastAnnouncedIdx = -1;  // 중복 발화 방지 (_announceStep용)
  GuidanceProfile? _profile;
  VoiceEngine? _voiceEngine;
  StructureVoiceEngine? _structureVoiceEngine;
  CurveVoiceEngine? _curveVoiceEngine;
  ExitLandmarkService? _landmarkService;

  // progress 구독
  ProviderSubscription<RouteProgress?>? _progressSub;

  // 속도 연동 줌
  double _navZoom = 15.0; // 현재 보간 중인 줌 레벨
  double? _lastMovingZoom; // 3km/h 미만에서 줌 진동 방지용 마지막 주행 중 줌
  double? _lastHeadingDeg; // 정차/저속 시 최근 방향 유지용 (bottom-anchor 오프셋)

  // 13-1b: 상시 표시 POI (ambient) — GPS 위치 기준으로 자동 표시/갱신되는
  // 별개 레이어의 로컬 상태.
  List<Poi> _ambientPois = const [];
  DateTime? _lastAmbientFetchAt;
  LatLng? _lastAmbientFetchCenter;
  Set<PoiType> _lastAmbientFetchTypes = const {};
  // 진행 중인 fetch보다 나중에 시작된 호출이 있으면 이전 응답은 버린다(stale-response 가드).
  int _ambientFetchGen = 0;
  // 뷰포트 사각형+타입 조합 단위로 최근 조회 결과를 재사용해 패닝 왕복 시
  // 불필요한 네트워크 재조회를 막는다. 이 State 인스턴스 전용(전역 아님).
  final _poiRegionCache = PoiRegionCache();
  // _navZoom은 속도 기반으로 계속 보간되는 값이라 카테고리 임계값(11/13/14)
  // 근처에서 흔들릴 수 있다 — 진입/이탈에 0.3 히스테리시스를 둬서 경계 근처
  // 진동이 매번 "카테고리 변경"으로 잡혀 디바운스 없이 fetch가 연발하지
  // 않게 한다.
  Set<PoiType> _stickyEligibleTypes = const {};

  // 코스 재선택 시트 (재탐색 버튼) — 프리뷰 전용 페치 결과와, 취소 시 복원할
  // 원래 선택 인덱스.
  List<RouteResult> _fetchedRoutes = [];
  int? _originalSelectedIdx;
  List<List<LatLng>>? _originalAllRoutes;
  List<({double km, int mins, double windingScore})>? _originalAllRouteMeta;
  int _courseSheetReqId = 0;

  // 이탈 재탐색
  List<LatLng> _routePoints = []; // widget.routePolyline 의 가변 복사본
  // 재탐색/코스 재선택으로 _routePoints가 통째로 바뀌기 직전까지 지나온
  // 구간을 흡수해 누적하는 "그 날의 투어링" 전체 궤적. 투어링은 출발부터
  // 목적지 도착까지 이어지는 하나의 기록이라 경로가 바뀌어도 끊기면 안 됨
  // (사용자 피드백, BUGFIX_progress.md 7번). _updateRouteSplit이 매 tick
  // 이 값 + 현재 활성 경로의 지나온 구간을 합쳐 회색 레이어에 반영한다.
  List<LatLng> _traveledTrail = [];
  bool _isRerouting = false;
  Timer? _offRouteDebounce;
  static const _kDebounceSec = 3;  // 연속 이탈 확인 시간 (초)

  // 재탐색 쿨다운 + 수렴 실패 폴백 (RECON_heading_reroute.md §3)
  DateTime? _lastRerouteAt;                     // 마지막 재탐색 완료 시각
  static const _kRerouteCooldown = Duration(seconds: 8);
  final List<DateTime> _rerouteHistory = [];    // 최근 재탐색 완료 시각들
  static const _kFailureWindow = Duration(seconds: 12);
  static const _kFailureCount = 3;
  bool _rerouteFallback = false;                // true면 재탐색 중단, 기존 경로 유지
  bool _saidPassedDest = false;                 // '목적지를 지나쳤습니다' 중복 발화 방지

  late List<_TurnStep> _steps; // Valhalla maneuvers 또는 더미 폴백
  List<ManeuverStep> _maneuvers = const [];
  int _stepIdx = 0;
  double _cardRemainingM = 0.0; // 카드에 표시할 실시간 잔여 거리(m); GPS틱마다 갱신
  String? _lastForegroundText; // FGS 알림에 마지막으로 보낸 텍스트 — 중복 채널 호출 방지
  // 구조물(다리/터널) zone 비동기 페치 stale-response 가드 — _applyRouteGuidance
  // 호출마다 증가시켜, 이전 세대의 fetchStructureZones 응답이 늦게 도착해도
  // 최신 경로에 잘못 반영되지 않게 한다.
  int _routeGeneration = 0;

  // Phase B: PiP 미니창 — 다른 앱으로 전환(paused) 시 android_pip 콜백으로
  // true가 되고, PIP가 닫히거나(onPipExited) 사용자가 앱으로 복귀(onPipMaximised)하면
  // false로 되돌아온다. build()가 이 플래그로 전체 UI ↔ 컴팩트 뷰를 스위칭한다.
  bool _isInPip = false;
  AndroidPIP? _pip;
  static const MethodChannel _pipHintChannel =
      MethodChannel('com.westinx.yurunavi/nav_pip_hint');

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  /// Haversine 합산으로 폴리라인 총 거리(km)를 계산한다.
  static double _polylineKm(List<LatLng> pts) {
    if (pts.length < 2) return 0;
    const r = 6371.0; // Earth radius km
    const deg2rad = 0.017453292519943295; // pi / 180
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final lat1 = pts[i].latitude * deg2rad;
      final lat2 = pts[i + 1].latitude * deg2rad;
      final dLat = (pts[i + 1].latitude - pts[i].latitude) * deg2rad;
      final dLon = (pts[i + 1].longitude - pts[i].longitude) * deg2rad;
      final a = sin(dLat / 2) * sin(dLat / 2) +
          cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
      total += 2 * r * asin(sqrt(a));
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _routePoints = List<LatLng>.of(widget.routePolyline);
    _durationMin = widget.durationMin;
    // 주행 중 화면 꺼짐 방지
    WakelockPlus.enable();
    // Phase B: PiP 미니창. enterPipMode()는 액티비티가 아직 화면에 보이는 동안
    // 호출해야 성공한다 — didChangeAppLifecycleState(paused)는 Android onStop()
    // 이후에야 발화해 이미 늦다(실기기 검증: HOME 직후 dumpsys activity activities의
    // mLastReportedPictureInPictureMode가 계속 false로 남음). 대신 네이티브
    // onUserLeaveHint()(MainActivity.kt, onPause 이전 시점)를 nav_pip_hint 채널로
    // 포워딩받아 트리거한다. Android 전용이라 다른 플랫폼(iOS/desktop/테스트)에서는
    // 채널 핸들러도, AndroidPIP 인스턴스도 만들지 않는다.
    if (Platform.isAndroid) {
      _pip = AndroidPIP(
        onPipEntered: () {
          if (mounted) setState(() => _isInPip = true);
        },
        onPipExited: () {
          if (mounted) setState(() => _isInPip = false);
        },
        onPipMaximised: () {
          if (mounted) setState(() => _isInPip = false);
        },
      );
      _pipHintChannel.setMethodCallHandler((call) async {
        if (call.method == 'onUserLeaveHint') await _maybeEnterPip();
      });
    }
    // TTS 초기화 + 첫 안내
    _initTts();
    _applyRouteGuidance(widget.maneuvers);
    if (widget.destination == null) {
      // 목적지 없이 진입하면 즉시 빠져나간다
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _startLocation();
    unawaited(NavForegroundService.start('경로 안내 중'));
    _loadRawStyle();
  }

  Future<void> _loadRawStyle() async {
    final raw = await rootBundle.loadString('assets/images/osm_liberty_yurunavi.json');
    if (!mounted) return;
    final lang = ref.read(mapLanguageProvider).value ?? MapLanguage.korean;
    setState(() {
      _rawStyle = raw;
      _styleJson = applyMapLanguageToStyle(raw, lang);
    });
  }

  /// 다른 앱으로 전환 직전(네이티브 onUserLeaveHint → nav_pip_hint 채널) PiP
  /// 미니창 진입을 시도한다. 목적지가 없거나 수동/코스시트 모드 중이면 시도하지
  /// 않음(_startLocation의 동일 가드 패턴 참고) — 도착배너 표시 중에도 PiP 진입
  /// 자체는 막지 않는다(스코프 밖). 종료는 OS가 관리하고 onPipExited/onPipMaximised
  /// 콜백이 _isInPip을 되돌린다. PiP 미지원 기기(API<26 등)에서 enterPipMode()를
  /// 호출하면 안전하지 않을 수 있어 isPipAvailable로 먼저 확인한다.
  Future<void> _maybeEnterPip() async {
    final pip = _pip;
    if (pip == null ||
        widget.destination == null ||
        _isManualMode ||
        _showCourseSheet) {
      return;
    }
    if (!await AndroidPIP.isPipAvailable) return;
    await pip.enterPipMode();
  }

  @override
  void dispose() {
    if (!_tourFinalizeStarted) {
      unawaited(_finalizeAndPersistTour());
    }
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.dark,
    ));
    _pipHintChannel.setMethodCallHandler(null);
    _recenterTimer?.cancel();
    _offRouteDebounce?.cancel();
    _exitAutoCloseTimer?.cancel();
    _locationSub?.close();
    _progressSub?.close();
    _pulseCtrl.dispose();
    _tts?.stop();
    unawaited(NavForegroundService.stop());
    WakelockPlus.disable(); // 내비 종료 시 wakelock 해제
    super.dispose();
  }

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    // 이미 알려진 위치가 있으면 카메라 이동
    final knownLoc = ref.read(currentLocationProvider);
    if (knownLoc != null && mounted) {
      _mlCtrl?.animateCamera(ml.CameraUpdate.newLatLngZoom(_toMl(knownLoc), _navZoom));
    }

    // navStateProvider 구독 — 카메라/속도만. 진행 파생은 progressSub에서.
    _locationSub = ref.listenManual<NavigationState?>(
      navStateProvider,
      (_, next) {
        if (next == null || !mounted) return;
        final loc = next.pos;
        // 이 틱의 heading을 한 번만 확정해 bearing 회전과 offset 계산에
        // 동일하게 전달 — 서로 다른 heading 세대를 쓰는 순서 역전 방지
        // (RECON §6, _recenter가 await를 포함한 비동기라 호출부가 다음 틱을
        // 기다리지 않고 흘려보내는 구조에서 발생).
        final effectiveHeadingDeg = _resolveHeading(next.speedKmh, next.headingDeg);
        if (!_isManualMode && !_showCourseSheet) {
          _recenter(loc, speedKmh: next.speedKmh, headingDeg: effectiveHeadingDeg);
        }
        _ensureLocationMarker(effectiveHeadingDeg);
        unawaited(_maybeFetchAmbientPois());
        if (!_tourRecorderStarted) {
          _tourRecorderStarted = true;
          unawaited(_tourRecorder.start(loc, DateTime.now()));
        } else {
          _tourRecorder.onFix(loc, next.speedKmh, DateTime.now());
        }
        _checkWaypointProgress(loc, next.speedKmh);
      },
      fireImmediately: true,
    );

    // routeProgressProvider 구독 — step/카드/TTS/도착/이탈
    _progressSub = ref.listenManual<RouteProgress?>(
      routeProgressProvider,
      (_, prog) {
        if (prog == null || !mounted) return;
        setState(() {
          _cardRemainingM = prog.distToNextTurnM;
          _stepIdx = prog.activeStepIdx.clamp(0, _steps.length - 1);
        });
        // 온스크린 카드(build()의 `upcoming`, 약 1539번째 줄)와 동일하게 "다음" 턴 라벨을
        // 써야 _cardRemainingM(다음 턴까지 거리)과 짝이 맞는다 — 현재 스텝 라벨을 쓰면
        // 라벨과 거리가 서로 다른 턴을 가리키게 된다.
        final upcomingLabel = _stepIdx + 1 < _steps.length
            ? _steps[_stepIdx + 1].label
            : _steps[_stepIdx].label;
        final fgText =
            '$upcomingLabel · ${_TurnStep._formatDist(_cardRemainingM / 1000.0)}';
        if (fgText != _lastForegroundText) {
          _lastForegroundText = fgText;
          unawaited(NavForegroundService.update(fgText));
        }
        _updateRouteSplit(prog.snapIdx);
        _handleVoice(prog);
        if (prog.arrived && !_arrived && _passedWaypointCount >= widget.waypoints.length) {
          _arrived = true;
          setState(() => _arrivalBannerVisible = true);
          _fetchNearbyPois(widget.destination!).then((pois) {
            if (mounted) setState(() => _arrivalPois = pois);
          });
        }
        if (_arrivalBannerVisible) _updateExitGate(prog.distToDestM);
        if (!_saidArrival &&
            prog.distToDestM <= (_profile?.arrivalVoiceM ?? 8)) {
          _saidArrival = true;
          _vps?.speak('arrival');
        }
        if (_rerouteFallback) {
          // 목적지 150m 밖으로 벗어나거나 다시 경로 위로 복귀하면 폴백 해제
          if (!prog.offRoute || prog.distToDestM > 30) {
            _rerouteFallback = false;
            _rerouteHistory.clear();
            _saidPassedDest = false;
            debugPrint('YNAV_REROUTE fallback exit');
          }
        } else if (prog.offRoute) {
          _triggerReroute();
        } else {
          _offRouteDebounce?.cancel();
          _offRouteDebounce = null;
        }
      },
    );
  }

  /// 도착배너 표시 중 지오펜스(폴리라인 잔여거리 30m 이내)+속도(30km/h 이하)
  /// 게이트로 종료버튼 노출을 토글한다. 게이트가 열리면(false→true) 10초 뒤
  /// 자동 종료 타이머를 시작하고, 닫히면(true→false) 그 타이머를 취소한다.
  void _updateExitGate(double distToDestM) {
    final navState = ref.read(navStateProvider);
    if (navState == null) return;
    final can = exitGateOpen(
      distanceM: distToDestM,
      speedKmh: navState.speedKmh,
      geofenceM: _kExitGeofenceM,
      speedLimitKmh: _kExitSpeedKmh,
    );
    if (can != _canExit) {
      setState(() => _canExit = can);
      _exitAutoCloseTimer?.cancel();
      if (can) {
        _exitAutoCloseTimer = Timer(const Duration(seconds: 10), () {
          if (mounted && _canExit) _exitNav();
        });
      } else {
        _exitAutoCloseTimer = null;
      }
    }
  }

  void _handleVoice(RouteProgress prog) {
    if (_profile == null) return;
    // "목적지" vs "경유지" 문구는 실시간 진행 상태(_passedWaypointCount)가
    // 아니라 이 maneuver가 전체 목록의 마지막 도착 maneuver인지로 정해야
    // 한다 — Valhalla 다중 레그 경로는 각 레그(경유지별)가 끝날 때마다
    // type 4/5/6 도착 maneuver를 하나씩 내놓고 _collectManeuvers가 이를
    // 그대로 이어붙이므로, 목록의 마지막 항목이 항상 실제 최종 목적지다.
    final isFinalDestination = _maneuvers.isNotEmpty &&
        prog.activeStepIdx + 1 == _maneuvers.length - 1;
    // exitStructureByManeuverIdx는 setRoute/setStructureZones마다 갱신되는
    // 파생 데이터라 VoiceEngine 생성 시점의 스냅샷이 아니라 매 틱 최신값으로
    // 갱신해 전달한다.
    _voiceEngine!.exitStructureByManeuverIdx =
        ref.read(routeProgressProvider.notifier).exitStructureByManeuverIdx;
    final intents = _voiceEngine!.onProgress(
        prog.activeStepIdx, prog.distToNextTurnM, _maneuvers,
        shapePoints: _routePoints,
        isFinalDestination: isFinalDestination);
    for (final it in intents) {
      _vps?.speak(it.key, vars: it.vars);
      debugPrint('YNAV_TTS key=${it.key} dist=${it.vars['dist']} step=${prog.activeStepIdx}');
    }
    final structureIntents = _structureVoiceEngine!.onProgress(
        prog.structureZoneIdx, prog.distToNextStructureM, prog.nextStructureType);
    for (final it in structureIntents) {
      _vps?.speak(it.key, vars: it.vars);
      debugPrint('YNAV_TTS key=${it.key} dist=${it.vars['dist']} zone=${prog.structureZoneIdx}');
    }
    final curveIntents = _curveVoiceEngine!.onProgress(
        prog.curveZoneIdx, prog.distToNextCurveM, prog.nextCurveDirection);
    for (final it in curveIntents) {
      _vps?.speak(it.key, vars: it.vars);
      debugPrint('YNAV_TTS key=${it.key} dist=${it.vars['dist']} curve=${prog.curveZoneIdx}');
    }
  }

  /// maneuvers로부터 카드 목록을 만든다. exit(20/21) maneuver는
  /// routeProgressProvider의 exitStructureByManeuverIdx(다리/터널 인접 여부)를
  /// 반영한다 — trace_attributes 응답이 비동기로 도착하므로 초기 호출 시점엔
  /// 비어 있을 수 있고, [_loadStructureZones]에서 도착 후 다시 호출해 갱신한다.
  List<_TurnStep> _buildTurnSteps(List<ManeuverStep> maneuvers) {
    if (maneuvers.isEmpty) {
      return const [
        _TurnStep(Icons.play_arrow_rounded, '경로 안내 시작', '', 0),
        _TurnStep(Icons.straight_rounded,   '직진',         '', 0),
        _TurnStep(Icons.flag_rounded,        '목적지 도착',  '', 0),
      ];
    }
    // 마지막 maneuver만 실제 최종 목적지 — _handleVoice 상단 주석 참조.
    final lastIdx = maneuvers.length - 1;
    final structureMap =
        ref.read(routeProgressProvider.notifier).exitStructureByManeuverIdx;
    return maneuvers
        .asMap()
        .entries
        .map((e) => _TurnStep.fromManeuver(
              e.value,
              isFinalDestination: e.key == lastIdx,
              nearbyStructure: structureMap[e.key],
            ))
        .toList();
  }

  void _applyRouteGuidance(List<ManeuverStep> maneuvers) {
    final generation = ++_routeGeneration;
    _steps = _buildTurnSteps(maneuvers);
    _maneuvers = maneuvers;
    _stepIdx = 0;
    _cardRemainingM = 0.0;
    _lastAnnouncedIdx = -1;
    _voiceEngine?.reset();
    _structureVoiceEngine?.reset();
    _curveVoiceEngine?.reset();
    if (widget.destination != null) {
      // setRoute는 provider를 수정하므로 build/initState 단계에서 직접 호출 금지.
      // post-frame으로 미뤄 Riverpod build-phase 수정 에러 방지.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(routeProgressProvider.notifier).setRoute(
          points: _routePoints,
          maneuvers: maneuvers,
          destination: widget.destination!,
        );
      });
      // 다리/터널 zone 조회는 다음 프레임을 기다릴 필요 없는 순수 HTTP 호출 —
      // setRoute post-frame 콜백과 독립적으로 즉시 fire-and-forget.
      unawaited(_loadStructureZones(_routePoints, generation));
    }
  }

  /// Valhalla trace_attributes로 다리/터널 구간을 비동기 조회해 provider에
  /// 주입한다. 실패해도 예외를 던지지 않는 부가 기능(routing_service 계약) —
  /// 조회가 느리거나 실패해도 내비게이션 본편은 정상 진행된다. generation이
  /// 최신 _applyRouteGuidance 호출과 다르면(그 사이 재탐색/코스 재선택으로
  /// 경로가 또 바뀌었으면) stale 응답이니 버린다.
  Future<void> _loadStructureZones(List<LatLng> points, int generation) async {
    final zones = await RoutingService.fetchStructureZones(points);
    if (!mounted || generation != _routeGeneration) return;
    debugPrint('YNAV_STRUCT zones=${zones.length}');
    final notifier = ref.read(routeProgressProvider.notifier);
    notifier.setStructureZones(zones);
    // exit(20/21) 카드 라벨이 방금 갱신된 exitStructureByManeuverIdx를 반영할
    // 수 있도록 카드 목록을 다시 만든다 — maneuvers 자체는 그대로다.
    setState(() {
      _steps = _buildTurnSteps(_maneuvers);
    });
    // 온-루트로 못 찾은 exit만 대상으로 옆길(우회 중인) 구조물을 마저 조회한다
    // — _loadStructureZones가 채운 exitStructureByManeuverIdx가 필요하므로
    // 반드시 그 다음에 실행(HANDOFF_0716 §3 참조).
    unawaited(_loadOffRouteStructures(generation));
  }

  /// 경로 위(온-루트)에서 구조물을 못 찾은 exit(20/21) maneuver에 한해, 그
  /// 시작점부터 "주행 경로를 따라 전방으로만" 500m까지를 Valhalla /locate로
  /// 조회해 "옆길로 우회 중인" 구조물을 찾는다 — 언더패스/고가도로 옆길
  /// 분기에서 미리 차선을 바꾸지 못해 마지막 순간 급하게 차선을 가로지르는
  /// 사고 위험을 줄이기 위한 안전 기능(HANDOFF_0716_structure_bypass_exit.md
  /// §0). 내 위치 중심 원형 하나로 크게 잡으면 옆 도로나 뒤쪽의 무관한
  /// 구조물까지 오탐할 수 있다는 지적(2026-07-17)에 따라, 큰 반경 하나 대신
  /// [RoutingService.forwardSamplePoints]로 경로를 따라 전방으로만 나열한
  /// 여러 지점을 각각 작은 반경(150m)으로 조회해 병합한다
  /// (RoutingService.mergeOffRouteStructures) — 뒤쪽/역방향은 애초에 샘플
  /// 대상에 들지 않고, 인접 샘플 원이 겹쳐 경로 전방 600m까지 빈틈없이
  /// 커버된다. 실패해도 예외를 던지지 않는 부가 기능 — 조회가 느리거나
  /// 실패해도 내비게이션 본편은 정상 진행된다.
  Future<void> _loadOffRouteStructures(int generation) async {
    final notifier = ref.read(routeProgressProvider.notifier);
    final onRoute = notifier.exitStructureByManeuverIdx;
    final candidates = <int, List<LatLng>>{};
    for (int i = 0; i < _maneuvers.length; i++) {
      final m = _maneuvers[i];
      if ((m.type != 20 && m.type != 21) || onRoute.containsKey(i)) continue;
      final pts = RoutingService.forwardSamplePoints(
          _routePoints, m.beginShapeIdx);
      if (pts.isNotEmpty) candidates[i] = pts;
    }
    if (candidates.isEmpty) return;

    final results = await Future.wait(candidates.entries.map((e) async {
      final types = await Future.wait(
          e.value.map(RoutingService.fetchOffRouteStructureNear));
      return MapEntry(e.key, RoutingService.mergeOffRouteStructures(types));
    }));
    if (!mounted || generation != _routeGeneration) return;

    final map = <int, StructureType>{
      for (final r in results)
        if (r.value != null) r.key: r.value!,
    };
    if (map.isEmpty) return;
    debugPrint('YNAV_OFFROUTE_STRUCT found=${map.length} detail=$map');
    notifier.setOffRouteStructures(map);
    setState(() {
      _steps = _buildTurnSteps(_maneuvers);
    });
  }

  void _triggerReroute() {
    if (_isRerouting || _rerouteFallback) return;
    if (_lastRerouteAt != null &&
        DateTime.now().difference(_lastRerouteAt!) < _kRerouteCooldown) {
      debugPrint('YNAV_REROUTE cooldown skip');
      return;
    }
    _offRouteDebounce ??= Timer(const Duration(seconds: _kDebounceSec), () {
      _offRouteDebounce = null;
      final current = ref.read(navStateProvider)?.pos;
      if (current != null) _reroute(current);
    });
  }

  Future<void> _reroute(LatLng origin, {bool silent = false}) async {
    if (_showCourseSheet) return;
    if (_isRerouting || !mounted) return;
    if (_arrivalBannerVisible) {
      setState(() {
        _arrivalBannerVisible = false;
        _arrivalPois = const [];
        _arrived = false;
        _saidArrival = false;
        _canExit = false;
      });
    }
    final dest = widget.destination;
    if (dest == null) return;
    setState(() => _isRerouting = true);
    final navState = ref.read(navStateProvider);
    // 단순 speedKmh>2 게이트는 라이더가 재탐색 사이에 잠깐 감속/정차하면
    // heading을 null로 버려 offsetOrigin이 no-op이 되고, 그 시점에 다시
    // 이탈→재탐색이 걸리면 방향 힌트 없이 나가 제자리 유턴을 유도한다(실주행
    // 2회 이상 연속 재탐색에서 재현됨). _resolveHeading()은 이미 카메라
    // bearing 쪽에서 검증된 "저속 시 마지막 관측 heading 유지" 폴백을 갖고
    // 있으므로 재탐색에도 동일하게 적용한다.
    final heading =
        navState != null ? _resolveHeading(navState.speedKmh, navState.headingDeg) : null;
    debugPrint('YNAV_REROUTE hdg_src spd=${navState?.speedKmh} rawHdg=${navState?.headingDeg} used=$heading');
    final off = offsetOrigin(origin.latitude, origin.longitude, heading, 40);
    final routeOrigin = LatLng(off.lat, off.lng);
    debugPrint('YNAV_REROUTE off origin hdg=$heading d=40');
    try {
      final routes = await RoutingService.fetchRoutes(
        origin: routeOrigin,
        destination: dest,
        waypoints: widget.waypoints.sublist(_passedWaypointCount),
      );
      if (mounted && routes.isNotEmpty) {
        final selIdx = ref.read(mapInteractionProvider).selectedRouteIdx.clamp(0, routes.length - 1);
        final newPoints = routes[selIdx].points;
        _absorbTraveledIntoTrail(); // 경로 교체 전 지나온 구간을 궤적에 흡수
        setState(() {
          _routePoints = newPoints;
          _durationMin = routes[selIdx].durationMin;
          _applyRouteGuidance(routes[selIdx].maneuvers);
        });
        debugPrint('YNAV_GUIDE reroute steps=${_steps.length} first=${_steps.isNotEmpty ? _steps[0].label : "none"}');
        // 재탐색 맥락 구분: '안내를 시작합니다' 대신 재탐색 메시지 발화
        if (!silent) _vps?.speak('reroute');
        _lastAnnouncedIdx = 0; // 출발 step 중복 방지
        if (_styleLoaded) {
          _mlCtrl?.setGeoJsonSource(
              _navRouteSourceId, _buildRouteGeoJson(newPoints));
        }
      }
    } on RoutingException {
      // 재탐색 실패 — 기존 경로 유지
    } finally {
      if (mounted) setState(() => _isRerouting = false);
      final now = DateTime.now();
      _lastRerouteAt = now;
      _rerouteHistory.add(now);
      _rerouteHistory.removeWhere(
          (t) => now.difference(t) > _kFailureWindow);
      final stillOffRoute = ref.read(routeProgressProvider)?.offRoute ?? false;
      if (_rerouteHistory.length >= _kFailureCount && stillOffRoute) {
        _rerouteFallback = true;
        debugPrint('YNAV_REROUTE fallback enter n=${_rerouteHistory.length}');
        if (!_saidPassedDest) {
          _saidPassedDest = true;
          _vps?.speak('dest_passed');
        }
      }
    }
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts!.setLanguage('ko-KR');
    await _tts!.setSpeechRate(0.5);
    await _tts!.setVolume(1.0);
    await _tts!.setAudioAttributesForNavigation();
    // speak() Future가 네이티브 발화 완료(onDone/onStop/onError)까지 실제로
    // 기다리게 만든다. 이게 없으면 VoicePackService의 직렬화 큐가 "채널 호출
    // 성공"만 기다리게 되어 겹치는 speak 호출을 막지 못한다.
    await _tts!.awaitSpeakCompletion(true);
    _vps = await VoicePackService.load('assets/voice_packs/default_ko.json', _tts!);
    _profile = await GuidanceProfile.load('assets/config/guidance_profile.json');
    _landmarkService = await ExitLandmarkService.load('assets/data/kr_places.json');
    _voiceEngine = VoiceEngine(_profile!, landmarkService: _landmarkService);
    _structureVoiceEngine = StructureVoiceEngine(_profile!);
    _curveVoiceEngine = CurveVoiceEngine(_profile!);
    _announceStep(0);
  }

  void _announceStep(int idx) {
    if (idx < 0 || idx >= _steps.length) return;
    if (idx == _lastAnnouncedIdx) return; // 중복 방지
    _lastAnnouncedIdx = idx;
    final step = _steps[idx];
    if (step.label == '출발') {
      _vps?.speak('departure');
    }
    // 비-출발 접근 안내는 임계 경로(_handleVoice)가 담당 — 여기서 발화하지 않음
    debugPrint('YNAV_GUIDE announceStep idx=$idx label="${step.label}"');
  }

  /// Overpass API로 도착지 반경 500m 내 주유소·편의점·식당 최대 3개 조회.
  Future<List<({String name, String type})>> _fetchNearbyPois(LatLng dest) async {
    final query =
        '[out:json][timeout:5];'
        '(node["amenity"~"fuel|convenience|restaurant"]'
        '(around:500,${dest.latitude},${dest.longitude}););'
        'out 3;';
    try {
      final resp = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: query,
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List?) ?? [];
      return elements.take(3).map((e) {
        final tags = (e['tags'] as Map?) ?? {};
        return (
          name: (tags['name'] as String?) ?? '근처 장소',
          type: _poiTypeLabel(tags['amenity'] as String? ?? ''),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static String _poiTypeLabel(String amenity) {
    switch (amenity) {
      case 'fuel': return '주유소';
      case 'convenience': return '편의점';
      case 'restaurant': return '식당';
      default: return amenity;
    }
  }

  static String _etaText(int durationMin) {
    final eta = DateTime.now().add(Duration(minutes: durationMin));
    final h = eta.hour.toString().padLeft(2, '0');
    final m = eta.minute.toString().padLeft(2, '0');
    return '$h:$m 도착';
  }

  static String _remainingText(int durationMin) {
    if (durationMin <= 0) return '--';
    if (durationMin >= 60) {
      final h = durationMin ~/ 60;
      final m = durationMin % 60;
      return m > 0 ? '$h시간 $m분' : '$h시간';
    }
    return '$durationMin분';
  }

  /// [_tourRecorder]를 종료하고, 최소 기준(60초/150m)을 만족하면 시작/종료
  /// 주소를 역지오코딩한 뒤 [TourLogService]에 저장한다. `_tourFinalizeStarted`로
  /// 멱등성을 보장한다 — `_exitNav()`와 `dispose()`의 안전망 양쪽에서 호출돼도
  /// 중복 저장되지 않는다.
  Future<void> _finalizeAndPersistTour() async {
    if (_tourFinalizeStarted) return; // idempotent — dispose() also calls this as a safety net
    _tourFinalizeStarted = true;
    if (!_tourRecorderStarted) return; // never got a single GPS fix, nothing to finalize

    // ref-free on purpose: dispose()'s safety net can call this after Flutter
    // has already unmounted the element (mounted=false) but before
    // State.dispose() runs — Riverpod's ref.read() throws in that window, so
    // we source the end position from the recorder itself instead (updated
    // on every start()/onFix(), no ref/context dependency).
    final endPos = _tourRecorder.lastPos;
    if (endPos == null) return;

    final tourLog = await _tourRecorder.finish(endPos, DateTime.now());
    if (tourLog == null) return; // below minimum duration/distance threshold, already cleaned up by TourRecorder

    // 역지오코딩은 "있으면 좋은" 부가 정보일 뿐이다 — GeocodingService는 이미
    // 내부에서 실패를 잡아 null을 반환하지만, 여기서도 한 번 더 방어적으로
    // 감싼다. 이 블록에서 예외가 나도 투어 저장 자체(아래)는 반드시 시도한다 —
    // 이 함수는 unawaited()로 호출돼 예외가 나면 아무 로그도 없이 통째로
    // 유실되기 때문이다.
    var finalLog = tourLog;
    try {
      final geocoding = GeocodingService();
      final results = await Future.wait([
        geocoding.reverseGeocode(tourLog.startLat, tourLog.startLng),
        geocoding.reverseGeocode(tourLog.endLat, tourLog.endLng),
      ]);
      finalLog = tourLog.copyWith(startAddress: results[0], endAddress: results[1]);
    } catch (e) {
      debugPrint('YNAV_TOUR geocode failed, saving without address: $e');
    }

    try {
      await TourLogService().add(finalLog);
      debugPrint('YNAV_TOUR saved id=${finalLog.id} '
          'distanceM=${finalLog.distanceM.toStringAsFixed(0)} '
          'durationS=${finalLog.durationS} '
          'avgKmh=${finalLog.avgSpeedKmh.toStringAsFixed(1)} '
          'maxKmh=${finalLog.maxSpeedKmh.toStringAsFixed(1)} '
          'track=${finalLog.trackFilePath}');
    } catch (e) {
      debugPrint('YNAV_TOUR save FAILED id=${finalLog.id}: $e');
    }
  }

  /// 내비 화면의 유일한 "실제 종료" 경로 — 투어 기록 마무리+저장을 트리거한 뒤
  /// 화면을 pop한다. (다이얼로그 취소 등 비-종료성 pop은 이걸 거치지 않는다.)
  void _exitNav() {
    unawaited(_finalizeAndPersistTour());
    Navigator.of(context).pop();
  }

  void _confirmExit(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('내비게이션 종료'),
        content: const Text('내비게이션을 종료할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dlgCtx).pop();
              _exitNav();
            },
            child: const Text('종료'),
          ),
        ],
      ),
    );
  }

  /// 속도→줌 선형 보간: 0 km/h→18, 20→16, 60+→14
  double _zoomForSpeed(double kmh) {
    if (kmh <= 20) return 18.0 - (kmh / 20.0) * 2.0;
    if (kmh <= 60) return 16.0 - ((kmh - 20.0) / 40.0) * 2.0;
    return 14.0;
  }

  /// 3km/h 미만(정차/저속)에서는 GPS heading 잡음을 무시하고 마지막으로
  /// 이동 중 관측된 heading을 그대로 유지한다 — 정지 시 offset이 매 틱
  /// 잡음을 따라 흔들리는 것을 막는다 (RECON §4/§5). 호출부(GPS 틱 핸들러)가
  /// 틱당 한 번만 호출해 그 결과를 bearing 회전과 offset 계산 양쪽에
  /// 동일하게 전달해야 두 값이 어긋나지 않는다 (RECON §6).
  double? _resolveHeading(double speedKmh, double? headingDeg) {
    if (speedKmh >= 3 && headingDeg != null) _lastHeadingDeg = headingDeg;
    return (speedKmh >= 3 ? headingDeg : null) ?? _lastHeadingDeg;
  }

  // headingDeg는 호출부가 _resolveHeading()으로 이미 확정한 값이어야 한다.
  Future<void> _recenter(LatLng loc, {bool animate = false, double speedKmh = 0, double? headingDeg}) async {
    if (!_styleLoaded) return;
    // 3km/h 미만은 정차/저속으로 보고 줌을 갱신하지 않는다 — 정지 시 GPS
    // 속도 잡음(mpp가 0.238↔1.18처럼 튐)으로 줌이 진동하는 것을 방지.
    if (speedKmh >= 3) {
      final target = _zoomForSpeed(speedKmh);
      // GPS 이벤트당 최대 0.5레벨씩 부드럽게 수렴
      final diff = target - _navZoom;
      _navZoom += diff.clamp(-0.3, 0.3); // 수렴 속도 낮춤 (0~20km/h 구간 과도한 줌 방지)
      _navZoom = _navZoom.clamp(6.0, 17.0); // 앱 줌 상한(17)과 일치시켜 카메라-표시 어긋남 방지
      _lastMovingZoom = _navZoom;
    } else if (_lastMovingZoom != null) {
      _navZoom = _lastMovingZoom!;
    }

    var camTarget = loc;
    if (headingDeg != null) {
      final metersPerPixel = await _mlCtrl?.getMetersPerPixelAtLatitude(loc.latitude);
      if (metersPerPixel != null && mounted) {
        final screenHeightPx = MediaQuery.of(context).size.height;
        final dpr = MediaQuery.of(context).devicePixelRatio;
        const frac = 0.25;
        // getMetersPerPixelAtLatitude is meters per LOGICAL pixel (matches
        // size.height's unit), so no dpr conversion is needed here. Multiplying
        // by dpr (physH = logicalH * dpr) overshot mAhead by a factor of dpr,
        // pushing the puck target past the bottom of the screen.
        final logicalH = screenHeightPx;
        final metersAhead = metersPerPixel * logicalH * frac;
        final off = offsetOrigin(loc.latitude, loc.longitude, headingDeg, metersAhead);
        camTarget = LatLng(off.lat, off.lng);
        debugPrint('YNAV_CAM dpr=$dpr mpp=$metersPerPixel logicalH=$logicalH mAhead=$metersAhead '
            'puck=(${loc.latitude.toStringAsFixed(5)},${loc.longitude.toStringAsFixed(5)}) '
            'tgt=(${off.lat.toStringAsFixed(5)},${off.lng.toStringAsFixed(5)}) '
            'brg=${headingDeg.toStringAsFixed(1)} hdg=${headingDeg.toStringAsFixed(1)}');
      }
    }

    final brg = headingDeg ?? _lastHeadingDeg ?? 0.0;
    final update = ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(target: _toMl(camTarget), zoom: _navZoom, bearing: brg));
    if (animate) {
      _mlCtrl?.animateCamera(update);
    } else {
      _mlCtrl?.moveCamera(update);
    }
  }

  ml.LatLng _toMl(LatLng p) => ml.LatLng(p.latitude, p.longitude);

  Map<String, dynamic> _buildRouteGeoJson(List<LatLng> points) => {
        'type': 'FeatureCollection',
        'features': points.isEmpty
            ? <dynamic>[]
            : [
                {
                  'type': 'Feature',
                  'geometry': {
                    'type': 'LineString',
                    // GeoJSON은 [longitude, latitude] 순서
                    'coordinates':
                        points.map((p) => [p.longitude, p.latitude]).toList(),
                  },
                  'properties': <String, dynamic>{},
                }
              ],
      };

  Map<String, dynamic> _buildBgGeoJson(List<List<LatLng>> routes) => {
        'type': 'FeatureCollection',
        'features': routes.isEmpty
            ? <dynamic>[]
            : routes
                .map((pts) => {
                      'type': 'Feature',
                      'geometry': {
                        'type': 'LineString',
                        'coordinates':
                            pts.map((p) => [p.longitude, p.latitude]).toList(),
                      },
                      'properties': <String, dynamic>{},
                    })
                .toList(),
      };

  /// 코스 재선택 시트가 열려있는 동안, allRoutes 중 선택 안 된 코스들을
  /// 회색 배경 레이어로 갱신한다. 시트가 닫히면 빈 리스트로 초기화해 평소
  /// 내비 화면(지나온 경로 회색 레이어와는 별개)에는 보이지 않게 한다.
  void _updateRouteBgLayer(List<List<LatLng>> allRoutes, int selIdx) {
    if (!_styleLoaded) return;
    final bgRoutes = [
      for (int i = 0; i < allRoutes.length; i++)
        if (i != selIdx) allRoutes[i],
    ];
    _mlCtrl?.setGeoJsonSource(_navRouteBgSourceId, _buildBgGeoJson(bgRoutes));
  }

  Map<String, dynamic> _buildLocGeoJson(LatLng p, [double? bearing]) => {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              // GeoJSON은 [longitude, latitude] 순서
              'coordinates': [p.longitude, p.latitude],
            },
            'properties': <String, dynamic>{
              // ['get','bearing']이 null을 만나 회전 못하는 것을 막기 위해
              // heading 미확정 시 0으로 기본값 처리.
              'bearing': bearing ?? 0,
            },
          }
        ],
      };

  Future<void> _initRouteLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null) return;
    // 지나온 구간(회색) — 색상 레이어보다 먼저 추가하되 순서 자체는 중요하지
    // 않음(좌표가 겹치지 않음), 둘 다 라벨 아래에 배치되기만 하면 됨.
    await ctrl.addGeoJsonSource(
        _navRouteTraveledSourceId, _buildRouteGeoJson([]));
    await ctrl.addLineLayer(
      _navRouteTraveledSourceId,
      _navRouteTraveledLayerId,
      const ml.LineLayerProperties(
        lineColor: '#9E9E9E',
        lineWidth: 6.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: 'waterway-name',
    );
    // 코스 재선택 시트용 비교 배경 레이어 — 평소엔 빈 소스라 아무것도 안
    // 그려지고, _openCourseSheet()가 열려있는 동안만 _updateRouteBgLayer로
    // 채워진다.
    await ctrl.addGeoJsonSource(_navRouteBgSourceId, _buildBgGeoJson([]));
    await ctrl.addLineLayer(
      _navRouteBgSourceId,
      _navRouteBgLayerId,
      const ml.LineLayerProperties(
        lineColor: '#9E9E9E',
        lineWidth: 4.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: 'waterway-name',
    );
    await ctrl.addGeoJsonSource(_navRouteSourceId, _buildRouteGeoJson([]));
    final idx = ref.read(mapInteractionProvider).selectedRouteIdx;
    await ctrl.addLineLayer(
      _navRouteSourceId,
      _navRouteLayerId,
      ml.LineLayerProperties(
        lineColor: colorToHex(courseLineColor[idx] ?? courseLineColor[2]!),
        lineWidth: 6.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: 'waterway-name',
    );
  }

  /// route 레이어가 이미 추가된 뒤(호출 순서 보장) 위치점 레이어를 1회 추가.
  /// 나중에 추가된 레이어가 위(전면)에 그려지므로 route 위에 puck이 온다
  /// (RECON_camera_redesign.md §1-2, RECON_ZORDER.md). belowLayerId 없이
  /// call order만으로 z-order를 확정하기 위해 _locLayerReady로 1회만 실행 보장.
  Future<void> _initLocationLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null || _locLayerReady) return;
    final p = ref.read(navStateProvider)?.pos ?? _kInitialMapView;
    await ctrl.addGeoJsonSource(_navLocSourceId, _buildLocGeoJson(p));
    // addSymbol/SymbolManager로는 icon-rotation-alignment:map을 설정할 수
    // 없어(스타일 기본값 auto로 고정) 헤딩 회전이 카메라 bearing과 어긋난다.
    // raw GeoJSON 기반 addSymbolLayer만 iconRotationAlignment을 노출한다.
    await ctrl.addSymbolLayer(
      _navLocSourceId,
      _navLocLayerId,
      ml.SymbolLayerProperties(
        iconImage: _kArrowIcon,
        iconRotate: [ml.Expressions.get, 'bearing'],
        iconRotationAlignment: 'map',
        iconAnchor: 'center',
        iconSize: _kArrowIconSize,
        iconAllowOverlap: true,
      ),
    );
    _locLayerReady = true;
  }

  Future<void> _ensureLocationMarker([double? heading]) async {
    final c = _mlCtrl;
    // _locLayerReady 이전엔 no-op — _initLocationLayer가 route 레이어
    // 추가 이후에만 puck 레이어를 만들도록 해 z-order 레이스를 막는다.
    if (c == null || !_styleLoaded || !_locLayerReady) return;
    final p = ref.read(navStateProvider)?.pos;
    if (p == null) return;
    await c.setGeoJsonSource(_navLocSourceId, _buildLocGeoJson(p, heading));
  }

  // ── POI 상시 표시(ambient) 레이어 (13-1b) ──────────────────────────────────
  // main_map_screen의 검색 시트 POI(_fetchNearbyPois/_arrivalPois는 도착배너용
  // 완전히 다른 기능)와 무관 — 줌 레벨 임계값(Poi.minZoomLevel)에 따라 자동
  // 표시된다.

  Map<String, dynamic> _buildPoiGeoJson(List<Poi> pois) => {
        'type': 'FeatureCollection',
        'features': pois
            .map((p) => {
                  'type': 'Feature',
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [p.location.longitude, p.location.latitude],
                  },
                  'properties': <String, dynamic>{
                    'poiType': p.type.name,
                    'poiIcon': 'poi-icon-${p.type.name}',
                    'name': p.name,
                  },
                })
            .toList(),
      };

  Future<void> _initPoiLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null) return;
    await ctrl.addGeoJsonSource(_navPoiSourceId, _buildPoiGeoJson(const []));
    await ctrl.addSymbolLayer(
      _navPoiSourceId,
      _navPoiLayerId,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'poiIcon'],
        iconSize: 0.4, // 96px 원본 기준 실사용 크기 — 실기기 확인 후 추가 조정
        iconAllowOverlap: true,
        iconAnchor: 'center',
        textField: ['get', 'name'],
        textFont: ['Noto Sans Regular'],
        textSize: 11,
        textOffset: [0, 1.6],
        textAnchor: 'top',
        textColor: '#212121',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.2,
        textAllowOverlap: false,
        textOptional: true, // 라벨 공간이 없어도 아이콘은 계속 표시
      ),
    );
  }

  void _updatePoiLayer(List<Poi> pois) {
    if (!_styleLoaded) return;
    _mlCtrl?.setGeoJsonSource(_navPoiSourceId, _buildPoiGeoJson(pois));
  }

  /// GPS 위치 기준(내비 중엔 카메라가 항상 라이더를 따라가므로 화면 중심과
  /// 동일)으로 현재 줌(_navZoom)에서 노출 대상인 카테고리를 계산하고, 필요
  /// 시(카테고리 변경 시 즉시 / 그 외엔 200m 이동 또는 15초 경과 디바운스)
  /// POI를 재조회해 ambient 레이어를 갱신한다. 화면에 실제 보이는 것만,
  /// 가까운 순 최대 10개로 제한한다.
  /// _navZoom(속도 보간값)이 카테고리 임계값 근처에서 흔들려도 매번
  /// "카테고리 변경"으로 잡히지 않도록 진입/이탈에 0.3 히스테리시스를 둔다.
  Set<PoiType> _resolveEligibleTypes(double zoom) {
    final result = <PoiType>{};
    for (final t in PoiType.values) {
      final threshold = t.minZoomLevel.toDouble();
      if (_stickyEligibleTypes.contains(t)) {
        if (zoom >= threshold - 0.3) result.add(t);
      } else {
        if (zoom >= threshold + 0.3) result.add(t);
      }
    }
    return result;
  }

  /// 현재 위치로 다음 미통과 경유지에 대한 [waypointPassageEvent] 판정을
  /// 굴려 도착/통과 이벤트를 처리한다. 두 이벤트 모두 _passedWaypointCount를
  /// 증가시켜 이후 재탐색에서 배제한다.
  void _checkWaypointProgress(LatLng pos, double speedKmh) {
    if (_passedWaypointCount >= widget.waypoints.length) return;
    final target = widget.waypoints[_passedWaypointCount];
    final distM = PoiService.haversineMeters(pos, target);
    final result = waypointPassageEvent(
      distM: distM,
      speedKmh: speedKmh,
      closestDistM: _waypointClosestDistM,
      arrivalM: _kWaypointArrivalM,
      stopSpeedKmh: _kWaypointStopSpeedKmh,
      passedMarginM: _kWaypointPassedMarginM,
    );
    _waypointClosestDistM = result.closestDistM;
    switch (result.event) {
      case WaypointPassageEvent.arrived:
        _passedWaypointCount++;
        _vps?.speak('waypoint_arrived');
      case WaypointPassageEvent.passed:
        _passedWaypointCount++;
        _vps?.speak('waypoint_passed');
      case WaypointPassageEvent.none:
        break;
    }
  }

  Future<void> _maybeFetchAmbientPois() async {
    final ctrl = _mlCtrl;
    final gpsPos = ref.read(navStateProvider)?.pos;
    if (ctrl == null || !_styleLoaded || gpsPos == null) return;

    final targetTypes = _resolveEligibleTypes(_navZoom);
    _stickyEligibleTypes = targetTypes; // 매 틱 갱신 — fetch 성사 여부와 무관
    if (targetTypes.isEmpty) {
      _ambientFetchGen++; // 진행 중이던 fetch가 있으면 응답을 무효화
      if (_ambientPois.isNotEmpty) {
        _ambientPois = const [];
        _updatePoiLayer(const []);
      }
      _lastAmbientFetchTypes = const {};
      return;
    }

    // 디바운스 판단용 저비용 중심점(플랫폼 채널 호출 없음): 수동 팬 모드(rider가
    // 지도를 직접 팬해 자동추종을 벗어난 상태)에선 카메라 target을, 자동추종
    // 모드에선 GPS 위치를 쓴다. 실제 getVisibleRegion()은 재조회가 확정된
    // 뒤(_isManualMode 분기)에만 부른다.
    final LatLng approxCenter;
    if (_isManualMode) {
      final camTarget = ctrl.cameraPosition?.target;
      if (camTarget == null) return;
      approxCenter = LatLng(camTarget.latitude, camTarget.longitude);
    } else {
      approxCenter = gpsPos;
    }

    final sameTypes = targetTypes.length == _lastAmbientFetchTypes.length &&
        targetTypes.every(_lastAmbientFetchTypes.contains);
    if (sameTypes) {
      final lastAt = _lastAmbientFetchAt;
      final lastCenter = _lastAmbientFetchCenter;
      final movedEnough = lastCenter == null ||
          PoiService.haversineMeters(lastCenter, approxCenter) >= 200;
      final staleEnough = lastAt == null ||
          DateTime.now().difference(lastAt) >= const Duration(seconds: 15);
      if (!movedEnough && !staleEnough) return;
    }

    // 이 호출 시작 시점의 세대를 기록 — 아래 await(getVisibleRegion/fetchPois)
    // 도중 더 최신 호출이 시작되면(_ambientFetchGen이 바뀌면) 이 응답은
    // stale이니 버린다.
    final myGen = ++_ambientFetchGen;

    final LatLng center;
    final double south, north, west, east;
    if (_isManualMode) {
      // 수동 팬 모드 — main_map_screen._maybeFetchAmbientPois와 동일하게 실제
      // 뷰포트 bounds를 중심/필터링 기준으로 쓴다.
      final ml.LatLngBounds bounds;
      try {
        bounds = await ctrl.getVisibleRegion();
      } catch (_) {
        return;
      }
      if (!mounted || myGen != _ambientFetchGen) return;
      center = LatLng(
        (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
        (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
      );
      south = bounds.southwest.latitude;
      north = bounds.northeast.latitude;
      west = bounds.southwest.longitude;
      east = bounds.northeast.longitude;
    } else {
      // 자동추종 모드 — 카메라가 항상 헤딩에 맞춰 회전해 축 정렬된 실제
      // 뷰포트 bounds 개념이 no map-pan case와 맞지 않으므로, GPS 위치를
      // 중심으로 한 정사각형 근사 bounds를 쓴다(main_map_screen._mapPinPois와
      // 동일 패턴).
      center = gpsPos;
      const delta = 0.02; // ~2.2km, 그리드 분산용 근사치일 뿐 실제 필터링엔 영향 없음.
      south = center.latitude - delta;
      north = center.latitude + delta;
      west = center.longitude - delta;
      east = center.longitude + delta;
    }

    final cached = _poiRegionCache.tryGet(
      south: south,
      west: west,
      north: north,
      east: east,
      types: targetTypes,
    );

    final List<Poi> pois;
    if (cached != null) {
      pois = cached;
    } else {
      final fetched = await ref.read(poiServiceProvider).fetchPoisInBounds(
            south: south,
            west: west,
            north: north,
            east: east,
            types: targetTypes.toList(),
          );
      if (!mounted || myGen != _ambientFetchGen) return;
      _poiRegionCache.put(
        south: south,
        west: west,
        north: north,
        east: east,
        types: targetTypes,
        pois: fetched,
      );
      pois = fetched;
    }

    final limited = PoiService.selectForAmbientDisplay(
      candidates: pois,
      south: south,
      north: north,
      west: west,
      east: east,
      center: center,
      maxCount: 20,
    );

    _ambientPois = limited;
    _updatePoiLayer(limited);
    _lastAmbientFetchAt = DateTime.now();
    _lastAmbientFetchCenter = center;
    _lastAmbientFetchTypes = targetTypes;
  }

  /// 목적지/경유지는 widget 생명주기 동안 불변(ctor의 final 필드, 재할당 없음)
  /// 이므로 puck과 달리 틱마다 갱신할 필요 없이 스타일 로드 후 1회만 설정한다.
  /// route 레이어 위, puck 레이어 아래에 오도록 puck보다 먼저 생성한다.
  Future<void> _initDestLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null || _destLayerReady) return;
    _destLayerReady = true;
    for (final wp in widget.waypoints) {
      await ctrl.addSymbol(ml.SymbolOptions(
        geometry: _toMl(wp),
        iconImage: _kWpIcon,
        iconSize: _kWpIconSize,
        iconAnchor: 'bottom',
        zIndex: 5,
      ));
    }
    final dest = widget.destination;
    if (dest != null) {
      await ctrl.addSymbol(ml.SymbolOptions(
        geometry: _toMl(dest),
        iconImage: _kDestIcon,
        iconSize: _kDestIconSize,
        iconAnchor: 'bottom',
        zIndex: 10,
      ));
    }
  }

  void _onStyleLoaded() {
    setState(() => _styleLoaded = true);
    // 레이어 설치 후 진입 시 이미 있는 경로 즉시 반영
    _initRouteLayer().whenComplete(() async {
      if (_routePoints.length >= 2 && mounted) {
        _mlCtrl?.setGeoJsonSource(
            _navRouteSourceId, _buildRouteGeoJson(_routePoints));
      }
      // dest/waypoint 핀 이미지 1회 등록 (addSymbol 호출보다 먼저)
      final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
      await _mlCtrl?.addImage(_kDestIcon, pinBytes.buffer.asUint8List());
      final wpBytes = await rootBundle.load('assets/images/pointer_yellow.png');
      await _mlCtrl?.addImage(_kWpIcon, wpBytes.buffer.asUint8List());
      final arrowBytes = await rootBundle.load('assets/images/arrow_puck.png');
      await _mlCtrl?.addImage(_kArrowIcon, arrowBytes.buffer.asUint8List());
      // POI 카테고리 아이콘 — 스타일 재주입마다 다시 등록해야 한다(addImage도
      // 네이티브 스타일에 종속되어 재생성 시 사라짐). SymbolLayer가 참조하기
      // 전, _initPoiLayer보다 먼저 등록한다.
      for (final type in PoiType.values) {
        final bytes = await renderPoiIconPng(
          poiIcons[type]!,
          poiIconBgColors[type]!,
        );
        await _mlCtrl?.addImage('poi-icon-${type.name}', bytes);
      }
      _initDestLayer().whenComplete(() {
        _initLocationLayer().whenComplete(() => _ensureLocationMarker()); // unawaited — ③
        _initPoiLayer(); // unawaited — 13-1b 상시 표시 POI 레이어
      });
    });
  }

  void _onMapGesture() {
    setState(() => _isManualMode = true);
    _recenterTimer?.cancel();
    _recenterTimer = Timer(const Duration(seconds: 10), () {
      if (_showCourseSheet) return;
      setState(() => _isManualMode = false);
      final ns = ref.read(navStateProvider);
      final pos = ns?.pos;
      if (pos != null) {
        final speedKmh = ns?.speedKmh ?? 0;
        _recenter(pos,
            animate: true,
            speedKmh: speedKmh,
            headingDeg: _resolveHeading(speedKmh, ns?.headingDeg));
      }
    });
  }

  /// "재탐색" 버튼: 경로 전체가 보이는 오버뷰로 전환하고, 3개 코스를 프리뷰용
  /// 으로 페치해 코스 재선택 시트를 띄운다. 시트가 이미 열려 있으면 no-op —
  /// 종료/확정은 시트 자신의 onClose/onStart 콜백이 담당한다.
  Future<void> _openCourseSheet() async {
    if (_showCourseSheet) return;
    if (_routePoints.length < 2) return;
    final reqId = ++_courseSheetReqId;
    // 오버뷰 유지 중엔 _isManualMode의 10초 자동복귀가 개입하지 않도록
    // 별도 타이머는 걸지 않되, 기존에 예약된 팬 제스처 타이머는 취소한다.
    _recenterTimer?.cancel();
    setState(() {
      _showCourseSheet = true;
      _fetchedRoutes = [];
    });
    final minLat = _routePoints.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = _routePoints.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLng = _routePoints.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = _routePoints.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    await _mlCtrl?.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: ml.LatLng(minLat, minLng),
          northeast: ml.LatLng(maxLat, maxLng),
        ),
        left: 50,
        top: 110,
        right: 80,
        bottom: 360,
      ),
    );
    await _mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(0));

    final currentMapState = ref.read(mapInteractionProvider);
    _originalSelectedIdx = currentMapState.selectedRouteIdx;
    _originalAllRoutes = currentMapState.allRoutes;
    _originalAllRouteMeta = currentMapState.allRouteMeta;
    final navState = ref.read(navStateProvider);
    final origin = navState?.pos;
    final dest = widget.destination;
    if (origin == null || dest == null) return;
    // _reroute()와 동일한 heading 오프셋 — 안 하면 재탐색 버튼도 반대편(뒤쪽)
    // 엣지에 스냅되어 제자리 유턴을 유도할 수 있다 (RECON_heading_reroute.md §3).
    // _resolveHeading()으로 저속/정차 시에도 마지막 관측 heading을 유지한다
    // (단순 speedKmh>2 게이트의 2회+ 연속 재탐색 버그, 위 _reroute()와 동일).
    final heading =
        navState != null ? _resolveHeading(navState.speedKmh, navState.headingDeg) : null;
    final off = offsetOrigin(origin.latitude, origin.longitude, heading, 40);
    final routeOrigin = LatLng(off.lat, off.lng);
    try {
      final routes = await RoutingService.fetchRoutes(
        origin: routeOrigin,
        destination: dest,
        waypoints: widget.waypoints.sublist(_passedWaypointCount),
      );
      if (!mounted || reqId != _courseSheetReqId) return;
      final scores = await Future.wait(
        routes.map((r) => NativeEngine.scoreFunV2(r.points)),
      );
      if (!mounted || reqId != _courseSheetReqId) return;
      final notifier = ref.read(mapInteractionProvider.notifier);
      final allPoints = routes.map((r) => r.points).toList();
      notifier.setAllRoutes(allPoints);
      _updateRouteBgLayer(
          allPoints, ref.read(mapInteractionProvider).selectedRouteIdx);
      notifier.setAllRouteMeta(List.generate(routes.length, (i) => (
        km: routes[i].distanceKm,
        mins: routes[i].durationMin,
        windingScore: scores[i].funScoreV2,
      )));
      setState(() => _fetchedRoutes = routes);
    } on RoutingException {
      // 프리뷰 페치 실패 — _fetchedRoutes 비워둔 채로 두고 기존
      // allRouteMeta(있다면)로 시트를 표시한다. nav_screen엔 home 같은
      // 스낵바 에러 패턴이 없어 새로 만들지 않는다 (범위 밖).
    }
  }

  /// 코스 카드 탭 — 프리뷰만 갱신 (_routePoints/_durationMin은 건드리지 않음).
  void _onCourseCardTap(int idx) {
    ref.read(mapInteractionProvider.notifier).setSelectedRouteIdx(idx);
    if (idx < _fetchedRoutes.length) {
      if (_styleLoaded) {
        _mlCtrl?.setGeoJsonSource(
            _navRouteSourceId, _buildRouteGeoJson(_fetchedRoutes[idx].points));
      }
      _recolorNavRouteLayer(idx);
      _updateRouteBgLayer(
          _fetchedRoutes.map((r) => r.points).toList(), idx);
    }
  }

  /// 슬라이더 확정 — 현재 선택된 프리뷰를 실제 활성 경로로 커밋한다.
  void _onCourseSheetStart() {
    if (_fetchedRoutes.isNotEmpty) {
      final idx = ref
          .read(mapInteractionProvider)
          .selectedRouteIdx
          .clamp(0, _fetchedRoutes.length - 1);
      final route = _fetchedRoutes[idx];
      _absorbTraveledIntoTrail(); // 경로 교체 전 지나온 구간을 궤적에 흡수
      setState(() {
        _routePoints = route.points;
        _durationMin = route.durationMin;
        _applyRouteGuidance(route.maneuvers);
      });
      _lastAnnouncedIdx = 0;
      if (_styleLoaded) {
        _mlCtrl?.setGeoJsonSource(
            _navRouteSourceId, _buildRouteGeoJson(route.points));
      }
      _recolorNavRouteLayer(idx); // 마지막 프리뷰 탭과 이미 일치할 수 있으나 방어적으로 재설정
      _vps?.speak('reroute');
    }
    _updateRouteBgLayer(const [], 0); // 코스 확정 — 비교용 회색 레이어 정리
    setState(() => _showCourseSheet = false);
    final ns = ref.read(navStateProvider);
    final pos = ns?.pos;
    if (pos != null) {
      final speedKmh = ns?.speedKmh ?? 0;
      _recenter(pos,
          animate: true,
          speedKmh: speedKmh,
          headingDeg: _resolveHeading(speedKmh, ns?.headingDeg));
    }
  }

  /// 시트 닫기(확정 없이) — 프리뷰를 원래 선택으로 되돌린다. _routePoints는
  /// 프리뷰 중 변형된 적이 없으므로 지도 소스/색상과 provider 인덱스만 복원.
  void _onCourseSheetClose() {
    final restoreIdx = _originalSelectedIdx!;
    final notifier = ref.read(mapInteractionProvider.notifier);
    if (_originalAllRoutes != null) notifier.setAllRoutes(_originalAllRoutes!);
    if (_originalAllRouteMeta != null) {
      notifier.setAllRouteMeta(_originalAllRouteMeta!);
    }
    notifier.setSelectedRouteIdx(restoreIdx);
    if (_styleLoaded) {
      _mlCtrl?.setGeoJsonSource(
          _navRouteSourceId, _buildRouteGeoJson(_routePoints));
    }
    _recolorNavRouteLayer(restoreIdx);
    _updateRouteBgLayer(const [], 0); // 시트 취소 — 비교용 회색 레이어 정리
    setState(() => _showCourseSheet = false);
    final ns = ref.read(navStateProvider);
    final pos = ns?.pos;
    if (pos != null) {
      final speedKmh = ns?.speedKmh ?? 0;
      _recenter(pos,
          animate: true,
          speedKmh: speedKmh,
          headingDeg: _resolveHeading(speedKmh, ns?.headingDeg));
    }
  }

  Future<void> _recolorNavRouteLayer(int idx) async {
    final ctrl = _mlCtrl;
    if (ctrl == null || !_styleLoaded) return;
    await ctrl.removeLayer(_navRouteLayerId);
    await ctrl.addLineLayer(
      _navRouteSourceId,
      _navRouteLayerId,
      ml.LineLayerProperties(
        lineColor: colorToHex(courseLineColor[idx] ?? courseLineColor[2]!),
        lineWidth: 6.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: 'waterway-name',
    );
  }

  /// 재탐색/코스 재선택으로 _routePoints가 통째로 교체되기 직전에 호출해,
  /// 그때까지 지나온 구간을 _traveledTrail에 흡수한다. 그 날의 투어링
  /// 궤적은 경로가 바뀌어도 끊기지 않고 목적지 도착까지 이어져야 한다.
  void _absorbTraveledIntoTrail() {
    if (_routePoints.length < 2) return;
    final snapIdx = ref.read(routeProgressProvider)?.snapIdx ?? 0;
    final idx = snapIdx.clamp(0, _routePoints.length - 1);
    _traveledTrail = [..._traveledTrail, ..._routePoints.sublist(0, idx + 1)];
  }

  /// GPS 진행률(snapIdx)에 맞춰 경로를 지나온 구간(회색)과 남은 구간(코스
  /// 색상)으로 나눠 각자의 레이어에 반영한다. 지나온 구간은 재탐색 이전
  /// 경로들에서 흡수된 _traveledTrail을 앞에 이어붙여, 경로가 바뀌어도
  /// 그 날의 투어링 궤적 전체가 끊기지 않도록 한다. 코스 프리뷰 시트가
  /// 열려있는 동안은 시트가 보여주는 프리뷰 경로를 덮어쓰지 않도록
  /// 건너뛴다(_isManualMode/_showCourseSheet일 때 카메라 추적을 건너뛰는
  /// 기존 패턴과 동일한 이유).
  void _updateRouteSplit(int snapIdx) {
    final ctrl = _mlCtrl;
    if (ctrl == null || !_styleLoaded || _showCourseSheet) return;
    if (_routePoints.length < 2) return;
    final idx = snapIdx.clamp(0, _routePoints.length - 1);
    final pos = ref.read(navStateProvider)?.pos;
    final traveledPts = [
      ..._traveledTrail,
      ..._routePoints.sublist(0, idx + 1),
      ?pos,
    ];
    final remainingPts = [
      ?pos,
      ..._routePoints.sublist(idx + 1),
    ];
    ctrl.setGeoJsonSource(_navRouteTraveledSourceId,
        _buildRouteGeoJson(traveledPts.length >= 2 ? traveledPts : const []));
    ctrl.setGeoJsonSource(_navRouteSourceId,
        _buildRouteGeoJson(remainingPts.length >= 2 ? remainingPts : const []));
  }

  /// PiP 미니창 전용 컴팩트 뷰 — 지도(MapLibre)나 나머지 UI 없이 다음 턴
  /// 아이콘 + 라벨 + 남은 거리만 표시한다. 온스크린 카드(build()의 `upcoming`)와
  /// 동일한 기존 데이터(_steps[_stepIdx + 1]/_cardRemainingM)만 재사용하고
  /// 새 아이콘/에셋은 추가하지 않는다.
  Widget _buildPipCompactView() {
    final upcoming =
        _stepIdx + 1 < _steps.length ? _steps[_stepIdx + 1] : _steps[_stepIdx];
    final distText = _TurnStep._formatDist(_cardRemainingM / 1000.0);
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(upcoming.icon, color: Colors.white, size: 40),
                const SizedBox(height: 6),
                Text(
                  upcoming.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  distText,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Phase B: PiP 미니창에서는 지도/전체 UI를 그리지 않고 다음 턴 아이콘+거리만
    // 보여주는 컴팩트 뷰로 대체한다 (onUserLeaveHint → nav_pip_hint 채널 →
    // _maybeEnterPip → onPipEntered 콜백이 _isInPip을 true로 세팅).
    if (_isInPip) return _buildPipCompactView();
    final navState = ref.watch(navStateProvider);
    final step = _steps[_stepIdx];
    // 카드에 표시할 "다가오는 회전" — 마지막 step이면 step 자신(목적지)으로 폴백
    final upcoming = _stepIdx + 1 < _steps.length ? _steps[_stepIdx + 1] : step;
    final daylightCycle = ref.watch(daylightCycleProvider);
    final daylightProgress = daylightCycle?.progress ?? 0.5;
    final isDay = daylightCycle?.isDay ?? true;
    final cs = Theme.of(context).colorScheme;
    final routeKm = _polylineKm(widget.routePolyline);

    ref.listen<AsyncValue<MapLanguage>>(mapLanguageProvider, (_, next) {
      final raw = _rawStyle;
      if (raw == null) return;
      final lang = next.value ?? MapLanguage.korean;
      if (mounted) setState(() => _styleJson = applyMapLanguageToStyle(raw, lang));
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _confirmExit(context);
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
        children: [
          // ── 지도: MapLibre (커밋 ①) ─────────────────────────────────────────
          // Listener: 사용자 터치 시작 감지 → _onMapGesture (수동모드 진입)
          // HitTestBehavior.translucent: MapLibre 네이티브 패닝/줌 제스처 보존
          if (_styleJson == null)
            const Center(child: CircularProgressIndicator()),
          if (_styleJson != null)
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _onMapGesture(),
            child: ml.MapLibreMap(
              styleString: _styleJson!,
              minMaxZoomPreference: const ml.MinMaxZoomPreference(6.0, 17.0),
              initialCameraPosition: ml.CameraPosition(
                target: _toMl(ref.read(navStateProvider)?.pos ?? _kInitialMapView),
                zoom: 15,
              ),
              rotateGesturesEnabled: false, // North-up 고정 (바이크 거치)
              tiltGesturesEnabled: false,   // 2D 유지
              compassEnabled: false,
              onMapCreated: (c) => _mlCtrl = c,
              onStyleLoadedCallback: _onStyleLoaded,
            ),
          ),

          // ── OSM attribution (ODbL 라이선스 필수 표기) ──────────────────────────
          // 네이티브 attribution 버튼과 별개로 항상 보이는 안전장치.
          Positioned(
            left: 4,
            bottom: 4,
            child: IgnorePointer(
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),

          // ── 수동모드 복귀 알림 ──────────────────────────────────────────────
          if (_isManualMode)
            Positioned(
              top: MediaQuery.of(context).padding.top + 88,
              left: 60,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.gps_fixed, color: cs.tertiary, size: 14),
                    const SizedBox(width: 6),
                    Text('10초 후 현위치 복귀',
                        style: TextStyle(color: cs.onSurface, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // ── 도착 배너 (비침습, dim 없음) ──────────────────────────────────────
          if (_arrivalBannerVisible)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.flag_rounded, color: cs.tertiary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('목적지 도착',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        GestureDetector(
                          onTap: () {
                            _exitAutoCloseTimer?.cancel();
                            setState(() {
                              _arrivalBannerVisible = false;
                              _canExit = false;
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded, size: 20),
                          ),
                        ),
                      ],
                    ),
                    if (_arrivalPois.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ..._arrivalPois.map((p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              Icon(Icons.place, size: 14, color: cs.tertiary),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text('${p.type}: ${p.name}',
                                      style: const TextStyle(fontSize: 12))),
                            ]),
                          )),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!_canExit)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Text('정차 후 종료 가능',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Text('10초 후 자동 종료',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          ),
                        // 목적지 근처에서 정차만 하면(예: 신호 대기, 헬멧 벗는 중) 곧바로
                        // _canExit이 열리고 10초 뒤 자동 종료되므로, 라이더가 실제로는
                        // 계속 안내를 원해도 명시적으로 취소할 버튼이 없었다(2026-07-15
                        // 밤 라이딩 리포트 — "계속 안내" 버튼 부재 + 대기 없이 바로 종료).
                        GestureDetector(
                          onTap: () {
                            _exitAutoCloseTimer?.cancel();
                            setState(() {
                              _arrivalBannerVisible = false;
                              _canExit = false;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text('계속 안내',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                )),
                          ),
                        ),
                        GestureDetector(
                          onTap: _canExit
                              ? () {
                                  _exitAutoCloseTimer?.cancel();
                                  _exitNav();
                                }
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _canExit ? cs.tertiary : cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text('안내 종료',
                                style: TextStyle(
                                  color: _canExit ? Colors.white : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                )),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ── 상단 회전 안내 ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: GestureDetector(
                onTap: () {
                  if (_stepIdx < _steps.length - 1) {
                    setState(() => _stepIdx++);
                    _announceStep(_stepIdx);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: (_stepIdx + 1) / _steps.length,
                          backgroundColor: cs.outline,
                          color: cs.tertiary,
                          minHeight: 3,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: cs.tertiary,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(upcoming.icon, color: Colors.white, size: 30),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_cardRemainingM > 0 || step.dist.isNotEmpty)
                                      Builder(builder: (ctx) {
                                        final raw = _cardRemainingM > 0
                                            ? _TurnStep._formatDist(_cardRemainingM / 1000.0)
                                            : step.dist;
                                        final parts = _TurnStep._splitDistStr(raw);
                                        return RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: parts.$1,
                                                style: TextStyle(
                                                  color: cs.tertiary,
                                                  fontSize: 38,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.1,
                                                ),
                                              ),
                                              TextSpan(
                                                text: parts.$2,
                                                style: TextStyle(
                                                  color: cs.tertiary,
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w700,
                                                  height: 1.1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    Text(
                                      upcoming.label,
                                      style: TextStyle(
                                        color: cs.onSurface,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── 좌측 속도계 (상단 30% 높이, 네이버지도 배치 참고) ─────────────────
          Positioned(
            left: 12,
            top: MediaQuery.of(context).size.height * 0.30,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: _Speedometer(speedKmh: navState?.speedKmh ?? 0, firstFixReceived: navState?.firstFix ?? false),
            ),
          ),

          // ── 우측: Daylight + 컨트롤 (ETA 바 위에 위치) ──────────────────────
          Positioned(
            right: 12,
            top: 200,
            bottom: 160,
            child: Column(
              children: [
                Expanded(
                  child: DaylightBar(
                    progress: daylightProgress,
                    sunriseLabel: daylightCycle != null
                        ? DateFormat('HH:mm').format(daylightCycle.topTime)
                        : '--:--',
                    sunsetLabel: daylightCycle != null
                        ? DateFormat('HH:mm').format(daylightCycle.bottomTime)
                        : '--:--',
                    isNightMode: !isDay,
                  ),
                ),
                const SizedBox(height: 10),
                _NavIconBtn(
                  icon: _isManualMode ? Icons.gps_fixed : Icons.my_location,
                  onTap: () {
                    final ns = ref.read(navStateProvider);
                    final pos = ns?.pos;
                    if (pos == null) return;
                    _recenterTimer?.cancel();
                    setState(() => _isManualMode = false);
                    final speedKmh = ns?.speedKmh ?? 0;
                    _recenter(pos,
                        animate: true,
                        speedKmh: speedKmh,
                        headingDeg: _resolveHeading(speedKmh, ns?.headingDeg));
                  },
                ),
              ],
            ),
          ),

          // ── 하단 ETA 바 ─────────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _etaText(_durationMin),
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                Text(_remainingText(_durationMin), style: TextStyle(color: cs.tertiary, fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                Text(routeKm > 0 ? '${routeKm.toStringAsFixed(1)}km' : '--', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: cs.outline, margin: const EdgeInsets.symmetric(horizontal: 16)),
                      Builder(builder: (_) {
                        final canReroute = navState?.pos != null && !_isRerouting;
                        final fg = canReroute
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.3);
                        return GestureDetector(
                          onTap: canReroute ? _openCourseSheet : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.alt_route, color: fg, size: 20),
                                const SizedBox(height: 2),
                                Text('재탐색',
                                    style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _exitNav(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close_rounded, color: Colors.white, size: 20),
                              SizedBox(height: 2),
                              Text('종료', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── 코스 재선택 시트 (재탐색 버튼) ─────────────────────────────────────
          if (_showCourseSheet)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: CourseSheet(
                  routeMeta: ref.watch(mapInteractionProvider).allRouteMeta,
                  selectedIdx: ref.watch(mapInteractionProvider).selectedRouteIdx,
                  onSelect: _onCourseCardTap,
                  onStart: _onCourseSheetStart,
                  onClose: _onCourseSheetClose,
                ),
              ),
            ),

          // ── 야간 디밍 오버레이 (EENT 후 ~ 익일 BMNT) ──────────────────────────
          // 색 재지정 없이 반투명 검정으로 화면 밝기를 낮춤.
          if (!isDay)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Speedometer extends StatefulWidget {
  final double speedKmh;
  final bool firstFixReceived;
  const _Speedometer({required this.speedKmh, required this.firstFixReceived});

  @override
  State<_Speedometer> createState() => _SpeedometerState();
}

class _SpeedometerState extends State<_Speedometer> with SingleTickerProviderStateMixin {
  late final AnimationController _blinkCtrl;
  late final Animation<double> _blinkAnim;

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _blinkAnim = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _blinkCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_Speedometer old) {
    super.didUpdateWidget(old);
    if (widget.firstFixReceived && _blinkCtrl.isAnimating) _blinkCtrl.stop();
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surface,
        border: Border.all(color: cs.tertiary, width: 2.5),
        boxShadow: [BoxShadow(color: cs.tertiary.withValues(alpha: 0.25), blurRadius: 16)],
      ),
      child: widget.firstFixReceived
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.speedKmh.toStringAsFixed(0),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.tertiary, height: 1.0),
                ),
                Text('km/h', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            )
          : FadeTransition(
              opacity: _blinkAnim,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('GPS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.tertiary, height: 1.1)),
                  Text('검색 중', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
    );
  }
}

class _NavIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavIconBtn({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(color: cs.outline, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8)],
        ),
        child: Icon(icon, color: cs.tertiary, size: 20),
      ),
    );
  }
}

class _TurnStep {
  final IconData icon;
  final String label;
  final String dist;
  final double rawDistKm; // GPS 거리 자동 진행용 원시 거리(km)
  final int type;
  const _TurnStep(this.icon, this.label, this.dist, [this.rawDistKm = 0.0, this.type = 0]);

  factory _TurnStep.fromManeuver(ManeuverStep m,
      {bool isFinalDestination = true, StructureType? nearbyStructure}) {
    return _TurnStep(
      _iconForType(m.type),
      _labelForType(
          m.type, m.roundaboutExitCount, isFinalDestination, nearbyStructure),
      _formatDist(m.distanceKm),
      m.distanceKm,
      m.type,
    );
  }

  static IconData _iconForType(int type) {
    switch (type) {
      case 1: case 2: case 3: return Icons.play_arrow_rounded;
      case 4: case 5: case 6: return Icons.flag_rounded;
      case 8: case 17: case 22: return Icons.straight_rounded;
      case 9: case 18: case 23: return Icons.turn_slight_right;
      case 10: case 20: case 26: case 27: return Icons.turn_right_rounded;
      case 11: return Icons.turn_right_rounded;
      case 12: case 13: return Icons.u_turn_right_rounded;
      case 14: return Icons.turn_left_rounded;
      case 15: case 21: return Icons.turn_left_rounded;
      case 16: case 19: case 24: return Icons.turn_slight_left;
      case 25: return Icons.straight_rounded;
      default: return Icons.straight_rounded;
    }
  }

  static String _labelForType(int type,
      [int? roundaboutExitCount,
      bool isFinalDestination = true,
      StructureType? nearbyStructure]) {
    switch (type) {
      case 1: case 2: case 3: return '출발';
      case 4: case 5: case 6: return isFinalDestination ? '목적지 도착' : '경유지 도착';
      case 7: return '도로명 변경';
      case 8: case 22: return '직진';
      case 9: return '완만한 우회전';
      case 10: return '우회전';
      case 11: return '급한 우회전';
      case 12: case 13: return '유턴';
      case 14: return '급한 좌회전';
      case 15: return '좌회전';
      case 16: return '완만한 좌회전';
      case 17: return '직진';
      case 18: return '우측으로 진입';
      case 19: return '좌측으로 진입';
      case 20:
        return nearbyStructure != null
            ? '${nearbyStructure.labelKo} 우측 옆길'
            : '우측으로 진출';
      case 21:
        return nearbyStructure != null
            ? '${nearbyStructure.labelKo} 좌측 옆길'
            : '좌측으로 진출';
      case 23: return '우측 차선';
      case 24: return '좌측 차선';
      case 25: return '합류구간';
      case 26: return roundaboutExitCount != null ? '회전교차로 $roundaboutExitCount번째 출구' : '회전교차로 진입';
      case 27: return '회전교차로 진출';
      case 28: return '도선 탑승';
      case 29: return '도선 하차';
      default: return '직진';
    }
  }

  static String _formatDist(double km) {
    if (km <= 0) return '';
    if (km < 1.0) return '${(km * 1000).round()}m';
    return '${km.toStringAsFixed(1)}km';
  }

  static (String, String) _splitDistStr(String s) {
    if (s.endsWith('km')) return (s.substring(0, s.length - 2), 'km');
    if (s.endsWith('m')) return (s.substring(0, s.length - 1), 'm');
    return (s, '');
  }
}
