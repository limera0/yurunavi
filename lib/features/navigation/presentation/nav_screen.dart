import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math show sin, cos, sqrt, asin, pi;

import 'package:http/http.dart' as http;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/skin/skin_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/safe_clamp.dart';
import '../../../core/widgets/course_sheet.dart';
import '../../../core/widgets/daylight_bar.dart';
import '../../../services/active_tour_destination_store.dart';
import '../../../services/exit_landmark_service.dart';
import '../../../services/gas_station_service.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/nav_floating_overlay.dart';
import '../../../services/nav_foreground_service.dart';
import '../../../services/poi_icon_renderer.dart';
import '../../../services/poi_service.dart';
import '../../../services/tour_log_service.dart';
import '../../../services/voice_pack_service.dart';
import '../../../models/map_language.dart';
import '../../../models/poi.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/routing_service.dart';
import '../../map/providers/map_providers.dart';
import '../../map/style_language_transform.dart';
import '../../settings/providers/settings_providers.dart';
import '../../tour_summary/tour_log_format.dart';
import '../providers/nav_state_provider.dart';
import '../providers/route_progress_provider.dart';
import '../guidance_profile.dart';
import '../models/rear_camera.dart';
import '../tour_recorder.dart';
import '../guidance_arbiter.dart';
import '../voice_engine.dart';
import '../../route/offset_origin.dart';
import 'nav_top_card.dart';
import 'rear_camera_gauge.dart';

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
  // S15: "이어서 안내하기"로 재개된 투어일 때, 중단 전 원래 구간의
  // TourLog.id. 일반 신규 투어는 null.
  final String? resumedFromId;

  const NavScreen({
    super.key,
    this.destination,
    this.waypoints = const [],
    this.routePolyline = const [],
    this.maneuvers = const [],
    this.durationMin = 0,
    this.resumedFromId,
  });

  @override
  ConsumerState<NavScreen> createState() => _NavScreenState();
}

class _NavScreenState extends ConsumerState<NavScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  ml.MapLibreMapController? _mlCtrl;
  bool _styleLoaded = false;
  // dispose() 진입 즉시 true로 세팅 — 비동기 콜백이 스트림 close 이후에
  // 도달해도 지도 API 호출을 막는 게이트(_canCallMap)에서 사용한다.
  bool _isDisposing = false;

  String? _rawStyle;
  String? _styleJson;
  // O1 청크3: 지도 한글 폰트 — MapView 생성 시점에만 적용되고 런타임 변경이
  // 안 되므로(maplibre_gl 포크 제약), 스타일 로드 시 한 번만 읽어 고정한다.
  // Android 전용, iOS는 항상 null(플러그인이 해당 키를 읽지 않음).
  String? _ideographFontFamily;

  bool _locLayerReady = false;
  bool _destLayerReady = false;
  bool _navRouteArrowLayerReady = false;
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
  static const _navRouteArrowLayerId = 'nav-route-arrow-layer';
  static const _kRouteArrowIcon = 'route-arrow';
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

  // 주유소 경유지 추가
  GasStation? _selectedGasStation;
  late List<LatLng> _liveWaypoints; // widget.waypoints 런타임 복사본 — 주유소 추가 시 갱신

  // 하단 카드 목적지명 ↔ 현위치(시/군/구) 3초 교대 표시 (§4).
  // 3s Timer.periodic으로 토글, 다른 Timer 필드들(_recenterTimer 등)과 동일한
  // "field 선언 + dispose에서 취소" 패턴을 따른다.
  Timer? _cardLabelToggleTimer;
  bool _showCurrentLocInCard = false;
  String? _currentLocLabel; // reverseGeocodeCoarse 결과, 실패/미조회 시 null(널 가드로 목적지명 유지)
  // 시/군/구는 자주 안 바뀌므로 1Hz GPS 틱마다 부르지 않고 300m/60초 중
  // 먼저 오는 조건에서만 재조회 — PoiFetchThrottle 재사용(S2 429 폭주 방지
  // 패턴, feedback_prefer_simple_reuse 메모리 참고). 기기 내장 geocoder라
  // 네트워크 요청은 아니지만 불필요한 기기 API 호출 폭주는 마찬가지로 피한다.
  final _coarseGeoThrottle = PoiFetchThrottle(
    minInterval: const Duration(seconds: 60),
    minMoveMeters: 300,
  );

  // 도착 감지
  bool _arrived = false;
  bool _saidArrival = false; // 'arrival' 음성 전용 래치 (배너/POI와 별도 트리거)
  bool _arrivalBannerVisible = false;
  // 라운드7: 독립 도착 배너를 폐기하며 이 리스트를 렌더링할 자리가 새 목업엔
  // 없어졌다(PROGRESS.md 미확정 항목 — 완전 제거 vs 다른 화면 이전은 별도
  // 결정 필요). 조회(_fetchNearbyPois) 자체는 부작용 없어 그대로 두고 값만
  // 계속 채우므로, 표시하지 않는 한 analyzer가 "읽히지 않는 필드"로 잡는다.
  // ignore: unused_field
  List<({String name, String type})> _arrivalPois = const [];
  // 실제 주행 경과시간(라운드7 카드1 "목적지 도착" 표시용) — 내비 시작
  // 시각(_tourRecorderStarted와 같은 시점)을 기록해두고, 도착 판정 순간
  // 한 번만 스냅샷(_arrivalDurationS)을 찍는다(실시간 갱신 스톱워치 아님).
  DateTime? _navStartedAt;
  int? _arrivalDurationS;
  // 도착배너 종료버튼 지오펜스+속도 게이트 (feat/arrival-fix SPEC_arrival_v2 포팅 —
  // 정차(속도<1.0) 게이트는 실 GPS에서 안 걸려 폐기됐던 전례가 있어 채택하지 않음).
  static const _kExitGeofenceM = 30.0;  // 종료버튼 노출 지오펜스 반경(폴리라인 잔여거리 기준, m)
  static const _kExitSpeedKmh = 30.0;   // 종료버튼 노출 속도 상한(km/h)
  bool _canExit = false;
  // _canExit이 true가 된 뒤 10초 경과 시 자동 종료 — 게이트가 다시 닫히거나
  // 배너를 직접 닫으면 반드시 취소해야 한다(주행 중 화면이 갑자기 꺼지면 안 됨).
  Timer? _exitAutoCloseTimer;
  Timer? _compassNorthTimer;

  // 하단 ETA 카드 ↔ "탐색 유지"/"내비게이션 종료" 확인 카드 전환 (라운드7).
  // 트리거는 두 가지: (a) 도착(_arrivalBannerVisible=true와 동시에 켜짐,
  // _canExit 게이트 적용) (b) 시스템 뒤로가기/온스크린 종료(X) 탭(게이트 없음,
  // 즉시 활성).
  bool _showExitConfirm = false;
  // (b) 뒤로가기 트리거 전용 "두 번째 뒤로가기" 무장 플래그 — _showExitConfirm과
  // 분리한 이유(code-auditor 지적, 2026-07-31): 도착 트리거는 _showExitConfirm을
  // GPS 도착 판정 즉시(라이더 조작 없이) true로 세팅하므로, 이 값 하나만으로
  // "뒤로가기를 이미 한 번 눌렀는지"를 판단하면 도착 직후 첫 뒤로가기가
  // _canExit 지오펜스+속도 게이트를 건너뛰고 곧바로 종료돼버린다(안전장치 우회
  // 버그). 도착 중(_arrivalBannerVisible)엔 이 플래그를 아예 쓰지 않고 항상
  // _canExit 게이트로만 판단하며, 뒤로가기 트리거(도착과 무관)에서만 "1차
  // 눌러서 카드 전환 → 2차 눌러서 즉시 종료"의 무장 상태로 사용한다.
  bool _backExitArmed = false;

  // 하단 ETA 카드 실측 높이(라운드7 우측버튼 줌아웃 가림 버그 근본수정) —
  // 매직넘버(bottom:125) 대신 카드 자신의 렌더 높이를 실측해 우측 버튼
  // 컬럼의 bottom 오프셋을 역산한다. SafeArea가 내부에서 이미 기기별
  // MediaQuery.padding.bottom을 흡수해 패딩으로 반영하므로, 이 높이엔
  // 하단 인셋이 이미 포함돼 있다.
  final GlobalKey _etaCardKey = GlobalKey();
  double _etaCardHeight = 110; // 첫 프레임 측정 전 사용할 대략치(측정 즉시 갱신됨)

  // 음성 안내
  FlutterTts? _tts;
  VoicePackService? _vps;
  int _lastAnnouncedIdx = -1;  // 중복 발화 방지 (_announceStep용)
  GuidanceProfile? _profile;
  VoiceEngine? _voiceEngine;
  StructureVoiceEngine? _structureVoiceEngine;
  CurveVoiceEngine? _curveVoiceEngine;
  RearCameraVoiceEngine? _rearCameraVoiceEngine;
  final _guidanceArbiter = GuidanceArbiter();
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
  // ambient POI 재조회 디바운스(15초/200m 시간·거리 하한, 타입 변경 시 3초
  // 하한 — §2-3) + 반드시 shouldFetch가 true인 그 자리에서(await 전에)
  // markStarted를 호출해야 한다. 응답 후에만 커밋하면 응답이 느릴 때
  // 디바운스가 영원히 무장되지 않는다(2026-08-05 S2에서 발견한 429 폭주 원인).
  final _ambientThrottle = PoiFetchThrottle(
    minInterval: const Duration(seconds: 15),
    minMoveMeters: 200,
    typeChangeMinInterval: const Duration(seconds: 3),
  );
  // 진행 중인 ambient fetch가 있으면 새 호출은 즉시 return.
  bool _ambientFetchInFlight = false;
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
  List<({double km, int mins})>? _originalAllRouteMeta;
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
  bool _isOfflineRouting = false;               // serverDown 재탐색 실패 중
  bool _saidPassedDest = false;                 // '목적지를 지나쳤습니다' 중복 발화 방지

  late List<_TurnStep> _steps; // Valhalla maneuvers 또는 더미 폴백
  List<ManeuverStep> _maneuvers = const [];
  int _stepIdx = 0;
  double _cardRemainingM = 0.0; // 카드에 표시할 실시간 잔여 거리(m); GPS틱마다 갱신
  double _remainingRouteM = 0.0; // 하단 카드용 남은 경로 전체 거리(m); progressSub가 갱신, 초기엔 routeKm*1000 폴백
  // 구조물(다리/터널) zone 비동기 페치 stale-response 가드 — _applyRouteGuidance
  // 호출마다 증가시켜, 이전 세대의 fetchStructureZones 응답이 늦게 도착해도
  // 최신 경로에 잘못 반영되지 않게 한다.
  int _routeGeneration = 0;

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
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
      total += 2 * r * math.asin(math.sqrt(a));
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: kSystemBarColor,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: kSystemBarColor,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ));
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _routePoints = List<LatLng>.of(widget.routePolyline);
    // 첫 GPS fix 전(progressSub 미도착) 표시용 폴백 — 이후 progressSub가
    // prog.distToDestM으로 실시간 갱신한다.
    _remainingRouteM = _polylineKm(widget.routePolyline) * 1000;
    _durationMin = widget.durationMin;
    _liveWaypoints = List<LatLng>.of(widget.waypoints);
    // 하단 카드 목적지명 ↔ 현위치 3초 교대 표시 토글 (§4).
    _cardLabelToggleTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _showCurrentLocInCard = !_showCurrentLocInCard);
    });
    // 주행 중 화면 꺼짐 방지
    WakelockPlus.enable();
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
    // 결정 2(2026-08-06) 반영: 플로팅 오버레이 진입점 초기화.
    // 권한 다이얼로그는 2026-08-14 결정으로 여기서 더 이상 호출하지 않는다 —
    // main_map_screen(홈 화면) initState에서 앱 생애주기 1회만 표시한다.
    NavFloatingOverlay.attach(ref, context);
  }

  Future<void> _loadRawStyle() async {
    final raw = await rootBundle.loadString('assets/images/osm_liberty_yurunavi.json');
    if (!mounted) return;
    final lang = ref.read(mapLanguageProvider).value ?? MapLanguage.korean;
    // Android 전용 — 값은 한 번만 읽는다(런타임 override 불가, 위 필드 주석 참고).
    final ideographFont = Platform.isAndroid
        ? (ref.read(mapIdeographFontFamilyProvider).value ??
            MapIdeographFontFamilyNotifier.defaultFamily)
        : null;
    setState(() {
      _rawStyle = raw;
      _styleJson = applyMapLanguageToStyle(raw, lang);
      _ideographFontFamily = ideographFont;
    });
  }

  @override
  void dispose() {
    // 결정 2(2026-08-06) 반영: 내비 종료 시 플로팅 오버레이 강제 해제(좀비 방지).
    // _isDisposing 세팅보다 먼저 호출해 오버레이 hide가 비동기 차단 없이 발송됨.
    NavFloatingOverlay.detach();
    // 비동기 콜백이 스트림 close 이후에 도달해도 지도 API 호출을 막도록
    // 가장 먼저 세팅한다. _canCallMap()이 이 플래그를 확인한다.
    _isDisposing = true;
    if (!_tourFinalizeStarted) {
      unawaited(_finalizeAndPersistTour());
    }
    // 내비 화면 진입 시 설정한 상태바+내비바를 앱 전역 색으로 명시 복원한다
    // (statusBarIconBrightness만 부분 복원하면 systemNavigationBarColor가
    // F8F4F0/F5F1EC에 눌어붙은 채 남는 버그였다 — loop/layout_fixes/PROGRESS.md 라운드2).
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: kSystemBarColor,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: kSystemBarColor,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ));
    WidgetsBinding.instance.removeObserver(this);
    _recenterTimer?.cancel();
    _offRouteDebounce?.cancel();
    _exitAutoCloseTimer?.cancel();
    _compassNorthTimer?.cancel();
    _cardLabelToggleTimer?.cancel();
    _locationSub?.close();
    _progressSub?.close();
    _pulseCtrl.dispose();
    _tts?.stop();
    unawaited(NavForegroundService.stop());
    WakelockPlus.disable(); // 내비 종료 시 wakelock 해제
    super.dispose();
  }

  /// 결정 2(2026-08-06) 반영: 시스템 PIP 폐기 후 SYSTEM_ALERT_WINDOW 플로팅 아이콘
  /// 방식으로 대체. paused/hidden에서 오버레이 표시, resumed에서 숨김.
  ///
  /// ⚠️ inactive에는 절대 반응하지 않는다 — S3 청크1에서 근원 차단한
  /// "알림창 내림·스크린샷으로 오검출" 문제가 여기서 재도입되면 안 됨.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.destination == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 설정 토글(주행 설정 > "다른 앱 위에 PIP 화면 표시")이 꺼져 있으면
        // 오버레이를 아예 띄우지 않는다 — 끈 상태에서는 show/hide 둘 다 no-op.
        if (ref.read(floatingOverlayEnabledProvider).value ?? true) {
          unawaited(NavFloatingOverlay.show(_currentGuidance()));
        }
      case AppLifecycleState.resumed:
        unawaited(NavFloatingOverlay.hide());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break; // 반응 없음 — S3 오검출 회귀 방지
    }
  }

  /// 현재 안내 스텝의 아이콘 타입과 잔여 거리, 그리고 다음 스텝(있으면)의
  /// 아이콘 타입과 거리를 반환한다. FloatingOverlayService에 전달할
  /// [GuidanceInfo]를 생성한다(네이티브 2줄 오버레이용, 2026-08-14).
  /// _steps / _stepIdx / _cardRemainingM는 progressSub가 매 tick 갱신한다.
  GuidanceInfo _currentGuidance() {
    // build()의 메인 카드(2028행 upcoming = _steps[_stepIdx+1])와 같은 컨벤션을
    // 따른다 — _cardRemainingM(=routeProgressProvider의 distToNextTurnM)이 실제로
    // 카운트다운하는 대상은 _steps[_stepIdx]가 아니라 _steps[_stepIdx+1]이다.
    // (code-auditor 2026-08-14 지적: _steps[_stepIdx]를 쓰면 1행 아이콘과 거리가
    // 서로 다른 회전을 가리키게 됨.) 마지막 스텝이면 _stepIdx 자신으로 폴백.
    final current = _stepIdx + 1 < _steps.length
        ? _steps[_stepIdx + 1]
        : (_steps.isNotEmpty ? _steps[_stepIdx.clamp(0, _steps.length - 1)] : null);
    // svgAsset 경로에서 파일명만 추출해 iconType으로 변환
    // (예: 'assets/images/nav_icons/nav_right.svg' → 'nav_right')
    final iconType = current != null
        ? current.svgAsset.split('/').last.replaceAll('.svg', '')
        : 'nav_straight';
    final distText = _cardRemainingM > 0
        ? _TurnStep._formatDist(_cardRemainingM / 1000)
        : '';
    // 다음 스텝 — 위 1행보다 한 스텝 더 앞(온스크린 카드2와 동일하게 _stepIdx+2).
    // 없으면 null로 둬 네이티브가 1줄 레이아웃으로 접히게 한다.
    final upcoming = _stepIdx + 2 < _steps.length ? _steps[_stepIdx + 2] : null;
    final nextIconType =
        upcoming?.svgAsset.split('/').last.replaceAll('.svg', '');
    final nextDistanceText = upcoming?.dist;
    return (
      iconType: iconType,
      distanceText: distText,
      nextIconType: nextIconType,
      nextDistanceText: nextDistanceText,
    );
  }

  /// 지도 API 호출 허용 여부 게이트.
  /// - mounted: 위젯 트리에서 분리되지 않았는지
  /// - _mlCtrl != null: controller가 연결됐는지 (nullptr 가드는 이미 있지만
  ///   controller reference가 살아있고 native view만 죽은 경우를 추가 방어)
  /// - !_isDisposing: dispose() 진입 후 비동기 콜백이 늦게 도달하는 경우 차단
  ///
  /// 로그 근거: MissingPluginException(source#setGeoJson) 431건,
  /// camera#move 136건 — _mlCtrl? 널가드는 controller reference가 살아있고
  /// native view만 죽은 경우를 잡지 못한다.
  bool _canCallMap() => mounted && _mlCtrl != null && !_isDisposing;

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    // 이미 알려진 위치가 있으면 카메라 이동
    final knownLoc = ref.read(currentLocationProvider);
    if (knownLoc != null && _canCallMap()) {
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
        // S5: 정차 모드(5km/h 미만 10초 지속) 동안엔 카메라 추종/앰비언트
        // POI 페치를 멈춘다 — GPS 지터로 인한 미세 흔들림·불필요 네트워크
        // 호출 방지. 파란 점(_ensureLocationMarker)은 정차 중에도 최신 위치/
        // 방향을 반영해야 하므로 게이트하지 않는다.
        final isStationary = ref.read(isStationaryProvider);
        if (!isStationary && !_isManualMode && !_showCourseSheet) {
          final isNorthUp = !(ref.read(navHeadingUpProvider).value ?? true);
          _recenter(loc,
              speedKmh: next.speedKmh,
              headingDeg: isNorthUp ? null : effectiveHeadingDeg,
              forceBearingNorth: isNorthUp);
        }
        _ensureLocationMarker(effectiveHeadingDeg);
        if (!isStationary) unawaited(_maybeFetchAmbientPois());
        unawaited(_maybeFetchCoarseLocation(loc));
        if (!_tourRecorderStarted) {
          _tourRecorderStarted = true;
          _navStartedAt = DateTime.now();
          unawaited(_tourRecorder.start(loc, _navStartedAt!));
          final dest = widget.destination;
          if (dest != null) {
            unawaited(ActiveTourDestinationStore().record(
              id: _navStartedAt!.millisecondsSinceEpoch.toString(),
              destLat: dest.latitude,
              destLng: dest.longitude,
              destName: ref.read(mapInteractionProvider).destinationName,
              waypoints: widget.waypoints,
            ));
          }
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
          _remainingRouteM = prog.distToDestM;
          _stepIdx = _steps.isEmpty
              ? 0
              : prog.activeStepIdx.clamp(0, _steps.length - 1);
        });
        _updateRouteSplit(prog.snapIdx);
        _handleVoice(prog);
        if (prog.arrived && !_arrived && _passedWaypointCount >= widget.waypoints.length) {
          _arrived = true;
          setState(() {
            _arrivalBannerVisible = true;
            // 도착 트리거 — 하단 카드도 함께 "탐색 유지"/"내비게이션 종료"
            // 확인 상태로 전환(라운드7 4-a).
            _showExitConfirm = true;
            // 도착 중엔 뒤로가기 판정을 전적으로 _canExit 게이트에 맡긴다 —
            // 혹시 도착 전에 무장돼 있던 값이 남아 있어도(뒤로가기 트리거가
            // 먼저 있었던 드문 순서) 게이트를 우회하지 않도록 방어적으로 리셋.
            _backExitArmed = false;
            _arrivalDurationS = _navStartedAt != null
                ? DateTime.now().difference(_navStartedAt!).inSeconds
                : null;
          });
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
    // roadClassByManeuverIdx도 동일 이유(파생 데이터, 매 틱 최신값 필요)로
    // onProgress 호출 직전에 갱신한다(S10).
    _voiceEngine!.roadClassByManeuverIdx =
        ref.read(routeProgressProvider.notifier).roadClassByManeuverIdx;
    final voiceIntents = _voiceEngine!.onProgress(
        prog.activeStepIdx, prog.distToNextTurnM, _maneuvers,
        shapePoints: _routePoints,
        isFinalDestination: isFinalDestination);
    final structureIntents = _structureVoiceEngine!.onProgress(
        prog.structureZoneIdx, prog.distToNextStructureM, prog.nextStructureType);
    final curveIntents = _curveVoiceEngine!.onProgress(
        prog.curveZoneIdx, prog.distToNextCurveM, prog.nextCurveDirection);
    final rearCameraIntents = _rearCameraVoiceEngine!
        .onProgress(prog.distToNextCameraM, prog.inPostZone);
    final spoken = _guidanceArbiter.arbitrate(
        rearCamera: rearCameraIntents,
        voice: voiceIntents,
        structure: structureIntents,
        curve: curveIntents);
    for (final it in spoken) {
      _vps?.speak(it.key, vars: it.vars);
      debugPrint('YNAV_TTS key=${it.key} dist=${it.vars['dist'] ?? ''} step=${prog.activeStepIdx}');
    }
  }

  /// maneuvers로부터 카드 목록을 만든다. exit(20/21) maneuver는
  /// routeProgressProvider의 exitStructureByManeuverIdx(다리/터널 인접 여부)를
  /// 반영한다 — trace_attributes 응답이 비동기로 도착하므로 초기 호출 시점엔
  /// 비어 있을 수 있고, [_loadStructureZones]에서 도착 후 다시 호출해 갱신한다.
  List<_TurnStep> _buildTurnSteps(List<ManeuverStep> maneuvers) {
    if (maneuvers.isEmpty) {
      return const [
        _TurnStep('assets/images/nav_icons/nav_straight.svg', '경로 안내 시작', '', 0),
        _TurnStep('assets/images/nav_icons/nav_straight.svg', '직진',           '', 0),
        _TurnStep('assets/images/nav_icons/nav_straight.svg', '목적지 도착',    '', 0),
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
    _guidanceArbiter.reset();
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
    final result = await RoutingService.fetchStructureZones(points, _maneuvers);
    if (!mounted || generation != _routeGeneration) return;
    debugPrint('YNAV_STRUCT zones=${result.zones.length}');
    final notifier = ref.read(routeProgressProvider.notifier);
    notifier.setStructureZones(result.zones);
    // S10: 등급 유지/상승 갈림길 음성 억제 판정용 진입/진출 road_class —
    // 같은 trace_attributes 응답에서 함께 받아온다(HANDOFF_0807_S10 §1).
    notifier.setRoadClasses(result.roadClasses);
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
    // S5: 정차 중엔 GPS 지터로 인한 이탈 오검출이 반복 재탐색을 유발한다
    // (분당 최대 151건 실측, RECON 근거) — 디바운스 타이머 자체를 등록하지
    // 않고 조용히 리턴한다. 이탈 로직(offRoute 판정) 자체는 건드리지 않으므로
    // 정차 모드가 풀리는(속도 회복) 순간 다음 offRoute 판정에서 이 게이트를
    // 통과해 정상적으로 다시 재탐색이 걸린다.
    if (ref.read(isStationaryProvider)) return;
    // S7: 터널 dead reckoning 중엔 추정 위치가 실측이 아니므로, 이 동안의
    // offRoute 판정을 근거로 재탐색하면 안 된다 — 실측 fix가 돌아올 때까지
    // 대기(HANDOFF_0807_S7 §5).
    if (ref.read(routeProgressProvider)?.deadReckoning == true) return;
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
      _exitAutoCloseTimer?.cancel();
      setState(() {
        _arrivalBannerVisible = false;
        _arrivalPois = const [];
        _arrived = false;
        _saidArrival = false;
        _canExit = false;
        _showExitConfirm = false;
        _backExitArmed = false;
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
    final off = offsetOrigin(origin.latitude, origin.longitude, heading, 50);
    final routeOrigin = LatLng(off.lat, off.lng);
    debugPrint('YNAV_REROUTE off origin hdg=$heading d=50');
    try {
      final routes = await RoutingService.fetchRoutes(
        origin: routeOrigin,
        destination: dest,
        waypoints: _liveWaypoints.sublist(_passedWaypointCount),
      );
      if (mounted && routes.isNotEmpty) {
        final selIdx = ref.read(mapInteractionProvider).selectedRouteIdx.clamp(0, routes.length - 1);
        final newPoints = routes[selIdx].points;
        _absorbTraveledIntoTrail(); // 경로 교체 전 지나온 구간을 궤적에 흡수
        setState(() {
          _routePoints = newPoints;
          _durationMin = routes[selIdx].durationMin;
          _isOfflineRouting = false;
          _applyRouteGuidance(routes[selIdx].maneuvers);
        });
        debugPrint('YNAV_GUIDE reroute steps=${_steps.length} first=${_steps.isNotEmpty ? _steps[0].label : "none"}');
        // 재탐색 맥락 구분: '안내를 시작합니다' 대신 재탐색 메시지 발화
        if (!silent) _vps?.speak('reroute');
        _lastAnnouncedIdx = 0; // 출발 step 중복 방지
        if (_styleLoaded && _canCallMap()) {
          _mlCtrl?.setGeoJsonSource(
              _navRouteSourceId, _buildRouteGeoJson(newPoints));
        }
      }
    } on RoutingException catch (e) {
      if (e.type == RoutingError.serverDown) {
        if (mounted) setState(() => _isOfflineRouting = true);
      }
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

  // ── 주유소 경유지 추가 ──────────────────────────────────────────────────────

  static double _haversineM(LatLng a, LatLng b) {
    const r = 6371000.0;
    const deg2rad = 0.017453292519943295;
    final lat1 = a.latitude * deg2rad;
    final lat2 = b.latitude * deg2rad;
    final dlat = (b.latitude - a.latitude) * deg2rad;
    final dlng = (b.longitude - a.longitude) * deg2rad;
    final sinDlat = math.sin(dlat / 2);
    final sinDlng = math.sin(dlng / 2);
    final h = sinDlat * sinDlat + math.cos(lat1) * math.cos(lat2) * sinDlng * sinDlng;
    return 2 * r * math.asin(math.sqrt(h));
  }

  void _addGasStationWaypoint(GasStation s) {
    final currentPos = ref.read(navStateProvider)?.pos;
    if (currentPos == null) return;
    final stationLoc = LatLng(s.lat, s.lon);
    final stationDist = _haversineM(currentPos, stationLoc);
    // 현위치 기준 거리 오름차순으로 이미 통과하지 않은 경유지들 사이에 삽입
    int insertIdx = _liveWaypoints.length;
    for (int i = _passedWaypointCount; i < _liveWaypoints.length; i++) {
      if (stationDist < _haversineM(currentPos, _liveWaypoints[i])) {
        insertIdx = i;
        break;
      }
    }
    _liveWaypoints.insert(insertIdx, stationLoc);
    // 레이어가 이미 초기화된 이후에 추가되는 경우에만 즉시 심볼 하나를
    // 그린다 — 레이어 자체가 아직이면 _initDestLayer()가 첫 실행 시
    // _liveWaypoints를 순회하며 알아서 커버하므로 여기서 중복 추가하지 않음.
    if (_canCallMap() && _destLayerReady) {
      _mlCtrl?.addSymbol(ml.SymbolOptions(
        geometry: _toMl(stationLoc),
        iconImage: _kWpIcon,
        iconSize: _kWpIconSize,
        iconAnchor: 'bottom',
        zIndex: 5,
      ));
    }
    setState(() => _selectedGasStation = null);
    // S5 판단: 이 reroute는 GPS 지터로 반복 발화하는 자동 이탈 재탐색이
    // 아니라, 사용자가 목록에서 주유소를 탭해 명시적으로 1회 트리거하는
    // 호출이다 — isStationary 게이트를 적용하면 정차 중 추가한 경유지가
    // 반영되지 않는 채로 조용히 묵살돼 실제 사용자 요청을 드롭하는 회귀가
    // 된다. 재탐색 폭주 억제(§2)는 자동 이탈 감지 경로(_triggerReroute)에만
    // 적용하고 여기는 게이트하지 않는다 — HANDOFF_0807_S5 §2 참고,
    // 최종 판단은 이번 세션 구현 시점에 코드를 읽고 내렸다.
    _reroute(currentPos, silent: true);
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
    // 후면단속카메라(18번) — 경로와 무관한 정적 전체 목록을 1회 로드해 주입.
    // route_progress_provider._advance()가 다음 GPS fix부터 이 목록으로 판정한다.
    ref.read(routeProgressProvider.notifier).setRearCameras(await RearCamera.loadAll());
    _voiceEngine = VoiceEngine(_profile!, landmarkService: _landmarkService);
    _structureVoiceEngine = StructureVoiceEngine(_profile!);
    _curveVoiceEngine = CurveVoiceEngine(_profile!);
    _rearCameraVoiceEngine = RearCameraVoiceEngine();
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
    // resumedFromId는 역지오코딩 성공 여부와 무관하게 항상 붙어야 하므로
    // (지오코딩 실패는 흔한 부가정보 손실일 뿐, 재개 연결 정보 유실로
    // 이어져선 안 된다) try 블록 밖에서 먼저 반영해둔다.
    var finalLog = tourLog.copyWith(resumedFromId: widget.resumedFromId);
    try {
      final geocoding = GeocodingService();
      final results = await Future.wait([
        geocoding.reverseGeocode(tourLog.startLat, tourLog.startLng),
        geocoding.reverseGeocode(tourLog.endLat, tourLog.endLng),
      ]);
      finalLog = finalLog.copyWith(
        startAddress: results[0],
        endAddress: results[1],
      );
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
  // forceBearingNorth=true 시 bearing을 0(북쪽)으로 고정하고 offset을 적용하지 않는다.
  Future<void> _recenter(LatLng loc, {bool animate = false, double speedKmh = 0, double? headingDeg, bool forceBearingNorth = false}) async {
    if (!_styleLoaded || !_canCallMap()) return;
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

    final brg = forceBearingNorth ? 0.0 : (headingDeg ?? _lastHeadingDeg ?? 0.0);
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
    if (!_styleLoaded || !_canCallMap()) return;
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
    final courseLineColor = ref.read(skinProvider).colors.courseLineColor;
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
    if (c == null || !_styleLoaded || !_locLayerReady || !_canCallMap()) return;
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
        iconSize: 0.52, // 96px 원본 기준 실사용 크기 — 실기기 확인 후 추가 조정
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
    if (!_styleLoaded || !_canCallMap()) return;
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
    for (final t in PoiService.serverSupportedTypes) {
      final threshold = t.minZoomLevel.toDouble();
      if (_stickyEligibleTypes.contains(t)) {
        if (zoom >= threshold - 0.3) result.add(t);
      } else {
        if (zoom >= threshold + 0.3) result.add(t);
      }
    }
    return result;
  }

  /// 하단 카드 현위치(시/군/구) 표시용 — 300m 이동 또는 60초 경과 중 먼저
  /// 오는 조건에서만 기기 내장 geocoder를 호출한다(_coarseGeoThrottle,
  /// PoiFetchThrottle 재사용). 실패 시 _currentLocLabel은 이전 값을 유지
  /// (§4 명세: 실패/미조회면 목적지명만 계속 표시, 빈 상태로 갱신하지 않음).
  Future<void> _maybeFetchCoarseLocation(LatLng pos) async {
    if (!_coarseGeoThrottle.shouldFetch(center: pos)) return;
    // shouldFetch가 true인 이 자리에서(await 전에) 즉시 커밋 — 응답이
    // 느릴 때 디바운스가 영원히 무장되지 않는 회귀(S2 429 폭주 원인)를
    // 다시 도입하지 않기 위함(_ambientThrottle과 동일 패턴).
    _coarseGeoThrottle.markStarted(center: pos);
    final label = await GeocodingService().reverseGeocodeCoarse(pos.latitude, pos.longitude);
    if (!mounted || label == null) return;
    setState(() => _currentLocLabel = label);
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
    if (ctrl == null || !_styleLoaded || gpsPos == null || !_canCallMap()) return;
    if (_ambientFetchInFlight) return; // 진행 중인 fetch가 있으면 즉시 포기

    final targetTypes = _resolveEligibleTypes(_navZoom);
    _stickyEligibleTypes = targetTypes; // 매 틱 갱신 — fetch 성사 여부와 무관
    if (targetTypes.isEmpty) {
      _ambientFetchGen++; // 진행 중이던 fetch가 있으면 응답을 무효화
      if (_ambientPois.isNotEmpty) {
        _ambientPois = const [];
        _updatePoiLayer(const []);
      }
      _ambientThrottle.clearTypes();
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

    if (!_ambientThrottle.shouldFetch(center: approxCenter, types: targetTypes)) {
      return;
    }
    // 선커밋 — 아래 await(getVisibleRegion/fetchPoisInBounds) 이전에 즉시
    // 확정한다. 응답 후(성공 경로)에서만 커밋하면 응답이 느릴 때 디바운스가
    // 영원히 무장되지 않는다(2026-08-05 S2에서 발견한 429 폭주의 진짜 원인).
    _ambientThrottle.markStarted(center: approxCenter, types: targetTypes);

    _ambientFetchInFlight = true;
    try {
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

      // 캐시 적중률을 위해 네트워크 요청·캐시 put/get 모두 바깥쪽으로 스냅한
      // bbox를 쓴다(자동추종 모드는 GPS ± delta라 1m만 움직여도 원래는
      // 매번 미스했다) — 표시(selectForAmbientDisplay)는 실제 뷰포트를 써야
      // 하므로 후보를 먼저 실제 뷰포트로 필터링한다(아래).
      final snapped = PoiService.snapBoundsOutward(
        south: south,
        west: west,
        north: north,
        east: east,
      );

      final cached = _poiRegionCache.tryGet(
        south: snapped.south,
        west: snapped.west,
        north: snapped.north,
        east: snapped.east,
        types: targetTypes,
      );

      final List<Poi> pois;
      if (cached != null) {
        pois = cached;
      } else {
        try {
          final fetched = await ref.read(poiServiceProvider).fetchPoisInBounds(
                south: snapped.south,
                west: snapped.west,
                north: snapped.north,
                east: snapped.east,
                types: targetTypes.toList(),
                tag: 'ambient-nav',
              );
          if (!mounted || myGen != _ambientFetchGen) return;
          _poiRegionCache.put(
            south: snapped.south,
            west: snapped.west,
            north: snapped.north,
            east: snapped.east,
            types: targetTypes,
            pois: fetched,
          );
          pois = fetched;
        } on PoiFetchException {
          // 실패(429/네트워크 오류/서킷 오픈) — 캐시에 넣지 않고 기존
          // _ambientPois를 유지한 채 조용히 종료한다.
          return;
        }
      }

      final visible = pois
          .where((p) =>
              p.location.latitude >= south &&
              p.location.latitude <= north &&
              p.location.longitude >= west &&
              p.location.longitude <= east)
          .toList();

      final limited = PoiService.selectForAmbientDisplay(
        candidates: visible,
        south: south,
        north: north,
        west: west,
        east: east,
        center: center,
        maxCount: 20,
      );

      _ambientPois = limited;
      _updatePoiLayer(limited);
    } finally {
      _ambientFetchInFlight = false;
    }
  }

  /// 목적지/경유지는 widget 생명주기 동안 불변(ctor의 final 필드, 재할당 없음)
  /// 이므로 puck과 달리 틱마다 갱신할 필요 없이 스타일 로드 후 1회만 설정한다.
  /// route 레이어 위, puck 레이어 아래에 오도록 puck보다 먼저 생성한다.
  Future<void> _initDestLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null || _destLayerReady) return;
    _destLayerReady = true;
    // widget.waypoints(불변, 생성 시점 고정)이 아니라 _liveWaypoints(런타임
    // 가변 복사본)를 순회 — 이 메서드가 처음 도는 시점까지 이미
    // _addGasStationWaypoint()로 추가된 경유지까지 커버하기 위함.
    // 스냅샷 복사본을 순회한다 — await 사이에 _addGasStationWaypoint()가
    // _liveWaypoints를 변경하면(예: 플로팅 오버레이 복귀로 _onStyleLoaded가
    // 재실행되는 동안) ConcurrentModificationError가 난다(code-auditor 지적).
    for (final wp in List<LatLng>.of(_liveWaypoints)) {
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
    // 스타일 재주입 시 네이티브 소스/레이어/심볼이 파괴·재생성되므로 Dart의
    // "1회만 실행" 가드를 초기화해 재생성 경로를 다시 태운다
    // (main_map_screen.dart와 동일한 패턴, A-5).
    _locLayerReady = false;
    _destLayerReady = false;
    _navRouteArrowLayerReady = false;
    // 레이어 설치 후 진입 시 이미 있는 경로 즉시 반영
    _initRouteLayer().whenComplete(() async {
      if (_routePoints.length >= 2 && _canCallMap()) {
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
      await _mlCtrl?.addImage(_kRouteArrowIcon, await renderRouteArrowPng());
      await _initNavRouteArrowLayer();
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
        final isNorthUp = !(ref.read(navHeadingUpProvider).value ?? true);
        _recenter(pos,
            animate: true,
            speedKmh: speedKmh,
            headingDeg: isNorthUp ? null : _resolveHeading(speedKmh, ns?.headingDeg),
            forceBearingNorth: isNorthUp);
      }
    });
  }

  void _tapCompass() {
    _compassNorthTimer?.cancel();
    ref.read(navHeadingUpProvider.notifier).set(false); // 노스업 전환
    // 수동 모드(팬/줌)에서는 GPS 틱이 _recenter를 스킵하므로
    // 현재 카메라 위치·줌을 유지한 채 bearing만 북쪽(0°)으로 직접 회전.
    if (_isManualMode && _canCallMap()) {
      _mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(0));
    }
    _compassNorthTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      ref.read(navHeadingUpProvider.notifier).set(true); // 헤딩업 복귀
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
    // await 호출 — 게이트 통과 후 PIP 진입 경쟁이 발생할 수 있으므로
    // MissingPluginException만 잡는 최후 방어선을 추가한다.
    if (_canCallMap()) {
      try {
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
        if (_canCallMap()) {
          await _mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(0));
        }
      } on MissingPluginException catch (e) {
        debugPrint('YNAV_MAP_GATE MissingPluginException suppressed in _openCourseSheet: $e');
      }
    }

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
    final off = offsetOrigin(origin.latitude, origin.longitude, heading, 50);
    final routeOrigin = LatLng(off.lat, off.lng);
    try {
      final routes = await RoutingService.fetchRoutes(
        origin: routeOrigin,
        destination: dest,
        waypoints: widget.waypoints.sublist(_passedWaypointCount),
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
      if (_styleLoaded && _canCallMap()) {
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
      if (_styleLoaded && _canCallMap()) {
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
      final isNorthUp = !(ref.read(navHeadingUpProvider).value ?? true);
      _recenter(pos,
          animate: true,
          speedKmh: speedKmh,
          headingDeg: isNorthUp ? null : _resolveHeading(speedKmh, ns?.headingDeg),
          forceBearingNorth: isNorthUp);
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
    if (_styleLoaded && _canCallMap()) {
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
      final isNorthUp = !(ref.read(navHeadingUpProvider).value ?? true);
      _recenter(pos,
          animate: true,
          speedKmh: speedKmh,
          headingDeg: isNorthUp ? null : _resolveHeading(speedKmh, ns?.headingDeg),
          forceBearingNorth: isNorthUp);
    }
  }

  Future<void> _recolorNavRouteLayer(int idx) async {
    final ctrl = _mlCtrl;
    if (ctrl == null || !_styleLoaded || !_canCallMap()) return;
    final courseLineColor = ref.read(skinProvider).colors.courseLineColor;
    if (_navRouteArrowLayerReady) await ctrl.removeLayer(_navRouteArrowLayerId);
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
    if (_navRouteArrowLayerReady) {
      await ctrl.addSymbolLayer(
        _navRouteSourceId,
        _navRouteArrowLayerId,
        const ml.SymbolLayerProperties(
          symbolPlacement: 'line',
          symbolSpacing: 80.0,
          iconImage: _kRouteArrowIcon,
          iconSize: 0.6,
          iconRotationAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        belowLayerId: 'waterway-name',
      );
    }
  }

  Future<void> _initNavRouteArrowLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null) return;
    await ctrl.addSymbolLayer(
      _navRouteSourceId,
      _navRouteArrowLayerId,
      const ml.SymbolLayerProperties(
        symbolPlacement: 'line',
        symbolSpacing: 80.0,
        iconImage: _kRouteArrowIcon,
        iconSize: 0.6,
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      belowLayerId: 'waterway-name',
    );
    _navRouteArrowLayerReady = true;
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
    if (ctrl == null || !_styleLoaded || _showCourseSheet || !_canCallMap()) return;
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

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navStateProvider);
    final step = _steps[_stepIdx];
    // 카드에 표시할 "다가오는 회전" — 마지막 step이면 step 자신(목적지)으로 폴백
    final upcoming = _stepIdx + 1 < _steps.length ? _steps[_stepIdx + 1] : step;
    final daylightCycle = ref.watch(daylightCycleProvider);
    final daylightProgress = daylightCycle?.progress ?? 0.5;
    final isDay = daylightCycle?.isDay ?? true;
    final cs = Theme.of(context).colorScheme;
    // 라운드7: 우측 버튼 5개·속도계·하단 카드 확인버튼의 스킨 연동 색상.
    final skinColors = ref.watch(skinProvider).colors;
    final brandColor = skinColors.brand;
    final successColor = skinColors.success;
    final dangerColor = skinColors.danger;
    final progress = ref.watch(routeProgressProvider);
    // 후면단속카메라(18번) 게이지 활성 여부 — 접근구간(150m 이내) + 사후구간
    // 전체. 활성 중엔 좌측 속도계가 게이지로 변신하고 DaylightBar를 숨긴다.
    final cameraGaugeActive = progress != null &&
        (progress.inPostZone ||
            progress.distToNextCameraM <= CameraApproachGauge.kThresholdM);
    final cameraOverSpeed = progress != null &&
        progress.inPostZone &&
        (navState?.speedKmh ?? 0) > progress.nextCameraSpeedKmh;

    ref.listen<AsyncValue<MapLanguage>>(mapLanguageProvider, (_, next) {
      final raw = _rawStyle;
      if (raw == null) return;
      final lang = next.value ?? MapLanguage.korean;
      if (mounted) setState(() => _styleJson = applyMapLanguageToStyle(raw, lang));
    });

    ref.listen<bool>(isOnlineProvider, (prev, next) {
      if (next && !(prev ?? false) && _isOfflineRouting) {
        final pos = ref.read(navStateProvider)?.pos;
        if (pos != null && mounted) _reroute(pos, silent: true);
      }
    });

    // 하단 ETA 카드(_etaCardKey) 실측 높이 갱신 — 우측 버튼 컬럼의 bottom
    // 오프셋 계산용(1-C). 매 프레임 후 측정해 값이 바뀐 경우에만 setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _etaCardKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && (box.size.height - _etaCardHeight).abs() > 0.5) {
        setState(() => _etaCardHeight = box.size.height);
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (didPop) return;
        // 도착 트리거(게이트 적용) vs 뒤로가기 트리거(게이트 없음)를 반드시
        // 구분한다 — _showExitConfirm/_arrivalBannerVisible은 GPS 도착 판정
        // 즉시(라이더 조작 없이) true가 되므로, 이 값들만으로 "뒤로가기를
        // 이미 눌렀는지"를 판단하면 도착 직후 첫 뒤로가기가 _canExit
        // 지오펜스+속도 게이트를 건너뛰고 즉시 종료돼버린다(code-auditor 지적,
        // 2026-07-31 — 안전장치 우회 버그).
        final gated = _arrivalBannerVisible;
        // 도착 중엔 온스크린 "내비게이션 종료" 버튼과 동일하게 _canExit로만
        // 판단(정차 전엔 뒤로가기를 몇 번 눌러도 종료되지 않음). 도착과 무관한
        // 뒤로가기 트리거는 _backExitArmed로 "1차: 카드 전환 / 2차: 즉시 종료"의
        // 시간제한 없는 더블프레스를 그대로 유지한다.
        final canForceExit = gated ? _canExit : _backExitArmed;
        if (canForceExit) {
          _exitNav();
        } else {
          setState(() {
            _showExitConfirm = true;
            if (!gated) _backExitArmed = true;
          });
        }
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
              localIdeographFontFamily: _ideographFontFamily,
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

          if (_isOfflineRouting)
            Positioned(
              top: MediaQuery.of(context).padding.top +
                  (_isManualMode ? 132 : 88),
              left: 60,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.signal_wifi_off, color: Colors.white70, size: 14),
                    SizedBox(width: 6),
                    Text(
                      '신호 없음 — 기존 경로로 안내 중',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          // ── 상단 카드1/2 (회전 안내 / 도착) ─────────────────────────────────
          // 라운드7: 독립 도착 배너를 폐기하고 카드1(아래)이 내부에서
          // _arrivalBannerVisible 분기로 "목적지 도착"까지 표시한다. 카드1은
          // 이제 항상 렌더링된다(더 이상 이 Positioned 전체를 숨기지 않음).
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // (A) 메인 상단 카드 — 도착 중엔 내부에서 "목적지 도착"으로 분기.
                // §5(HANDOFF_0807_S8): 자체 위젯(NavTopCard)으로 분리 — 컨텐츠에
                // 맞춰 늘어나되 기존 62% 밑으로는 안 줄어드는 ConstrainedBox+
                // IntrinsicWidth 레이아웃(nav_top_card.dart 헤더 주석 참고),
                // nav_screen.dart 전체를 마운트하지 않고도 위젯 테스트 가능.
                Builder(builder: (_) {
                  final raw = _cardRemainingM > 0
                      ? _TurnStep._formatDist(_cardRemainingM / 1000.0)
                      : step.dist;
                  final parts = (_cardRemainingM > 0 || step.dist.isNotEmpty)
                      ? _TurnStep._splitDistStr(raw)
                      : ('', '');
                  return NavTopCard(
                    svgAsset: upcoming.svgAsset,
                    minWidth: MediaQuery.of(context).size.width * 0.62,
                    maxWidth: MediaQuery.of(context).size.width - 12,
                    arrivalBannerVisible: _arrivalBannerVisible,
                    arrivalDurationText: _arrivalDurationS != null
                        ? '소요시간 ${formatTourDuration(_arrivalDurationS!)}'
                        : null,
                    distMain: parts.$1,
                    distUnit: parts.$2,
                    streetName: upcoming.streetNames.isNotEmpty ? upcoming.streetNames.first : null,
                    onTap: () {
                      if (!_arrivalBannerVisible && _stepIdx < _steps.length - 1) {
                        setState(() => _stepIdx++);
                        _announceStep(_stepIdx);
                      }
                    },
                  );
                }),
                // (B) 다음 이벤트 별개 카드 — 도착 중엔 숨김(카드2가 새 목업엔 없음)
                if (_stepIdx + 2 < _steps.length && !_arrivalBannerVisible)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.62 * 0.70,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          child: Row(
                            children: [
                              SvgPicture.asset(_steps[_stepIdx + 2].svgAsset, width: 33, height: 33),
                              const SizedBox(width: 8),
                              Text('다음', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 21, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _steps[_stepIdx + 2].streetNames.firstOrNull ?? _steps[_stepIdx + 2].label,
                                  style: TextStyle(color: cs.onSurface, fontSize: 21, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── 구조물/급커브 알림 배지 (회전카드와 완전히 별개 — 16번) ──────────
          if (progress != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 108,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.center,
                child: _StructureCurveAlert(progress: progress, cs: cs),
              ),
            ),

          // ── 좌측 속도계 (상단 30% 높이, 네이버지도 배치 참고) ─────────────────
          // 후면단속카메라 접근/사후구간(18번)엔 이 자리에서 속도계 대신
          // RearCameraGaugeSwitcher가 접근 웨지·사후 SLOW 링으로 변신한다.
          Positioned(
            left: 12,
            top: MediaQuery.of(context).size.height * 0.30,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: RearCameraGaugeSwitcher(
                progress: progress,
                speedKmh: navState?.speedKmh ?? 0,
                firstFixReceived: navState?.firstFix ?? false,
                brandColor: brandColor,
              ),
            ),
          ),

          // ── 좌측: Daylight 바 (속도계 아래, 카메라 게이지 활성 중엔 숨김) ──────
          if (!cameraGaugeActive)
            Positioned(
              left: 12,
              top: MediaQuery.of(context).size.height * 0.30 + 100,
              bottom: 160,
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

          // ── 우측 버튼 5개 통합 (라운드7) ──────────────────────────────────────
          // 주유소→나침반→현위치→줌인→줌아웃 순서, 전부 68px 원형+스킨 브랜드색.
          // bottom 오프셋은 하단 ETA 카드 실측 높이(_etaCardHeight, 기기별
          // MediaQuery.padding.bottom을 이미 흡수한 값) 기반으로 역산해
          // 줌아웃이 카드에 가려지는 문제를 근본적으로 없앤다(매직넘버 폐기).
          Positioned(
            right: 12,
            bottom: 12 + _etaCardHeight + 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NavIconBtn(
                  icon: Icons.local_gas_station,
                  color: brandColor,
                  onTap: () {
                    final pos = ref.read(navStateProvider)?.pos;
                    if (pos == null) return;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _GasStationSheet(
                        lat: pos.latitude,
                        lon: pos.longitude,
                        onSelected: (s) {
                          setState(() => _selectedGasStation = s);
                          if (_canCallMap()) {
                            _mlCtrl?.animateCamera(ml.CameraUpdate.newLatLngZoom(
                              ml.LatLng(s.lat, s.lon), 14,
                            ));
                          }
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _CompassBtn(
                  headingDeg: () {
                    final isNorthUp = !(ref.watch(navHeadingUpProvider).value ?? true);
                    if (isNorthUp) return 0.0;
                    return _resolveHeading(navState?.speedKmh ?? 0, navState?.headingDeg) ?? 0.0;
                  }(),
                  color: brandColor,
                  onTap: _tapCompass,
                ),
                const SizedBox(height: 10),
                _NavIconBtn(
                  icon: _isManualMode ? Icons.gps_fixed : Icons.my_location,
                  color: brandColor,
                  onTap: () {
                    final ns = ref.read(navStateProvider);
                    final pos = ns?.pos;
                    if (pos == null) return;
                    _recenterTimer?.cancel();
                    setState(() => _isManualMode = false);
                    final speedKmh = ns?.speedKmh ?? 0;
                    final isNorthUp = !(ref.read(navHeadingUpProvider).value ?? true);
                    _recenter(pos,
                        animate: true,
                        speedKmh: speedKmh,
                        headingDeg: isNorthUp ? null : _resolveHeading(speedKmh, ns?.headingDeg),
                        forceBearingNorth: isNorthUp);
                  },
                ),
                // 현위치 ↔ 줌인 사이만 의도적으로 넓게(라운드3 홈 화면 34dp 재사용).
                const SizedBox(height: 34),
                _NavIconBtn(
                  icon: Icons.add,
                  color: brandColor,
                  onTap: () { if (_canCallMap()) _mlCtrl?.animateCamera(ml.CameraUpdate.zoomIn()); },
                ),
                const SizedBox(height: 4),
                _NavIconBtn(
                  icon: Icons.remove,
                  color: brandColor,
                  onTap: () { if (_canCallMap()) _mlCtrl?.animateCamera(ml.CameraUpdate.zoomOut()); },
                ),
              ],
            ),
          ),

          // ── 하단 ETA 바 ─────────────────────────────────────────────────────
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                key: _etaCardKey,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 최상단 진행 바
                    LinearProgressIndicator(
                      value: (_stepIdx + 1) / _steps.length,
                      backgroundColor: cs.primaryContainer,
                      color: cs.primary,
                      minHeight: 12,
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 14),
                        child: Builder(builder: (_) {
                          // 라운드7: 도착(4-a) 또는 뒤로가기/온스크린 종료(4-b) 트리거로
                          // _showExitConfirm이 켜지면 [탐색 유지|내비게이션 종료] 2버튼
                          // 레이아웃으로 통째로 스왑한다. 게이트(_canExit)는 도착
                          // 트리거(_arrivalBannerVisible)일 때만 적용 — 뒤로가기/온스크린
                          // 종료 경로는 도착과 무관하므로 게이트 없이 즉시 활성.
                          if (_showExitConfirm) {
                            final gated = _arrivalBannerVisible;
                            final exitEnabled = !gated || _canExit;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (gated)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      _canExit ? '10초 후 자동 종료' : '정차 후 종료 가능',
                                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Row(
                                    children: [
                                      // ── 탐색 유지 ──
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            _exitAutoCloseTimer?.cancel();
                                            setState(() {
                                              _showExitConfirm = false;
                                              _backExitArmed = false;
                                              if (_arrivalBannerVisible) {
                                                _arrivalBannerVisible = false;
                                                _canExit = false;
                                              }
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: successColor,
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: const Text(
                                              '탐색 유지',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // ── 내비게이션 종료 ──
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: exitEnabled
                                              ? () {
                                                  _exitAutoCloseTimer?.cancel();
                                                  _exitNav();
                                                }
                                              : null,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: exitEnabled ? dangerColor : cs.surfaceContainerHigh,
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              '내비게이션 종료',
                                              style: TextStyle(
                                                color: exitEnabled ? Colors.white : cs.onSurfaceVariant,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }
                          final canReroute = navState?.pos != null && !_isRerouting;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // ── 재탐색 버튼 (왼쪽) ──
                              GestureDetector(
                                onTap: canReroute ? _openCourseSheet : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.alt_route, size: 26,
                                          color: canReroute ? cs.onSurface : cs.onSurface.withValues(alpha: 0.35)),
                                      const SizedBox(height: 2),
                                      Text('재탐색', style: TextStyle(fontSize: 11, color: canReroute ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.3))),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 1, height: 44, color: cs.outline.withValues(alpha: 0.4)),
                              // ── 중앙 정보 (목적지 + ETA + 거리) ──
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Builder(builder: (_) {
                                        // 3초마다 목적지 이름 ↔ 현위치(시/군/구) 교대 표시.
                                        // 현위치 조회가 아직 안 됐거나 실패했으면(null) 교대하지
                                        // 않고 목적지 이름만 계속 보여준다(빈 상태로 깜빡이지
                                        // 않게). ref.watch는 분기와 무관하게 항상 먼저 호출해
                                        // 구독이 매 빌드 끊기지 않게 한다.
                                        final destName =
                                            ref.watch(mapInteractionProvider).destinationName ?? '목적지';
                                        final label = (_showCurrentLocInCard && _currentLocLabel != null)
                                            ? _currentLocLabel!
                                            : destName;
                                        return Text(
                                          label,
                                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.normal, color: cs.onSurface),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      }),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _etaText(_durationMin),
                                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.onSurface),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _remainingRouteM > 0
                                                ? '${(_remainingRouteM / 1000).toStringAsFixed(1)} km'
                                                : '--',
                                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 1, height: 44, color: cs.outline.withValues(alpha: 0.4)),
                              // ── 종료 버튼 (오른쪽) — 즉시 종료 대신 확인 카드로 전환
                              // (온스크린 종료도 뒤로가기와 동일하게 2단계로 통일, 2026-07-30 마스터 승인).
                              // 이 행은 !_showExitConfirm일 때만 보이고 도착 트리거는 항상
                              // _showExitConfirm을 강제로 켜므로, 여기 도달했다는 건 항상
                              // 뒤로가기와 동일한 "게이트 없는" 트리거(b)라는 뜻 — _backExitArmed도
                              // 함께 세워 이후 물리 뒤로가기 한 번으로 바로 종료되게 한다. ──
                              GestureDetector(
                                onTap: () => setState(() {
                                  _showExitConfirm = true;
                                  _backExitArmed = true;
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.close_rounded, size: 26, color: cs.error),
                                      const SizedBox(height: 2),
                                      Text('종료', style: TextStyle(fontSize: 11, color: cs.error)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ],
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

          // ── 주유소 선택 카드 ────────────────────────────────────────────────────
          if (_selectedGasStation != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _GasStationSelectionCard(
                station: _selectedGasStation!,
                onAddWaypoint: () => _addGasStationWaypoint(_selectedGasStation!),
                onClose: () => setState(() => _selectedGasStation = null),
              ),
            ),

          // ── 후면단속카메라 사후구간 과속 경고 오버레이 (18번, Stack 최상단) ────
          Positioned.fill(
            child: SpeedWarningOverlay(active: cameraOverSpeed),
          ),

        ],
      ),
      ),
    );
  }
}

// ── 주유소 바텀시트 ────────────────────────────────────────────────────

class _GasStationSheet extends StatefulWidget {
  final double lat;
  final double lon;
  final void Function(GasStation) onSelected;
  const _GasStationSheet({required this.lat, required this.lon, required this.onSelected});

  @override
  State<_GasStationSheet> createState() => _GasStationSheetState();
}

class _GasStationSheetState extends State<_GasStationSheet> {
  String _fuel = 'B027'; // B027=휘발유, B034=고급휘발유
  late Future<List<GasStation>> _future;

  @override
  void initState() {
    super.initState();
    _future = GasStationService.fetchNearby(lat: widget.lat, lon: widget.lon, fuel: _fuel);
  }

  void _switchFuel(String fuel) {
    if (_fuel == fuel) return;
    setState(() {
      _fuel = fuel;
      _future = GasStationService.fetchNearby(lat: widget.lat, lon: widget.lon, fuel: fuel);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 타이틀 + 연료 토글
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(Icons.local_gas_station, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '근처 최저가 주유소',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // 연료 토글 칩
                _FuelChip(label: '휘발유', selected: _fuel == 'B027', onTap: () => _switchFuel('B027')),
                const SizedBox(width: 6),
                _FuelChip(label: '고급휘발유', selected: _fuel == 'B034', onTap: () => _switchFuel('B034')),
              ],
            ),
          ),
          const Divider(height: 1),
          // 결과 목록
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: FutureBuilder<List<GasStation>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final stations = snapshot.data ?? [];
                if (stations.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        '5km 내 주유소 정보를 찾을 수 없습니다',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: stations.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 20),
                  itemBuilder: (context, i) {
                    final s = stations[i];
                    final displayPrice = _fuel == 'B034' ? s.premiumPrice : s.price;
                    return ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        widget.onSelected(s);
                      },
                      dense: true,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        s.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_distanceText(s.distanceM)}  •  ${s.brand.isNotEmpty ? s.brand : "기타"}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      trailing: displayPrice != null
                          ? Text(
                              '${_formatPrice(displayPrice)}원',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: i == 0 ? cs.primary : cs.onSurface,
                              ),
                            )
                          : Text('정보 없음', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    );
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  static String _distanceText(double m) {
    if (m < 1000) return '${m.toStringAsFixed(0)}m';
    return '${(m / 1000).toStringAsFixed(1)}km';
  }

  static String _formatPrice(int price) {
    final s = price.toString();
    if (s.length <= 3) return s;
    return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
  }
}

class _FuelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FuelChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ── 주유소 선택 하단 카드 ──────────────────────────────────────────────────────

class _GasStationSelectionCard extends StatelessWidget {
  final GasStation station;
  final VoidCallback onAddWaypoint;
  final VoidCallback onClose;
  const _GasStationSelectionCard({
    required this.station,
    required this.onAddWaypoint,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_gas_station, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      station.name,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                station.address,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onAddWaypoint,
                      child: const Text('경유지로 설정'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: onClose,
                    child: const Text('닫기'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Speedometer extends StatefulWidget {
  final double speedKmh;
  final bool firstFixReceived;
  final Color brandColor;
  const _Speedometer({
    required this.speedKmh,
    required this.firstFixReceived,
    required this.brandColor,
  });

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
        border: Border.all(color: widget.brandColor, width: 2.5),
        boxShadow: [BoxShadow(color: widget.brandColor.withValues(alpha: 0.25), blurRadius: 16)],
      ),
      child: widget.firstFixReceived
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.speedKmh.toStringAsFixed(0),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: widget.brandColor, height: 1.0),
                ),
                Text('km/h', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            )
          : FadeTransition(
              opacity: _blinkAnim,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('GPS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: widget.brandColor, height: 1.1)),
                  Text('검색 중', style: TextStyle(fontSize: 11, color: widget.brandColor)),
                ],
              ),
            ),
    );
  }
}

/// 좌측 속도계 ↔ 후면단속카메라 게이지(18번) 전환 스위처.
///
/// - idle(카메라 무관): 기존 88×88 [_Speedometer].
/// - approach(distToNextCameraM <= 150 && !inPostZone): 176×176
///   [CameraApproachGauge]. idle→approach 전환은 [AnimatedSize]로 심플
///   스케일업(88→176)한다 — 좌측 위치(Positioned left/top)는 고정.
/// - post(inPostZone): 176×176 [CameraPostZoneGauge]. approach→post로
///   바뀌는 순간(inPostZone false→true) [CameraTransitionFlash]를 게이지
///   내부에 짧게 얹는다.
/// - 다시 idle로 돌아가면 176→88 스케일다운.
///
/// 클래스명이 public인 이유: nav_screen.dart 전체를 마운트하지 않고도
/// (rear_camera_gauge.dart의 위젯들과 동일하게) 위젯 테스트에서 직접
/// import해 상태머신(특히 mount 시점 플래시 오탐)을 검증하기 위해서다.
class RearCameraGaugeSwitcher extends StatefulWidget {
  final RouteProgress? progress;
  final double speedKmh;
  final bool firstFixReceived;
  final Color brandColor;
  const RearCameraGaugeSwitcher({
    super.key,
    required this.progress,
    required this.speedKmh,
    required this.firstFixReceived,
    required this.brandColor,
  });

  @override
  State<RearCameraGaugeSwitcher> createState() => _RearCameraGaugeSwitcherState();
}

enum _CamGaugeMode { idle, approach, post }

class _RearCameraGaugeSwitcherState extends State<RearCameraGaugeSwitcher> {
  bool _showFlash = false;
  late bool _wasInPostZone;

  @override
  void initState() {
    super.initState();
    // didUpdateWidget()은 위젯이 처음 마운트될 때는 호출되지 않으므로
    // (initState+build만 호출) 여기서 초기값을 시드해야 한다. 시드하지
    // 않으면 이미 inPostZone=true인 상태로 새로 생성된 위젯(예: 앱
    // 재시작/화면 복귀 시 라이더가 마침 사후구간 안에 있는 경우)이 다음
    // GPS tick의 didUpdateWidget에서 "false→true 전환"으로 오인되어
    // CameraTransitionFlash가 허위 재생된다.
    _wasInPostZone = widget.progress?.inPostZone ?? false;
  }

  _CamGaugeMode get _mode {
    final p = widget.progress;
    if (p == null) return _CamGaugeMode.idle;
    if (p.inPostZone) return _CamGaugeMode.post;
    if (p.distToNextCameraM <= CameraApproachGauge.kThresholdM) {
      return _CamGaugeMode.approach;
    }
    return _CamGaugeMode.idle;
  }

  @override
  void didUpdateWidget(covariant RearCameraGaugeSwitcher old) {
    super.didUpdateWidget(old);
    final nowPost = widget.progress?.inPostZone ?? false;
    if (nowPost && !_wasInPostZone) {
      // 0m 도달 순간(2-2) — 플래시를 얹는다. onComplete에서 스스로 제거된다.
      _showFlash = true;
    }
    _wasInPostZone = nowPost;
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;

    Widget content;
    switch (mode) {
      case _CamGaugeMode.idle:
        content = _Speedometer(
          speedKmh: widget.speedKmh,
          firstFixReceived: widget.firstFixReceived,
          brandColor: widget.brandColor,
        );
        break;
      case _CamGaugeMode.approach:
        content = CameraApproachGauge(
          key: const ValueKey('camera_approach_gauge'),
          distanceM: widget.progress!.distToNextCameraM,
        );
        break;
      case _CamGaugeMode.post:
        final p = widget.progress!;
        final remaining = (p.nextCameraPostZoneM - p.distToNextCameraM)
            .clampSafe(0.0, p.nextCameraPostZoneM.toDouble())
            .toDouble();
        content = CameraPostZoneGauge(
          key: const ValueKey('camera_post_zone_gauge'),
          remainingM: remaining,
        );
        break;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          content,
          if (_showFlash)
            CameraTransitionFlash(
              onComplete: () {
                if (mounted) setState(() => _showFlash = false);
              },
            ),
        ],
      ),
    );
  }
}

/// 우측 버튼 5개(주유소→나침반→현위치→줌인→줌아웃) 공용 원형 아이콘 버튼
/// (라운드7 — 기존 `_ZoomBtn`의 46×46 사각 스타일을 폐기하고 이 스타일로
/// 통합, 줌 인/아웃도 이 위젯을 재사용한다). 지름 68px, 아이콘 색은
/// 호출부에서 스킨 브랜드색(`skinProvider.colors.brand`)을 전달한다.
class _NavIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _NavIconBtn({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(color: cs.outline, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8)],
        ),
        child: Icon(icon, color: color, size: 32),
      ),
    );
  }
}

class _TurnStep {
  final String svgAsset;
  final String label;
  final String dist;
  final double rawDistKm; // GPS 거리 자동 진행용 원시 거리(km)
  final int type;
  final List<String> streetNames;
  const _TurnStep(this.svgAsset, this.label, this.dist, [this.rawDistKm = 0.0, this.type = 0, this.streetNames = const []]);

  factory _TurnStep.fromManeuver(ManeuverStep m,
      {bool isFinalDestination = true, StructureType? nearbyStructure}) {
    return _TurnStep(
      _svgAssetForType(m.type, m.roundaboutExitCount),
      _labelForType(
          m.type, m.roundaboutExitCount, isFinalDestination, nearbyStructure),
      _formatDist(m.distanceKm),
      m.distanceKm,
      m.type,
      m.streetNames,
    );
  }

  static const _svgBase = 'assets/images/nav_icons/';

  static String _svgAssetForType(int type, [int? roundaboutExitCount]) {
    switch (type) {
      case 10: case 20:
        return '${_svgBase}nav_right.svg';
      case 11:
        return '${_svgBase}nav_sharp_right.svg';
      case 12: case 13:
        return '${_svgBase}nav_uturn.svg';
      case 14:
        return '${_svgBase}nav_sharp_left.svg';
      case 15: case 21:
        return '${_svgBase}nav_left.svg';
      case 9: case 18: case 23:
        return '${_svgBase}nav_fork_right.svg';
      case 16: case 19: case 24:
        return '${_svgBase}nav_fork_left.svg';
      case 26: case 27:
        final exit = roundaboutExitCount ?? 0;
        if (exit == 1) return '${_svgBase}nav_roundabout_right.svg';
        if (exit == 3) return '${_svgBase}nav_roundabout_left.svg';
        return '${_svgBase}nav_roundabout_straight.svg';
      default:
        return '${_svgBase}nav_straight.svg';
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

/// 구조물(고가도로/터널/지하차도) 또는 지오메트리 감지 급커브가 앞에 있을 때
/// 표시하는 알림 배지. [_TurnStep] 파이프라인(Valhalla maneuver)과 완전히 별개로
/// [routeProgressProvider]를 직접 구독한다.
///
/// 표시 임계값(500 m / 400 m)은 안전 우선 원칙에 따라 넉넉하게 잡음.
class _StructureCurveAlert extends StatelessWidget {
  const _StructureCurveAlert({required this.progress, required this.cs});
  final RouteProgress progress;
  final ColorScheme cs;

  static const _kStructThresholdM = 500.0;
  static const _kCurveThresholdM  = 400.0;

  @override
  Widget build(BuildContext context) {
    final showStruct = progress.nextStructureType != null &&
        progress.distToNextStructureM <= _kStructThresholdM;
    final showCurve = progress.nextCurveDirection != null &&
        progress.distToNextCurveM <= _kCurveThresholdM;

    if (!showStruct && !showCurve) return const SizedBox.shrink();

    // 더 가까운 쪽을 표시; 거리가 같으면 구조물 우선 (safety-priority)
    if (showStruct &&
        (!showCurve ||
            progress.distToNextStructureM <= progress.distToNextCurveM)) {
      return _badge(
        icon: _structureIcon(progress.nextStructureType!),
        label: progress.nextStructureType!.labelKo,
        distM: progress.distToNextStructureM,
        color: const Color(0xFFFF8F00),
      );
    }
    return _badge(
      icon: Icons.warning_amber_rounded,
      label: progress.nextCurveDirection == CurveDirection.left
          ? '급커브 좌'
          : '급커브 우',
      distM: progress.distToNextCurveM,
      color: const Color(0xFFE64A19),
    );
  }

  Widget _badge({
    required IconData icon,
    required String label,
    required double distM,
    required Color color,
  }) {
    final distStr = distM < 1000
        ? '${distM.round()}m 앞'
        : '${(distM / 1000).toStringAsFixed(1)}km 앞';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            distStr,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  IconData _structureIcon(StructureType type) => Icons.warning_amber_rounded;
}

/// 나침반 버튼(라운드7: 68px로 확대, 고정 화살표만 스킨 브랜드색 — N/S/E/W
/// 라벨은 가독성 우선으로 기존 대비색 유지, PROGRESS.md 확인질문 Q1 참고).
class _CompassBtn extends StatelessWidget {
  final double headingDeg;
  final VoidCallback onTap;
  final Color color;
  const _CompassBtn({required this.headingDeg, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(color: cs.outline, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8)],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 회전하는 나침반 링 (N/S/E/W)
            Transform.rotate(
              angle: -headingDeg * math.pi / 180,
              child: SizedBox(
                width: 68,
                height: 68,
                child: Stack(
                  children: [
                    Positioned(top: 6, left: 0, right: 0,
                      child: Text('N', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.error, height: 1))),
                    Positioned(bottom: 6, left: 0, right: 0,
                      child: Text('S', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant, height: 1))),
                    Positioned(top: 0, bottom: 0, right: 7,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                          children: [Text('E', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant, height: 1))])),
                    Positioned(top: 0, bottom: 0, left: 7,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                          children: [Text('W', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant, height: 1))])),
                  ],
                ),
              ),
            ),
            // 고정 화살표 (항상 위를 가리킴) — 스킨 브랜드색
            Icon(Icons.navigation_rounded, size: 19, color: color),
          ],
        ),
      ),
    );
  }
}
