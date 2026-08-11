import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io' show Platform;
import 'dart:math' show Point, cos, sqrt, asin;

import 'package:flutter/foundation.dart'
    show kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, SystemNavigator, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/skin/skin_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/course_sheet.dart';
import '../../../core/widgets/daylight_bar.dart';
import '../../../core/widgets/map_ctrl_btn.dart';
import '../../../models/address_result.dart';
import '../../../models/map_language.dart';
import '../../../models/poi.dart';
import '../../../models/saved_place.dart';
import '../../../services/address_search_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/gas_station_service.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/native_engine.dart';
import '../../../services/poi_icon_renderer.dart';
import '../../../services/poi_service.dart';
import '../../../services/routing_service.dart';
import '../../../models/saved_route.dart';
import '../../../providers/app_providers.dart';
// ignore: unnecessary_import
import '../providers/map_providers.dart';
import '../style_language_transform.dart';
import '../../navigation/presentation/nav_screen.dart';
import '../../navigation/providers/nav_state_provider.dart';
import '../../settings/providers/settings_providers.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../tour_summary/presentation/tour_summary_list_screen.dart';
import '../poi_feature_picker.dart';
import '../poi_name_resolver.dart';
import '../poi_category.dart';
import 'waypoint_management_sheet.dart';

export 'main_map_screen.dart';

enum _TapAction { destination, origin }

/// 검색 결과 "어디로 추가할까요?" 시트의 선택 결과
enum _RouteAddAction { origin, waypoint, destination }

class _TappedPoi {
  final String? name;
  final String? category;
  const _TappedPoi({this.name, this.category});
}

/// Last-resort map framing. Reached ONLY when every earlier location source
/// fails to produce a fix: splash-screen boot acquisition
/// (`bootLocationProvider`, see splash_screen.dart) AND
/// `Geolocator.getLastKnownPosition()` here both come back empty — e.g.
/// location permission denied, or granted but the device has never cached a
/// fix. Camera only — never treated as the rider's location.
const LatLng kInitialMapView = LatLng(36.5, 127.5); // 한국 지리 중심 (서울 아님)

/// S0: 콜드 스타트 폴백 카메라 레이스 보정 상태기계.
///
/// `MapLibreMapController`(`_mlCtrl`)는 `onMapCreated`에서야 세팅되는데,
/// 플랫폼뷰 생성 대기(수백 ms) 중에 위치 fix가 먼저 도착하면 과거에는
/// null-safe 호출이 조용히 버려지고 다시는 재시도되지 않았다(2026-08-05
/// code-auditor 지적: `_openedAtFallback` 하나로 "폴백 좌표로 열렸는가"와
/// "카메라가 실측 fix로 보정됐는가"를 겹쳐 게이트를 걸면, boot-seed로 이미
/// _lastKnown이 채워져 있어도(=_openedAtFallback == false) 그 이후 도착하는
/// 진짜 첫 GPS fix가 이 레이스를 타는 순간 카메라가 세션 내내 부트 시점
/// 좌표에 고정되는 회귀가 생긴다).
///
/// 이 두 사실을 분리한다: 컨트롤러가 준비되지 않았으면([ctrlReady] false)
/// "폴백으로 열렸는지"와 무관하게 항상 목표를 보류한다. `onMapCreated`는
/// 카메라가 아직 실측 fix로 보정된 적이 없을 때만(=`corrected == false`)
/// 그 보류값을 적용한다.
///
/// 위젯 상태와 분리된 순수 로직이라 MapLibre 플랫폼뷰/위젯 pump 없이
/// `test/splash_boot_location_test.dart`가 직접 검증한다.
class FallbackRecenterState {
  LatLng? _pending;
  bool _corrected = false;

  /// 현재 보류 중인 목표(테스트 관찰용).
  LatLng? get pending => _pending;

  /// 카메라가 이미 실측 fix로 보정됐는지(테스트 관찰용).
  bool get corrected => _corrected;

  /// 위치 fix 도착 시 호출한다.
  /// - [ctrlReady]가 true면(컨트롤러 준비됨) 즉시 적용할 좌표를 반환한다 —
  ///   호출부가 이 반환값으로 `animateCamera`를 실행하고, 이 상태기계는
  ///   "보정됨"으로 전환된다.
  /// - false면(컨트롤러 미준비) "폴백으로 열렸는지"와 무관하게 항상 목표를
  ///   보류하고 null을 반환한다 — 호출부는 아무것도 하지 않는다.
  LatLng? onFixArrived(LatLng loc, {required bool ctrlReady}) {
    if (!ctrlReady) {
      _pending = loc;
      return null;
    }
    _corrected = true;
    return loc;
  }

  /// `onMapCreated`에서 호출한다. 보류된 목표가 있고 아직 카메라가 실측
  /// fix로 보정된 적이 없으면 그 목표를 반환하며(호출부가 적용) 내부
  /// 상태를 "보정됨"으로 전환한다. 이미 보정됐거나 보류값이 없으면 null —
  /// 이 경우 호출부는 아무것도 하지 않는다(사용자가 옮긴 카메라를 잡아채지
  /// 않는다는 불변조건은, 이 클래스가 관리하는 보류값이 컨트롤러 준비 전
  /// (=사용자가 지도를 만질 수조차 없는 시점)에만 생길 수 있다는 사실로
  /// 자동 성립한다).
  LatLng? consumePendingOnMapCreated() {
    if (_corrected) return null;
    final target = _pending;
    if (target == null) return null;
    _pending = null;
    _corrected = true;
    return target;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────

class MainMapScreen extends ConsumerStatefulWidget {
  const MainMapScreen({super.key});

  @override
  ConsumerState<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends ConsumerState<MainMapScreen>
    with SingleTickerProviderStateMixin {
  ml.MapLibreMapController? _mlCtrl; // M1~M4 동안 점진 연결
  bool _styleLoaded = false;

  static const _routeSourceId = 'route-source';
  static const _routeLayerId = 'route-layer';
  static const _routeArrowLayerId = 'route-arrow-layer';
  static const _kRouteArrowIcon = 'route-arrow';
  static const _routeBgSourceId = 'route-bg-source';
  static const _routeBgLayerId = 'route-bg-layer';
  static const _locSourceId = 'loc-source';
  static const _locLayerId = 'loc-layer';
  static const _poiSourceId = 'poi-explore-source';
  static const _poiLayerId = 'poi-explore-layer';
  // 13-1b: 검색 시트와 무관하게 줌 레벨 기준으로 항상 켜져 있는 POI 레이어.
  // 위 검색용 소스/레이어와 완전히 다른 식별자 — 서로 독립적으로 갱신된다.
  static const _ambientPoiSourceId = 'poi-ambient-source';
  static const _ambientPoiLayerId = 'poi-ambient-layer';
  // 즐겨찾기 전용 레이어 — ambient POI 레이어 위에 금색 별 아이콘으로 렌더링된다.
  static const _favPoiSourceId = 'poi-fav-source';
  static const _favPoiLayerId  = 'poi-fav-layer';
  static const _kFavPoiIcon    = 'poi-icon-favorite';

  bool _locLayerReady = false;
  bool _routeArrowLayerReady = false;
  ml.Symbol? _destMarker;
  ml.Symbol? _originMarker;
  List<ml.Symbol> _waypointMarkers = [];
  static const String _kDestIcon = 'pointer_red';
  static const double _kDestIconSize = 1.05; // nav_screen과 동일 배율(96px 핀 기준)
  static const String _kWpIcon = 'pointer_yellow';
  static const double _kWpIconSize = 1.05; // nav_screen과 동일 배율
  static const String _kOriginIcon = 'pointer_start';
  static const double _kOriginIconSize = 1.05; // 다른 핀과 동일 배율
  static const String _kArrowIcon = 'nav_arrow';
  static const double _kArrowIconSize = 1.0; // nav_screen과 동일
  // 검색 결과(상호명/주소 공통) 탭 시 확인시트가 뜨는 동안 위치를 보여주는 임시
  // 초록 점 — 목적지/경유지 드롭릿 핀과 달리 POI 아이콘과 같은 크기의 단순 점.
  ml.Symbol? _searchPreviewMarker;
  static const String _kSearchPreviewIcon = 'search-preview-dot';
  static const double _kSearchPreviewIconSize = 0.4; // POI 아이콘 SymbolLayer와 동일 배율

  double? _lastHeadingDeg; // 정차/저속 시 최근 방향 유지용

  // latlong2.LatLng → maplibre_gl.LatLng 변환 (지도에 넘길 때만 사용)
  ml.LatLng _toMl(LatLng p) => ml.LatLng(p.latitude, p.longitude);

  // Nullable until the device returns a real GPS fix — prevents the origin
  // marker / distance badge from rendering at a hardcoded mock location.
  LatLng? _origin;
  LatLng? _lastKnown; // getLastKnownPosition() 결과 — GPS 스트림보다 먼저 도착
  ProviderSubscription<NavigationState?>? _locationSub;

  // S0: 콜드 스타트 폴백 카메라 레이스 보정 — 상태기계 정의/불변조건은
  // FallbackRecenterState 문서 참조.
  final _fallbackRecenter = FallbackRecenterState();

  // 디버그 전용 E2E 자동화 하네스 — kDebugMode에서만 동작, 세션당 1회만 트리거.
  // 무인 가상 GPS 주행 테스트를 위해 adb intent extra로 목적지를 주입받아
  // "목적지 설정 → 경로 계산 → 내비 시작"까지 자동 실행한다. 릴리스 빌드에서는
  // kDebugMode가 컴파일타임 상수라 이 코드 전체가 tree-shake되어 제거된다.
  bool _e2eHarnessFired = false;
  static const _e2eHarnessChannel =
      MethodChannel('com.westinx.yurunavi/e2e_harness');

  // 마지막으로 페치한 3경로 전체 — 카드 전환 시 maneuvers 참조용
  List<RouteResult> _fetchedRoutes = const [];
  // 선택된 경로의 턴바이턴 maneuvers — NavScreen 으로 전달
  List<ManeuverStep> _selectedManeuvers = const [];
  double _currentZoom = 16.0; // z16 고정 초기 줌

  // 13-1b: 상시 표시 POI (ambient) — 검색 시트를 열지 않아도 줌 레벨에 따라
  // 자동으로 표시/갱신되는 별개 레이어의 로컬 상태.
  List<Poi> _ambientPois = const [];
  // 진행 중인 fetch보다 나중에 시작된 호출이 있으면 이전 응답은 버린다(stale-response 가드).
  int _ambientFetchGen = 0;
  // 뷰포트 사각형+타입 조합 단위로 최근 조회 결과를 재사용해 패닝 왕복 시
  // 불필요한 네트워크 재조회를 막는다. 이 State 인스턴스 전용(전역 아님).
  final _poiRegionCache = PoiRegionCache();
  // ambient POI 재조회 디바운스(15초/200m, nav_screen과 동일 정책) — 반드시
  // shouldFetch가 true인 그 자리에서(await 전에) markStarted를 호출해야 한다.
  // 응답 후에만 커밋하면 응답이 느릴 때 디바운스가 영원히 무장되지 않아 1Hz
  // 재시도가 무한 반복되는 결함이 생긴다(2026-08-05 S2에서 발견한 429 폭주 원인).
  final _ambientThrottle = PoiFetchThrottle(
    minInterval: const Duration(seconds: 15),
    minMoveMeters: 200,
  );
  // 진행 중인 ambient fetch가 있으면 새 호출은 즉시 return — HTTP 요청이 겹쳐
  // 쌓이는 걸 막는다.
  bool _ambientFetchInFlight = false;

  // 6번: 검색 시트("장소 검색") 전용 백그라운드 프리페치 — ambient 레이어(위)와는
  // 완전히 별개. GPS 위치 갱신 시마다 5종 전체를 미리 받아 캐시해 둬서, 시트를
  // 열었을 때 네트워크 대기 없이 바로 칩 필터링이 가능하게 한다.
  List<Poi> _searchPrefetchPois = const [];
  LatLng? _searchPrefetchCenter;
  int _searchPrefetchGen = 0;
  // search prefetch 디바운스(60초/500m) — ambient와 동일한 이유로 선커밋 필수.
  final _searchPrefetchThrottle = PoiFetchThrottle(
    minInterval: const Duration(seconds: 60),
    minMoveMeters: 500,
  );
  bool _searchPrefetchInFlight = false;

  // Course sheet
  bool _showCourseSheet = false;

  String? _rawStyle;   // 원본 JSON 1회 로드
  String? _styleJson;  // 언어 적용 후 주입 문자열
  // O1 청크3: 지도 한글 폰트 — MapView 생성 시점에만 적용되고 런타임 변경이
  // 안 되므로(maplibre_gl 포크 제약), 스타일 로드 시 한 번만 읽어 고정한다.
  // Android 전용, iOS는 항상 null(플러그인이 해당 키를 읽지 않음).
  String? _ideographFontFamily;

  // Touch overlay
  LatLng? _touchPoint;
  // ignore: unused_field
  double _touchDistKm = 0;

  // Slide-up animation for course sheet
  late final AnimationController _sheetCtrl;
  late final Animation<Offset> _sheetSlide;

  @override
  void initState() {
    super.initState();
    // S0: 스플래시 화면이 앱 진입 전에 선확보해 둔 위치가 있으면 즉시
    // _lastKnown을 시드한다 — initialCameraPosition(아래 build())이 첫
    // 빌드부터 실제 위치를 잡게 되고, _origin ?? _lastKnown 패턴을 쓰는 기존
    // 소비처 전부가 자동으로 혜택을 본다. 실측/최근 위치가 아니면 절대
    // 세팅하지 않는다(bootLocationProvider 자체가 그 불변조건을 보장).
    final boot = ref.read(bootLocationProvider);
    if (boot != null) _lastKnown = boot;
    // 이 시점에 _origin은 항상 null(GPS 스트림 시작 전)이므로, _lastKnown이
    // 비어 있다면 build()의 initialCameraPosition은 kInitialMapView로 열린다.
    // 진단 로그일 뿐 이후 로직을 게이트하지 않는다 — FallbackRecenterState는
    // 이 사실과 무관하게 컨트롤러 준비 여부만으로 동작한다(2026-08-05 감사
    // 지적, 위 클래스 문서 참조).
    if (kDebugMode && _lastKnown == null) {
      dev.log('S0: opened at kInitialMapView fallback (no boot-seeded location)',
          name: 'S0');
    }
    _sheetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _sheetSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOutCubic));
    _startLocationTracking();
    _loadRawStyle();
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
    _locationSub?.close();
    _sheetCtrl.dispose();
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _startLocationTracking() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    // 캐시된 마지막 위치를 즉시 표시 — GPS 콜드스타트 대기 없이 지도 이동
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted && _origin == null) {
        final loc = LatLng(last.latitude, last.longitude);
        setState(() => _lastKnown = loc);
        _moveCameraToFix(loc);
        _ensureLocationMarker(); // unawaited — B1
        unawaited(_maybeFetchSearchPrefetch(loc));
        unawaited(_maybeRunE2EHarness());
      }
    } catch (_) {} // 권한 미취득 등 — 무시하고 스트림으로 진행

    _locationSub = ref.listenManual<NavigationState?>(
      navStateProvider,
      (_, next) {
        if (next == null || !mounted) return;
        final loc = next.pos;
        final isFirstFix = _origin == null;
        setState(() => _origin = loc);
        if (isFirstFix) {
          _moveCameraToFix(loc);
        }
        final heading = _resolveHeading(next.speedKmh, next.headingDeg);
        _ensureLocationMarker(heading); // unawaited — B1
        unawaited(_maybeFetchSearchPrefetch(loc));
        unawaited(_maybeRunE2EHarness());
      },
      fireImmediately: true,
    );
  }

  /// 첫 실측(또는 캐시된) fix 도착 시 카메라를 이동시킨다. 레이스 보정 로직
  /// 자체는 `_fallbackRecenter`(`FallbackRecenterState`)에 위임 — 그 클래스의
  /// 문서에 불변조건이 정리돼 있다.
  void _moveCameraToFix(LatLng loc) {
    final ctrl = _mlCtrl;
    final target =
        _fallbackRecenter.onFixArrived(loc, ctrlReady: ctrl != null);
    if (target == null) return; // 보류됨 — onMapCreated가 나중에 적용
    ctrl!.animateCamera(
      ml.CameraUpdate.newLatLngZoom(_toMl(target), _currentZoom.clamp(10.0, 14.0)),
    );
  }

  // ── E2E 테스트 하네스 (디버그 전용) ──────────────────────────────────────────

  /// GPS 위치(원점)가 처음 확보된 시점에 호출. adb intent extra로 목적지가
  /// 넘어와 있으면 "목적지 설정 → 경로 계산 대기 → 내비 시작"을 자동 실행한다.
  /// kDebugMode가 아니거나 이미 이번 세션에 실행했으면 즉시 반환.
  Future<void> _maybeRunE2EHarness() async {
    if (!kDebugMode) return;
    if (_e2eHarnessFired) return;
    _e2eHarnessFired = true; // 재진입/중복 트리거 방지 — await 전에 즉시 세팅

    Map<Object?, Object?>? dest;
    try {
      dest = await _e2eHarnessChannel.invokeMapMethod<Object?, Object?>(
        'getE2EDestination',
      );
    } catch (e) {
      dev.log('E2E_HARNESS channel error: $e', name: 'E2EHarness');
      return;
    }
    if (dest == null) return;
    final lat = (dest['lat'] as num?)?.toDouble();
    final lon = (dest['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return;
    final courseIdx = (dest['courseIdx'] as num?)?.toInt();
    final noAutostart = ((dest['noAutostart'] as num?)?.toDouble() ?? 0.0) >= 1.0;

    dev.log('E2E_HARNESS dest=$lat,$lon courseIdx=$courseIdx start',
        name: 'E2EHarness');
    await _applyDestination(LatLng(lat, lon));

    final gotRoutes = await _e2eWaitForRoutes();
    if (!mounted) return;
    if (!gotRoutes) {
      dev.log('E2E_HARNESS timeout waiting for routes', name: 'E2EHarness');
      return;
    }
    if (courseIdx != null) {
      ref.read(mapInteractionProvider.notifier).setSelectedRouteIdx(courseIdx);
    }
    if (noAutostart) {
      dev.log('E2E_HARNESS routes ready, autostart 생략(비교 시트 유지)',
          name: 'E2EHarness');
      return;
    }
    _startNavigation();
    dev.log('E2E_HARNESS navigation started', name: 'E2EHarness');
  }

  /// _fetchAndStoreAllRoutes()가 비동기로 채우는 _fetchedRoutes를 폴링 대기.
  /// 라우팅 서비스 자체 타임아웃(20s)과 동일하게 맞춰 그보다 오래 걸리지 않게 한다.
  Future<bool> _e2eWaitForRoutes() async {
    const timeout = Duration(seconds: 20);
    const pollInterval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return false;
      if (_fetchedRoutes.isNotEmpty) return true;
      await Future<void>.delayed(pollInterval);
    }
    return _fetchedRoutes.isNotEmpty;
  }

  /// 정차/저속(3km/h 미만) 시 마지막 방향을 유지 — nav_screen._resolveHeading과 동일 로직.
  double? _resolveHeading(double speedKmh, double? headingDeg) {
    if (speedKmh >= 3 && headingDeg != null) _lastHeadingDeg = headingDeg;
    return (speedKmh >= 3 ? headingDeg : null) ?? _lastHeadingDeg;
  }

  void _recenterMap() {
    final o = _origin;
    if (o == null) return;
    _mlCtrl?.animateCamera(
      ml.CameraUpdate.newLatLngZoom(_toMl(o), _currentZoom.clamp(10.0, 14.0)),
    );
  }

  // ── Route polyline (M2) ───────────────────────────────────────────────────

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

  Future<void> _initRouteLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null) return;
    // bg layer (below selected route)
    await ctrl.addGeoJsonSource(_routeBgSourceId, _buildBgGeoJson([]));
    await ctrl.addLineLayer(
      _routeBgSourceId,
      _routeBgLayerId,
      const ml.LineLayerProperties(
        lineColor: '#9E9E9E',
        lineWidth: 4.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: 'waterway-name',
    );
    // selected route layer (above bg)
    await ctrl.addGeoJsonSource(_routeSourceId, _buildRouteGeoJson([]));
    final initialIdx = ref.read(mapInteractionProvider).selectedRouteIdx;
    final courseLineColor = ref.read(skinProvider).colors.courseLineColor;
    await ctrl.addLineLayer(
      _routeSourceId,
      _routeLayerId,
      ml.LineLayerProperties(
        lineColor: colorToHex(courseLineColor[initialIdx] ?? courseLineColor[2]!),
        lineWidth: 6.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: 'waterway-name',
    );
  }

  Future<void> _recolorRouteLayer(int idx) async {
    final ctrl = _mlCtrl;
    if (ctrl == null || !_styleLoaded) return;
    final courseLineColor = ref.read(skinProvider).colors.courseLineColor;
    if (_routeArrowLayerReady) await ctrl.removeLayer(_routeArrowLayerId);
    await ctrl.removeLayer(_routeLayerId);
    await ctrl.addLineLayer(
      _routeSourceId,
      _routeLayerId,
      ml.LineLayerProperties(
        lineColor: colorToHex(courseLineColor[idx] ?? courseLineColor[2]!),
        lineWidth: 6.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: 'waterway-name',
    );
    if (_routeArrowLayerReady) {
      await ctrl.addSymbolLayer(
        _routeSourceId,
        _routeArrowLayerId,
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

  Future<void> _initRouteArrowLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null) return;
    await ctrl.addSymbolLayer(
      _routeSourceId,
      _routeArrowLayerId,
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
    _routeArrowLayerReady = true;
  }

  // ── Marker helpers (B1/B2) ────────────────────────────────────────────────

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
              'bearing': bearing ?? 0,
            },
          }
        ],
      };

  /// nav_screen과 동일하게 raw GeoJSON + addSymbolLayer로 회전 가능한 화살표
  /// puck을 그린다 (addSymbol/SymbolManager는 iconRotationAlignment을 노출하지
  /// 않아 헤딩 회전이 카메라 bearing과 어긋난다).
  Future<void> _initLocationLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null || _locLayerReady) return;
    final p = _origin ?? _lastKnown ?? kInitialMapView;
    await ctrl.addGeoJsonSource(_locSourceId, _buildLocGeoJson(p));
    await ctrl.addSymbolLayer(
      _locSourceId,
      _locLayerId,
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

  // ── POI 탐색 레이어 (13-1) ────────────────────────────────────────────────

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
    await ctrl.addGeoJsonSource(_poiSourceId, _buildPoiGeoJson(const []));
    await ctrl.addSymbolLayer(
      _poiSourceId,
      _poiLayerId,
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
    if (!_styleLoaded) return;
    _mlCtrl?.setGeoJsonSource(_poiSourceId, _buildPoiGeoJson(pois));
  }

  // ── POI 상시 표시(ambient) 레이어 (13-1b) ──────────────────────────────────
  // _PoiExploreSheet용 위 레이어와는 완전히 별개 — 검색 시트를 열지 않아도
  // 줌 레벨 임계값(Poi.minZoomLevel)에 따라 자동으로 표시된다.

  Future<void> _initAmbientPoiLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null) return;
    await ctrl.addGeoJsonSource(_ambientPoiSourceId, _buildPoiGeoJson(const []));
    await ctrl.addSymbolLayer(
      _ambientPoiSourceId,
      _ambientPoiLayerId,
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

  void _updateAmbientPoiLayer(List<Poi> pois) {
    if (!_styleLoaded) return;
    _mlCtrl?.setGeoJsonSource(_ambientPoiSourceId, _buildPoiGeoJson(pois));
  }

  // ── 즐겨찾기 POI 레이어 ────────────────────────────────────────────────────

  Map<String, dynamic> _buildFavPoiGeoJson(List<FavoritePlace> favs) => {
    'type': 'FeatureCollection',
    'features': favs
        .map((f) => {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [f.lng, f.lat],
              },
              'properties': <String, dynamic>{
                'poiIcon': _kFavPoiIcon,
                'name': f.name,
              },
            })
        .toList(),
  };

  Future<void> _initFavPoiLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null) return;
    await ctrl.addGeoJsonSource(_favPoiSourceId, _buildFavPoiGeoJson(const []));
    await ctrl.addSymbolLayer(
      _favPoiSourceId,
      _favPoiLayerId,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'poiIcon'],
        iconSize: 0.52,
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
        textOptional: true,
      ),
    );
  }

  void _updateFavPoiLayer(List<FavoritePlace> favs) {
    if (!_styleLoaded) return;
    _mlCtrl?.setGeoJsonSource(_favPoiSourceId, _buildFavPoiGeoJson(favs));
  }

  /// 현재 줌 레벨에서 노출 대상인 카테고리를 계산하고, onCameraIdle마다(제스처가
  /// 멈출 때 1회) 뷰포트 중심 기준으로 POI를 재조회해 ambient 레이어를 갱신한다.
  /// 화면에 실제 보이는 것만, 카테고리 우선순위(주유소>편의점>카페>대형마트>식당)와
  /// 화면 분포를 함께 고려해 최대 20개로 제한한다.
  ///
  /// 디바운스(15초/200m, `_ambientThrottle`)와 in-flight 가드(`_ambientFetchInFlight`)
  /// 둘 다 네트워크 await 전에 판단·커밋한다 — 응답이 느릴 때 디바운스가
  /// 영원히 무장되지 않아 1Hz 재시도가 무한 반복되던 결함(2026-08-05 S2)의
  /// 재발 방지가 핵심이다.
  Future<void> _maybeFetchAmbientPois() async {
    final ctrl = _mlCtrl;
    if (ctrl == null || !_styleLoaded) return;
    if (_ambientFetchInFlight) return; // 진행 중인 fetch가 있으면 즉시 포기

    final targetTypes = PoiService.serverSupportedTypes
        .where((t) => _currentZoom >= t.minZoomLevel)
        .toSet();
    if (targetTypes.isEmpty) {
      _ambientFetchGen++; // 진행 중이던 fetch가 있으면 응답을 무효화
      if (_ambientPois.isNotEmpty) {
        _ambientPois = const [];
        _updateAmbientPoiLayer(const []);
      }
      _ambientThrottle.clearTypes();
      return;
    }

    // trackCameraPosition: true라 플랫폼 채널 호출 없이 즉시 읽을 수 있는
    // 저비용 근사 중심점 — 디바운스 판단(및 그 자리에서의 즉시 커밋)에만 쓰고,
    // 실제 조회 bounds는 아래에서 getVisibleRegion()으로 정확히 다시 구한다.
    final camTarget = ctrl.cameraPosition?.target;
    if (camTarget == null) return;
    final approxCenter = LatLng(camTarget.latitude, camTarget.longitude);

    if (!_ambientThrottle.shouldFetch(center: approxCenter, types: targetTypes)) {
      return;
    }
    // 선커밋 — 아래 두 await(getVisibleRegion, fetchPoisInBounds) 이전에 즉시
    // 확정한다. await 이후(성공 경로)에서만 커밋하면 응답이 느릴 때 디바운스가
    // 영원히 무장되지 않는다(2026-08-05 S2 조사에서 발견한 429 폭주의 진짜 원인).
    _ambientThrottle.markStarted(center: approxCenter, types: targetTypes);

    _ambientFetchInFlight = true;
    try {
      // 이 호출 시작 시점의 세대를 기록 — 아래 두 await(getVisibleRegion,
      // fetchPois) 도중 더 최신 호출이 시작되면(_ambientFetchGen이 바뀌면)
      // 이 응답은 stale이니 버린다.
      final myGen = ++_ambientFetchGen;

      final ml.LatLngBounds bounds;
      try {
        bounds = await ctrl.getVisibleRegion();
      } catch (_) {
        return;
      }
      if (!mounted || myGen != _ambientFetchGen) return;
      final center = LatLng(
        (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
        (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
      );
      final south = bounds.southwest.latitude;
      final north = bounds.northeast.latitude;
      final west = bounds.southwest.longitude;
      final east = bounds.northeast.longitude;

      // 캐시 적중률을 위해 네트워크 요청·캐시 put/get 모두 바깥쪽으로 스냅한
      // bbox를 쓴다 — 표시(selectForAmbientDisplay)는 실제 뷰포트를 써야
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
                tag: 'ambient-home',
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
          // _ambientPois를 유지한 채 조용히 종료(화면에서 POI가 사라지지
          // 않게 한다).
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
      _updateAmbientPoiLayer(limited);
    } finally {
      _ambientFetchInFlight = false;
    }
  }

  /// GPS 위치가 갱신될 때마다(캐시된 마지막 위치 포함) 호출 — 검색 시트(_PoiExploreSheet)용
  /// 5종 카테고리 전체를 1500m 반경으로 미리 받아둔다. 500m 이동 또는 60초 경과 전엔
  /// 재조회하지 않는다 — ambient 레이어보다 완화된 디바운스(반경이 넓어 약간의 위치 오차가
  /// 결과에 큰 영향을 주지 않고, 검색은 ambient만큼 실시간성이 필요하지 않음).
  Future<void> _maybeFetchSearchPrefetch(LatLng center) async {
    if (_searchPrefetchInFlight) return; // 진행 중인 fetch가 있으면 즉시 포기

    if (!_searchPrefetchThrottle.shouldFetch(center: center)) return;
    // 선커밋 — fetchPois await 이전에 즉시 확정(§2-2와 동일한 이유).
    _searchPrefetchThrottle.markStarted(center: center);

    _searchPrefetchInFlight = true;
    try {
      final myGen = ++_searchPrefetchGen;
      final List<Poi> pois;
      try {
        pois = await ref.read(poiServiceProvider).fetchPois(
              center: center,
              radiusMeters: 1500,
              types: PoiService.serverSupportedTypes,
              tag: 'search-prefetch',
            );
      } on PoiFetchException {
        // 실패 — 기존 프리페치 캐시(_searchPrefetchPois/Center)를 유지한 채
        // 조용히 종료한다.
        return;
      }
      if (!mounted || myGen != _searchPrefetchGen) return;

      _searchPrefetchPois = pois;
      _searchPrefetchCenter = center;
    } finally {
      _searchPrefetchInFlight = false;
    }
  }

  Future<void> _ensureLocationMarker([double? heading]) async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded || !_locLayerReady) return;
    final p = _origin ?? _lastKnown;
    if (p == null) return;
    await c.setGeoJsonSource(_locSourceId, _buildLocGeoJson(p, heading));
  }

  Future<void> _ensureDestMarker(LatLng dest, {String? name}) async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded) return;
    final geo = _toMl(dest);
    final options = ml.SymbolOptions(
      geometry: geo,
      iconImage: _kDestIcon,
      iconSize: _kDestIconSize,
      iconAnchor: 'bottom',
      zIndex: 10,
      // updateSymbol은 null 필드를 "변경 없음"으로 처리해 이전 라벨이 남을 수 있으므로
      // 이름이 없을 땐 빈 문자열을 명시적으로 보내 이전 값을 확실히 지운다.
      textField: name ?? '',
      textSize: 12,
      textOffset: const Offset(0, 1.4),
      textAnchor: 'top',
      textColor: '#212121',
      textHaloColor: '#FFFFFF',
      textHaloWidth: 1.2,
    );
    if (_destMarker == null) {
      _destMarker = await c.addSymbol(options);
    } else {
      await c.updateSymbol(_destMarker!, options);
    }
  }

  Future<void> _removeDestMarker() async {
    final c = _mlCtrl;
    if (c != null && _destMarker != null) {
      await c.removeSymbol(_destMarker!);
    }
    _destMarker = null;
  }

  Future<void> _ensureOriginMarker(LatLng origin, {String? name}) async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded) return;
    final geo = _toMl(origin);
    final options = ml.SymbolOptions(
      geometry: geo,
      iconImage: _kOriginIcon,
      iconSize: _kOriginIconSize,
      iconAnchor: 'bottom',
      zIndex: 4,
      // updateSymbol은 null 필드를 "변경 없음"으로 처리해 이전 라벨이 남을 수 있으므로
      // 이름이 없을 땐 빈 문자열을 명시적으로 보내 이전 값을 확실히 지운다.
      textField: name ?? '',
      textSize: 12,
      textOffset: const Offset(0, 1.4),
      textAnchor: 'top',
      textColor: '#212121',
      textHaloColor: '#FFFFFF',
      textHaloWidth: 1.2,
    );
    if (_originMarker == null) {
      _originMarker = await c.addSymbol(options);
    } else {
      await c.updateSymbol(_originMarker!, options);
    }
  }

  Future<void> _removeOriginMarker() async {
    final c = _mlCtrl;
    if (c != null && _originMarker != null) {
      await c.removeSymbol(_originMarker!);
    }
    _originMarker = null;
  }

  /// 검색 결과(상호명/주소) 탭 시 확인시트가 뜨는 동안만 보이는 임시 초록 점.
  /// `_ensureDestMarker`와 달리 텍스트 라벨이 없고, 핀처럼 좌표를 "가리키지"
  /// 않으므로 `iconAnchor: 'center'`로 좌표에 정중앙 배치한다.
  Future<void> _ensureSearchPreviewMarker(LatLng loc) async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded) return;
    final options = ml.SymbolOptions(
      geometry: _toMl(loc),
      iconImage: _kSearchPreviewIcon,
      iconSize: _kSearchPreviewIconSize,
      iconAnchor: 'center',
      zIndex: 6, // 경유지(5) 위, 목적지(10) 아래
    );
    if (_searchPreviewMarker == null) {
      _searchPreviewMarker = await c.addSymbol(options);
    } else {
      await c.updateSymbol(_searchPreviewMarker!, options);
    }
  }

  Future<void> _removeSearchPreviewMarker() async {
    final c = _mlCtrl;
    if (c != null && _searchPreviewMarker != null) {
      await c.removeSymbol(_searchPreviewMarker!);
    }
    _searchPreviewMarker = null;
  }

  Future<void> _syncWaypointMarkers(
      List<LatLng> waypoints, List<String?> names) async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded) return;
    for (final s in _waypointMarkers) {
      await c.removeSymbol(s);
    }
    _waypointMarkers = [];
    for (var i = 0; i < waypoints.length; i++) {
      final s = await c.addSymbol(ml.SymbolOptions(
        geometry: _toMl(waypoints[i]),
        iconImage: _kWpIcon,
        iconSize: _kWpIconSize,
        iconAnchor: 'bottom',
        zIndex: 5,
        textField: '${i + 1}',
        textSize: 11,
        textColor: '#FFFFFF',
        textOffset: const Offset(0, -2.1),
        textAnchor: 'bottom',
      ));
      _waypointMarkers.add(s);
    }
  }

  void _updateRouteLayer(List<LatLng> points) {
    if (!_styleLoaded) return;
    // selected route
    _mlCtrl?.setGeoJsonSource(_routeSourceId, _buildRouteGeoJson(points));
    // non-selected routes in grey
    final state = ref.read(mapInteractionProvider);
    final allRoutes = state.allRoutes;
    final selIdx = state.selectedRouteIdx;
    if (allRoutes.length > 1) {
      final bgRoutes = [
        for (int i = 0; i < allRoutes.length; i++)
          if (i != selIdx) allRoutes[i],
      ];
      _mlCtrl?.setGeoJsonSource(_routeBgSourceId, _buildBgGeoJson(bgRoutes));
    } else {
      _mlCtrl?.setGeoJsonSource(_routeBgSourceId, _buildBgGeoJson([]));
    }
    if (points.isEmpty) return;
    final minLat = points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLng = points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    final bottomPadding = _showCourseSheet ? 360.0 : 80.0;
    _mlCtrl?.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: ml.LatLng(minLat, minLng),
          northeast: ml.LatLng(maxLat, maxLng),
        ),
        left: 50,
        top: 110,
        right: 80,
        bottom: bottomPadding,
      ),
    );
  }

  // ── Haversine ─────────────────────────────────────────────────────────────

  double _haversineKm(LatLng a, LatLng b) {
    const r = 0.017453292519943295;
    final dLat = (b.latitude - a.latitude) * r;
    final dLon = (b.longitude - a.longitude) * r;
    final h = (dLat / 2) * (dLat / 2) +
        cos(a.latitude * r) *
            cos(b.latitude * r) *
            ((dLon / 2) * (dLon / 2));
    return 12742 * asin(sqrt(h));
  }

  // ── POI name resolution helpers ───────────────────────────────────────────

  Future<double> _screenDistFromTap(
    Point<num> tapScreen,
    dynamic geom,
    ml.MapLibreMapController c,
  ) async {
    final type = (geom as Map)['type'] as String;
    final rawCoords = geom['coordinates'] as List;
    final List coordPair;
    if (type == 'Point') {
      coordPair = rawCoords;
    } else if (type == 'LineString') {
      coordPair = rawCoords.first as List;
    } else {
      coordPair = (rawCoords.first as List).first as List;
    }
    final lng = (coordPair[0] as num).toDouble();
    final lat = (coordPair[1] as num).toDouble();
    final screenPt = await c.toScreenLocation(ml.LatLng(lat, lng));
    final dx = screenPt.x.toDouble() - tapScreen.x.toDouble();
    final dy = screenPt.y.toDouble() - tapScreen.y.toDouble();
    return sqrt(dx * dx + dy * dy);
  }

  Future<_TappedPoi?> _resolveTappedPoi(LatLng tap) async {
    final c = _mlCtrl;
    if (c == null) return null;
    final center = await c.toScreenLocation(_toMl(tap));
    const r = 24.0;
    final rect = Rect.fromCenter(
      center: Offset(center.x.toDouble(), center.y.toDouble()),
      width: r * 2,
      height: r * 2,
    );
    const ids = [
      'poi-level-1', 'poi-level-2', 'poi-level-3', 'poi-railway',
      'place-city', 'place-town', 'place-village', 'place-other',
    ];
    final picks = <PickFeature>[];
    for (final id in ids) {
      final fs = await c.queryRenderedFeaturesInRect(rect, [id], null);
      for (final f in fs) {
        try {
          final m = f as Map;
          final props = (m['properties'] as Map).cast<String, dynamic>();
          final g = m['geometry'];
          final sd = await _screenDistFromTap(center, g, c);
          picks.add(PickFeature(layerId: id, screenDist: sd, props: props));
        } catch (_) {
          continue;
        }
      }
    }
    final best = PoiFeaturePicker.pick(picks);
    if (best == null) return null;
    final lang = ref.read(mapLanguageProvider).value ?? MapLanguage.korean;
    final name = PoiNameResolver(lang).resolve(best.props);
    final cat = poiCategoryKo(best.props);
    return _TappedPoi(name: name, category: cat);
  }

  /// POI 없는 지점을 탭했을 때 좌표 대신 보여줄 이름 — 역지오코딩으로 동 단위
  /// 행정구역 이름을 가져온다. 실패(오프라인/지오코더 없음)하면 좌표로 폴백.
  Future<String> _resolveFallbackName(LatLng tapped) async {
    final address = await GeocodingService()
        .reverseGeocode(tapped.latitude, tapped.longitude);
    return address ??
        '${tapped.latitude.toStringAsFixed(5)}, ${tapped.longitude.toStringAsFixed(5)}';
  }

  // ── Map tap ───────────────────────────────────────────────────────────────

Future<void> _onMapTap(LatLng tapped) async {
    final origin = _origin ?? _lastKnown;
    if (origin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS 위치를 기다리는 중입니다…'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final interaction = ref.read(mapInteractionProvider);
    if (interaction.isLoading) return;

    final poi = await _resolveTappedPoi(tapped);
    if (!mounted) return;

    // 코스 시트가 열려 있으면(=경로가 이미 표시 중) 지도 탭도 검색결과 탭과
    // 동일한 4번 카드(_AddToRouteSheet)로 통일 — POI 없으면 역지오코딩한 행정구역
    // 이름(동 단위)을 보여준다. 실패 시에만 좌표로 최종 폴백.
    if (_showCourseSheet) {
      final name = poi?.name ?? await _resolveFallbackName(tapped);
      if (!mounted) return;
      final act = await _showAddToRouteSheet(
        location: tapped,
        name: name,
        hasDest: true,
      );
      if (!mounted || act == null) return;
      await _applyRouteAddAction(act, tapped, name, origin);
      return;
    }

    final act = await _showTapConfirmSheet(tapped, poi);
    if (!mounted) return;
    await _applyTapAction(act, tapped, origin, preResolvedName: poi?.name);
  }

  /// `_onMapTap`/`_handlePoiTap`가 확인시트에서 선택한 `_TapAction`을 실제로
  /// 적용하는 공통 꼬리부분 — 목적지 설정 또는 경유지 추가.
  Future<void> _applyTapAction(
    _TapAction? act,
    LatLng loc,
    LatLng origin, {
    String? preResolvedName,
  }) async {
    if (act == _TapAction.origin) {
      final name = preResolvedName ?? await _resolveFallbackName(loc);
      if (!mounted) return;
      ref.read(mapInteractionProvider.notifier).setOrigin(loc, name: name);
      await _ensureOriginMarker(loc, name: name);
      if (!mounted) return;
      final dest = ref.read(mapInteractionProvider).destination;
      if (dest != null) {
        ref.read(mapInteractionProvider.notifier).setLoading(true);
        try {
          await _fetchAndStoreAllRoutes(loc, dest);
        } finally {
          if (mounted) ref.read(mapInteractionProvider.notifier).setLoading(false);
        }
      }
      return;
    }
    if (act != _TapAction.destination) return;

    setState(() {
      _touchPoint = loc;
      _touchDistKm = _haversineKm(origin, loc);
    });
    await _applyDestination(loc, preResolved: preResolvedName);
  }

  /// ambient/검색 POI 점 탭 또는 검색시트 리스트 탭 공통 처리 — 기존 지도 빈 곳 탭과
  /// 동일한 확인시트(_showTapConfirmSheet)를 재사용해 "탭하면 바로 목적지로 잡힘" 문제를
  /// 없앤다. 이미 Poi 객체로 이름/카테고리를 알고 있으므로 _resolveTappedPoi(리버스
  /// 조회)는 생략.
  Future<void> _handlePoiTap(Poi poi) async {
    await _handleLocationTap(
      location: poi.location,
      name: poi.name,
      category: poi.type.label,
    );
  }

  /// 검색시트(상호명/주소 검색 공통)에서 목적지 후보를 탭했을 때의 공통 처리 — GPS
  /// 가드 → "어디로 추가할까요?" 시트(_AddToRouteSheet) → 선택 액션 적용.
  /// `_handlePoiTap`(상호명 검색 결과)과 `_handleAddressTap`(주소 검색 결과)이 이
  /// 헬퍼를 공유한다.
  Future<void> _handleLocationTap({
    required LatLng location,
    required String name,
    required String category,
  }) async {
    final origin = _origin ?? _lastKnown;
    if (origin == null) {
      // ambient POI 레이어는 GPS 확보 전(_maybeFetchAmbientPois가 카메라 뷰포트만으로도
      // 동작)에도 뜰 수 있어 _onMapTap과 달리 이 가드가 실제로 도달 가능함 — 조용히
      // 무시하지 않고 동일한 안내를 보여준다.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS 위치를 기다리는 중입니다…'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final interaction = ref.read(mapInteractionProvider);
    if (interaction.isLoading) return;

    // 검색 결과(상호명/주소 공통)를 탭한 시점에 목적지 확정 전이라도 그 위치를
    // 바로 보여준다 — 예전엔 확인 후에야 카메라가 움직여, 시트를 닫기 전엔 어딘지
    // 화면에서 전혀 알 수 없었다(2026-07-18 사용자 피드백). fire-and-forget — 시트는
    // 카메라 애니메이션 완료를 기다리지 않고 바로 뜬다.
    _mlCtrl?.animateCamera(
      ml.CameraUpdate.newLatLngZoom(_toMl(location), 16.0),
    );
    // 시트가 떠 있는 동안 정확히 어디를 검색했는지 보여주는 임시 초록 점 —
    // await해서 시트가 뜨기 전에 실제로 존재하게 한다.
    await _ensureSearchPreviewMarker(location);

    final hasDest = ref.read(mapInteractionProvider).destination != null;
    final act = await _showAddToRouteSheet(
      location: location,
      name: name,
      hasDest: hasDest,
    );
    if (!mounted) return;
    // 시트 결과와 무관하게 임시 점은 무조건 지운다 — 실제 결과(빨간 목적지 핀/
    // 노란 경유지 핀 또는 아무것도 없음)가 반영되기 직전에 지워야 마커가 겹쳐
    // 보이는 순간이 없다.
    await _removeSearchPreviewMarker();

    if (act == null) return;
    await _applyRouteAddAction(act, location, name, origin);
  }

  /// `_handleLocationTap`(검색결과 탭)과 `_onMapTap`(코스 시트 열린 상태의 지도 탭)이
  /// 공유하는 `_AddToRouteSheet` 결과(`_RouteAddAction`) 적용 로직.
  Future<void> _applyRouteAddAction(
    _RouteAddAction act,
    LatLng location,
    String name,
    LatLng origin,
  ) async {
    switch (act) {
      case _RouteAddAction.origin:
        ref.read(mapInteractionProvider.notifier).setOrigin(location, name: name);
        await _ensureOriginMarker(location, name: name);
      case _RouteAddAction.waypoint:
        final pending = ref.read(mapInteractionProvider).pendingWaypointInsert;
        ref.read(mapInteractionProvider.notifier).addWaypoint(
              location,
              name: name,
              atStart: pending == WaypointInsertPosition.start,
            );
        final dest = ref.read(mapInteractionProvider).destination;
        if (dest != null) {
          ref.read(mapInteractionProvider.notifier).setLoading(true);
          try {
            await _fetchAndStoreAllRoutes(origin, dest);
          } finally {
            if (mounted) {
              ref.read(mapInteractionProvider.notifier).setLoading(false);
            }
          }
        }
        ref.read(mapInteractionProvider.notifier).setPendingWaypointInsert(null);
        // 경유지 관리 카드의 `+` 버튼으로 진입한 경우에만 카드를 다시 연다
        // (일반 검색결과/지도탭 경유지 추가는 이 자동 재오픈 대상이 아님).
        if (pending != null && mounted) _showWaypointSheet(context);
      case _RouteAddAction.destination:
        await _applyDestination(location, preResolved: name);
    }
  }

  /// 주소 검색 결과 탭 → `_handleLocationTap` 공통 파이프라인 진입. `category`는
  /// 확인시트 표시용 라벨일 뿐 실제 분류 로직(PoiType)과는 무관.
  Future<void> _handleAddressTap(AddressResult r) => _handleLocationTap(
        location: r.location,
        name: r.address,
        category: '주소',
      );

  Future<_TapAction?> _showTapConfirmSheet(LatLng tapped, _TappedPoi? poi) {
    final title = poi?.name ?? '선택 위치';
    final subtitle = poi?.category ??
        '${tapped.latitude.toStringAsFixed(5)}, ${tapped.longitude.toStringAsFixed(5)}';
    return showModalBottomSheet<_TapAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      _FavoriteStarButton(
                        lat: tapped.latitude,
                        lng: tapped.longitude,
                        initialName: poi?.name ?? '',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                    child: const Icon(Icons.trip_origin, color: Colors.white, size: 14),
                  ),
                  title: const Text('출발지로 설정'),
                  onTap: () => Navigator.pop(context, _TapAction.origin),
                ),
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: AppColors.primary),
                  title: const Text('여기로 안내'),
                  onTap: () => Navigator.pop(context, _TapAction.destination),
                ),
                ListTile(
                  leading: const Icon(Icons.close, color: Colors.grey),
                  title: const Text('닫기'),
                  onTap: () => Navigator.pop(context, null),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 검색 결과 탭 시 "어디로 추가할까요?" 시트를 표시한다.
  /// 반환값: 사용자 선택(_RouteAddAction) 또는 null(닫기/취소).
  Future<_RouteAddAction?> _showAddToRouteSheet({
    required LatLng location,
    required String name,
    required bool hasDest,
  }) {
    return showModalBottomSheet<_RouteAddAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddToRouteSheet(
        name: name,
        hasDest: hasDest,
        lat: location.latitude,
        lng: location.longitude,
      ),
    );
  }

  Future<void> _applyDestination(LatLng dest, {String? preResolved}) async {
    final origin = _origin ?? _lastKnown;
    if (origin == null) return;
    final dist = _haversineKm(origin, dest);
    ref.read(mapInteractionProvider.notifier).setDestination(dest, dist, snapshotOrigin: origin);

    final sw = LatLng(
      origin.latitude < dest.latitude ? origin.latitude : dest.latitude,
      origin.longitude < dest.longitude
          ? origin.longitude
          : dest.longitude,
    );
    final ne = LatLng(
      origin.latitude > dest.latitude ? origin.latitude : dest.latitude,
      origin.longitude > dest.longitude
          ? origin.longitude
          : dest.longitude,
    );
    _mlCtrl?.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: _toMl(sw),
          northeast: _toMl(ne),
        ),
        left: 50,
        top: 110,
        right: 80,
        bottom: 260,
      ),
    );

    setState(() {
      _showCourseSheet = true;
      _touchPoint = null;
    });
    _sheetCtrl.forward();

    // await 필요 — preResolved가 이미 있으면 아래 setDestinationName이 곧바로 리스너를
    // 동기 트리거하는데, _destMarker 대입 전에 그 리스너가 또 addSymbol을 부르면 마커가
    // 두 개 생성되고 하나는 참조를 잃어 영원히 남는 경쟁상태가 생긴다.
    await _ensureDestMarker(dest, name: preResolved);

    // Valhalla 3회 병렬 호출 (시골길·지방도로·국도) → 3카드 동시 표시
    _fetchAndStoreAllRoutes(origin, dest);

    if (preResolved != null) {
      ref.read(mapInteractionProvider.notifier).setDestinationName(preResolved);
    } else {
      final resolved = await _resolveTappedPoi(dest);
      final name = resolved?.name ?? await _resolveFallbackName(dest);
      if (mounted) {
        ref.read(mapInteractionProvider.notifier).setDestinationName(name);
      }
    }
  }

  Future<void> _fetchAndStoreAllRoutes(LatLng origin, LatLng dest) async {
    final state = ref.read(mapInteractionProvider);
    ref.read(mapInteractionProvider.notifier).setLoading(true);
    try {
      final routes = await RoutingService.fetchRoutes(
        origin: origin,
        destination: dest,
        waypoints: state.waypoints,
      );
      if (!mounted) return;
      if (routes.isEmpty) {
        // 예외 없이 빈 응답만 온 경우 — 인덱싱할 대상이 없으니 조기 반환.
        return;
      }
      final notifier = ref.read(mapInteractionProvider.notifier);
      notifier.setAllRoutes(routes.map((r) => r.points).toList());
      final scores = await Future.wait(
        routes.map((r) => NativeEngine.scoreFunV2(r.points)),
      );
      notifier.setAllRouteMeta(List.generate(routes.length, (i) => (
        km: routes[i].distanceKm,
        mins: routes[i].durationMin,
        windingScore: scores[i].funScoreV2,
      )));
      final idx = ref.read(mapInteractionProvider).selectedRouteIdx;
      final selIdx = idx.clamp(0, routes.length - 1);
      notifier.setRoutePolyline(routes[selIdx].points);
      if (mounted) {
        setState(() {
          _fetchedRoutes = routes;
          _selectedManeuvers = routes[selIdx].maneuvers;
        });
      }
    } on RoutingException catch (e) {
      if (mounted) _showRoutingError(e, origin, dest);
    } finally {
      if (mounted) ref.read(mapInteractionProvider.notifier).setLoading(false);
    }
  }

  /// 라우팅 오류 유형별 메시지 + 재시도 버튼.
  void _showRoutingError(RoutingException error, LatLng origin, LatLng dest) {
    final String message;
    final bool canRetry;
    switch (error.type) {
      case RoutingError.serverDown:
        message = '라우팅 서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.';
        canRetry = true;
      case RoutingError.serverError:
        message = '서버 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
        canRetry = true;
      case RoutingError.noRoute:
        message = '이 구간의 경로를 찾을 수 없습니다.';
        canRetry = false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: canRetry ? 8 : 4),
        action: canRetry
            ? SnackBarAction(
                label: '다시 시도',
                onPressed: () => _fetchAndStoreAllRoutes(origin, dest),
              )
            : null,
      ),
    );
  }

  // ── 내 장소 (즐겨찾기 + 최근 경로) ─────────────────────────────────────────

  void _showPlacesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlacesSheet(
        onSelectDest: (lat, lng) {
          Navigator.pop(ctx);
          _applyDestination(LatLng(lat, lng));
        },
        onAddFavorite: (lat, lng, name) async {
          await ref.read(favoritePlacesProvider.notifier).add(
                FavoritePlace(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  lat: lat,
                  lng: lng,
                ),
              );
        },
        onRemoveFavorite: (id) =>
            ref.read(favoritePlacesProvider.notifier).remove(id),
      ),
    );
  }

  // ── POI 탐색 (13-1) ────────────────────────────────────────────────────

  Future<void> _showPoiExploreSheet() async {
    // 지도를 팬(이동)해서 다른 지역을 보고 있을 수 있으므로, GPS 위치 대신 현재
    // 화면에 보이는 지도 영역의 중심을 검색 기준점으로 쓴다. 실패 시 GPS로 폴백.
    LatLng? origin = _origin ?? _lastKnown;
    final ctrl = _mlCtrl;
    if (ctrl != null) {
      try {
        final bounds = await ctrl.getVisibleRegion();
        if (!mounted) return;
        origin = LatLng(
          (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
          (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
        );
      } catch (_) {
        origin = _origin ?? _lastKnown;
      }
    }
    if (!mounted) return;

    // 백그라운드 프리페치 캐시가 이 origin과 충분히 가까우면(1km 이내) 네트워크
    // 재요청 없이 그대로 넘겨서 시트가 뜨자마자 칩 필터링이 가능하게 한다 —
    // 너무 멀리 팬했거나 캐시가 아직 없으면 시트가 자체적으로 새로 조회(폴백).
    List<Poi>? initialPois;
    final cacheCenter = _searchPrefetchCenter;
    if (cacheCenter != null &&
        origin != null &&
        PoiService.haversineMeters(cacheCenter, origin) <= 1000) {
      initialPois = _searchPrefetchPois;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PoiExploreSheet(
        origin: origin,
        initialPois: initialPois,
        onSelectDest: (poi) {
          Navigator.pop(ctx);
          _handlePoiTap(poi);
        },
        onSelectAddress: (r) {
          Navigator.pop(ctx);
          _handleAddressTap(r);
        },
      ),
    ).whenComplete(() {
      if (!mounted) return;
      ref.read(poiListProvider.notifier).clear();
    });
  }

  void _clearDestination() {
    ref.read(mapInteractionProvider.notifier).reset();
    ref.read(poiListProvider.notifier).clear();
    setState(() {
      _showCourseSheet = false;
      _touchPoint = null;
    });
    _sheetCtrl.reverse();
    _recenterMap();
    _removeDestMarker(); // unawaited — B2
    _removeOriginMarker(); // unawaited — reset()이 explicit origin도 지우므로 핀도 제거
    _syncWaypointMarkers(const [], const []); // unawaited — 경유지 핀 전체 제거
  }

  void _showWaypointSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WaypointManagementSheet(),
    );
  }

  void _startNavigation() {
    final state = ref.read(mapInteractionProvider);
    final dest = state.destination;
    if (dest == null) return;
    final origin = _origin ?? _lastKnown;
    // 최근 경로 저장
    if (origin != null) {
      final dn = ref.read(mapInteractionProvider).destinationName;
      ref.read(recentRoutesProvider.notifier).add(RecentRoute(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            originLat: origin.latitude,
            originLng: origin.longitude,
            destLat: dest.latitude,
            destLng: dest.longitude,
            at: DateTime.now(),
            destName: dn,
          ));
    }
    // _fetchedRoutes가 빈 경우(재탐색 중 등) clamp의 상한이 -1이 되어 던진다 —
    // 빈 경우엔 인덱싱 자체를 건너뛰고 0으로 둔다.
    final durationMin = _fetchedRoutes.isEmpty
        ? 0
        : _fetchedRoutes[ref
                .read(mapInteractionProvider)
                .selectedRouteIdx
                .clamp(0, _fetchedRoutes.length - 1)]
            .durationMin;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NavScreen(
          destination: dest,
          waypoints: state.waypoints,
          routePolyline: state.routePolyline,
          maneuvers: _selectedManeuvers,
          durationMin: durationMin,
        ),
      ),
    ).then((_) {
      if (mounted) _clearDestination();
    });
  }

  Future<void> _onRouteCardSelect(int idx) async {
    final state = ref.read(mapInteractionProvider);
    ref.read(mapInteractionProvider.notifier).setSelectedRouteIdx(idx);

    final allRoutes = state.allRoutes;
    if (allRoutes.isNotEmpty) {
      // 이미 페치된 경로 즉시 사용 — Valhalla 재호출 없음
      final selIdx = idx.clamp(0, allRoutes.length - 1);
      ref.read(mapInteractionProvider.notifier).setRoutePolyline(allRoutes[selIdx]);
      // 카드 전환 시 maneuvers도 선택된 경로로 동기화
      if (selIdx < _fetchedRoutes.length) {
        setState(() => _selectedManeuvers = _fetchedRoutes[selIdx].maneuvers);
      }
      return;
    }

    // 저장된 경로가 없을 때만 fallback으로 Valhalla 호출
    final origin = _origin ?? _lastKnown;
    final dest = state.destination;
    if (origin == null || dest == null) return;

    await _fetchAndStoreAllRoutes(origin, dest);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<SavedRoute?>(pendingDeepLinkRouteProvider, (_, route) async {
      if (route == null) return;
      ref.read(pendingDeepLinkRouteProvider.notifier).state = null;
      await ref.read(savedRoutesProvider.notifier).add(route);
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('공유된 코스가 저장되었습니다')),
      );
    });

    final interaction = ref.watch(mapInteractionProvider);
    final dest = interaction.destination;
    final waypoint = interaction.waypoint; // ignore: unused_local_variable
    final allRoutes = interaction.allRoutes; // ignore: unused_local_variable
    final selectedRouteIdx = interaction.selectedRouteIdx;

    ref.listen<MapInteractionState>(mapInteractionProvider, (prev, next) {
      if (prev?.routePolyline != next.routePolyline) {
        _updateRouteLayer(next.routePolyline);
      }
      if (prev?.waypoints != next.waypoints) {
        _syncWaypointMarkers(next.waypoints, next.waypointNames); // unawaited
      }
      if (prev?.selectedRouteIdx != next.selectedRouteIdx) {
        _recolorRouteLayer(next.selectedRouteIdx); // unawaited
      }
      if (prev?.destinationName != next.destinationName &&
          next.destination != null) {
        _ensureDestMarker(next.destination!,
            name: next.destinationName); // unawaited — 비동기 이름 해석 완료 후 라벨 갱신
      }
    });

    ref.listen<List<Poi>>(poiListProvider, (prev, next) {
      _updatePoiLayer(next);
    });
    ref.listen<AsyncValue<List<FavoritePlace>>>(
      favoritePlacesProvider,
      (_, next) => _updateFavPoiLayer(next.value ?? const []),
    );
    final isOnline = ref.watch(isOnlineProvider);
    final isDay = ref.watch(isDayProvider);
    final mapNightDimEnabled =
        ref.watch(mapNightDimEnabledProvider).value ?? true;

    ref.listen<AsyncValue<MapLanguage>>(mapLanguageProvider, (_, next) {
      final raw = _rawStyle;
      if (raw == null) return;
      final lang = next.value ?? MapLanguage.korean;
      if (mounted) setState(() => _styleJson = applyMapLanguageToStyle(raw, lang));
    });

    // Map overlay colors. (M2~M3에서 마커에 재사용)
    // ignore: unused_local_variable
    final originColor = AppColors.mapOrigin;
    // ignore: unused_local_variable
    final destColor = AppColors.mapDestination;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (defaultTargetPlatform != TargetPlatform.android) return; // iOS: 아무 동작 없음
        _showExitConfirmSheet(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ══════════════════════════════════════════════════════
          // LAYER 1 · MapLibre Map (osm_liberty 스타일)
          // M1: 빈 지도 + 스타일만. 폴리라인·마커는 M2~M3에서 추가.
          // M2: 경로 폴리라인 GeoJSON 소스/레이어 추가.
          // ══════════════════════════════════════════════════════
          if (_styleJson == null)
            const Center(child: CircularProgressIndicator()),
          if (_styleJson != null)
          ml.MapLibreMap(
            styleString: _styleJson!,
            minMaxZoomPreference: const ml.MinMaxZoomPreference(6.0, 17.0),
            localIdeographFontFamily: _ideographFontFamily,
            initialCameraPosition: ml.CameraPosition(
              target: _toMl(_origin ?? _lastKnown ?? kInitialMapView),
              zoom: _currentZoom,
            ),
            // ctrl.cameraPosition이 실제 카메라를 추적하게 한다 — false(기본값)면
            // onCameraIdle 이후에도 _maybeFetchAmbientPois()의 저비용 사전 판단용
            // camTarget이 초기 위치에 고정돼 팬(pan)해도 ambient POI가 갱신되지 않는다.
            trackCameraPosition: true,
            // 오토바이 거치 — 회전 잠금 (North-up 고정)
            rotateGesturesEnabled: false,
            // 기울기도 잠금 (2D 유지)
            tiltGesturesEnabled: false,
            compassEnabled: false,
            onMapCreated: (c) {
              _mlCtrl = c;
              // S0: 컨트롤러가 준비되기 전에 fix가 먼저 도착해 보류돼 있던
              // 목표가 있고, 아직 실측 fix로 카메라가 보정된 적이 없으면
              // 지금 옮긴다("폴백으로 열렸는지"와는 무관 — FallbackRecenterState
              // 문서 참조).
              final pending = _fallbackRecenter.consumePendingOnMapCreated();
              if (pending != null) {
                c.animateCamera(
                  ml.CameraUpdate.newLatLngZoom(
                      _toMl(pending), _currentZoom.clamp(10.0, 14.0)),
                );
              }
              c.onFeatureTapped.add((point, coords, id, layerId, annotation) {
                if (layerId != _ambientPoiLayerId &&
                    layerId != _poiLayerId &&
                    layerId != _favPoiLayerId) {
                  return;
                }
                final tapLoc = LatLng(coords.latitude, coords.longitude);
                if (layerId == _favPoiLayerId) {
                  // 즐겨찾기 POI 탭 — 가장 가까운 즐겨찾기를 확인시트로 넘긴다.
                  final favs =
                      ref.read(favoritePlacesProvider).value ?? const [];
                  if (favs.isEmpty) return;
                  FavoritePlace? nearestFav;
                  var bestDist = double.infinity;
                  for (final f in favs) {
                    final d = PoiService.haversineMeters(
                        tapLoc, LatLng(f.lat, f.lng));
                    if (d < bestDist) {
                      bestDist = d;
                      nearestFav = f;
                    }
                  }
                  if (nearestFav != null) {
                    unawaited(_handleLocationTap(
                      location: LatLng(nearestFav.lat, nearestFav.lng),
                      name: nearestFav.name,
                      category: nearestFav.category,
                    ));
                  }
                  return;
                }
                final candidates = layerId == _ambientPoiLayerId
                    ? _ambientPois
                    : ref.read(poiListProvider);
                if (candidates.isEmpty) return;
                Poi? nearest;
                var bestDist = double.infinity;
                for (final p in candidates) {
                  final d = PoiService.haversineMeters(tapLoc, p.location);
                  if (d < bestDist) {
                    bestDist = d;
                    nearest = p;
                  }
                }
                if (nearest != null) _handlePoiTap(nearest);
              });
            },
            onStyleLoadedCallback: () async {
              _styleLoaded = true;
              // 스타일 재주입 시 네이티브 어노테이션 매니저가 파괴·재생성되므로
              // Dart 레퍼런스를 초기화해 재생성 경로를 타도록 한다.
              _destMarker = null;
              _originMarker = null;
              _waypointMarkers = <ml.Symbol>[];
              _searchPreviewMarker = null;
              _locLayerReady = false;
              _routeArrowLayerReady = false;
              await _initRouteLayer();
              // 스타일 로드 시점에 이미 경로가 있으면 즉시 반영
              final mapState = ref.read(mapInteractionProvider);
              final poly = mapState.routePolyline;
              if (poly.isNotEmpty) _updateRouteLayer(poly);
              // B2: 목적지/경유지 핀 이미지 1회 등록 (addSymbol 호출보다 먼저)
              final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
              await _mlCtrl!.addImage('pointer_red', pinBytes.buffer.asUint8List());
              final wpBytes = await rootBundle.load('assets/images/pointer_yellow.png');
              await _mlCtrl!.addImage(_kWpIcon, wpBytes.buffer.asUint8List());
              final startBytes = await rootBundle.load('assets/images/pointer_start.png');
              await _mlCtrl!.addImage(_kOriginIcon, startBytes.buffer.asUint8List());
              final arrowBytes = await rootBundle.load('assets/images/arrow_puck.png');
              await _mlCtrl!.addImage(_kArrowIcon, arrowBytes.buffer.asUint8List());
              await _mlCtrl!.setSymbolIconAllowOverlap(true);
              // 스타일 재주입으로 네이티브 어노테이션이 파괴됐으므로(위 주석 참조)
              // 목적지/경유지 핀도 경로 폴리라인과 마찬가지로 현재 상태에서
              // 다시 그려야 한다 — 안 그러면 _destMarker/_waypointMarkers를
              // null로만 초기화하고 실제 심볼은 재생성하지 않아 핀이 사라진 채로
              // 남는 버그가 생긴다. 위 addImage 호출 이후에 실행해야
              // 'pointer_red'/_kWpIcon 이미지가 등록된 상태에서 addSymbol이 나간다.
              final currentDest = mapState.destination;
              if (currentDest != null) {
                await _ensureDestMarker(currentDest,
                    name: mapState.destinationName);
              }
              if (mapState.origin != null) {
                await _ensureOriginMarker(mapState.origin!,
                    name: mapState.stops.first.name);
              }
              if (mapState.waypoints.isNotEmpty) {
                await _syncWaypointMarkers(
                    mapState.waypoints, mapState.waypointNames);
              }
              // B1: 현위치 화살표 puck — 경로 레이어 위에 그려지도록 마지막에 추가
              await _mlCtrl!.addImage(_kRouteArrowIcon, await renderRouteArrowPng());
              await _initRouteArrowLayer();
              await _initLocationLayer();
              await _ensureLocationMarker();
              // POI 카테고리 아이콘 — 스타일 재주입마다 다시 등록해야 한다
              // (addImage도 네이티브 스타일에 종속되어 재생성 시 사라짐).
              // SymbolLayer가 참조하기 전, _initPoiLayer/_initAmbientPoiLayer보다
              // 먼저 등록한다.
              for (final type in PoiType.values) {
                final bytes = await renderPoiIconPng(
                  poiIcons[type]!,
                  poiIconBgColors[type]!,
                );
                await _mlCtrl!.addImage('poi-icon-${type.name}', bytes);
              }
              // 즐겨찾기 전용 아이콘 — 금색 별
              await _mlCtrl!.addImage(
                _kFavPoiIcon,
                await renderPoiIconPng(Icons.star, const Color(0xFFFFD600)),
              );
              // 검색 결과 탭 시 보여주는 임시 초록 점 — POI 아이콘과 같은 이유로
              // 스타일 재주입마다 다시 등록해야 한다.
              await _mlCtrl!.addImage(
                _kSearchPreviewIcon,
                await renderPlainDotPng(AppColors.mapOrigin),
              );
              // 13-1: POI 탐색 결과 원형 레이어
              await _initPoiLayer();
              final pois = ref.read(poiListProvider);
              if (pois.isNotEmpty) _updatePoiLayer(pois);
              // 13-1b: 검색 시트와 무관한 상시 표시 POI 레이어
              await _initAmbientPoiLayer();
              // 즐겨찾기 POI 레이어 — ambient 위에 그려지도록 마지막에 추가
              await _initFavPoiLayer();
              final favs = ref.read(favoritePlacesProvider).value ?? const [];
              if (favs.isNotEmpty) _updateFavPoiLayer(favs);
            },
            onMapClick: (point, latLng) {
              _onMapTap(
                LatLng(latLng.latitude, latLng.longitude),
              );
            },
            onCameraIdle: () {
              final z = _mlCtrl?.cameraPosition?.zoom;
              if (z != null) setState(() => _currentZoom = z);
              unawaited(_maybeFetchAmbientPois());
            },
          ),

          // ══════════════════════════════════════════════════════
          // LAYER 1b · OSM attribution (ODbL 라이선스 필수 표기)
          // 네이티브 attribution 버튼과 별개로 항상 보이는 안전장치.
          // ══════════════════════════════════════════════════════
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

          // ══════════════════════════════════════════════════════
          // LAYER 2 · Loading overlay
          // ══════════════════════════════════════════════════════
          if (interaction.isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.08),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ══════════════════════════════════════════════════════
          // LAYER 2b · Offline banner (network lost during ride)
          // ══════════════════════════════════════════════════════
          if (!isOnline)
            Positioned(
              top: MediaQuery.of(context).padding.top + 58,
              left: 0,
              right: 0,
              child: const _OfflineBanner(),
            ),

          // ══════════════════════════════════════════════════════
          // LAYER 3 · Header  (SafeArea 상단)
          // ══════════════════════════════════════════════════════
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _MapHeader(
                onSettings: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                onPoiSearch: _showPoiExploreSheet,
              ),
            ),
          ),

          // ══════════════════════════════════════════════════════
          // LAYER 3.4 · 기록·즐겨찾기 (헤더 바로 아래, 상단 고정 그룹)
          // top = SafeArea.top + 헤더행높이(68) + 헤더상단패딩(12) + 그룹간격(8)
          // ══════════════════════════════════════════════════════
          Positioned(
            top: MediaQuery.of(context).padding.top + 68 + 12 + 8,
            right: 12,
            child: Column(
              children: [
                MapCtrlBtn(
                  icon: Icons.history_rounded,
                  size: 68,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TourSummaryListScreen()),
                  ),
                ),
                const SizedBox(height: 8),
                MapCtrlBtn(
                  icon: Icons.bookmark_border_rounded,
                  size: 68,
                  onTap: _showPlacesSheet,
                ),
              ],
            ),
          ),

          // ══════════════════════════════════════════════════════
          // LAYER 3.5 · Left Daylight bar
          // ══════════════════════════════════════════════════════
          Positioned(
            left: 12,
            top: MediaQuery.of(context).size.height * 0.30 + 100,
            bottom: _showCourseSheet ? 380 : 160,
            child: _LeftDaylightBar(),
          ),

          // ══════════════════════════════════════════════════════
          // LAYER 4 · Right panel  (현위치·줌인·줌아웃, 하단 고정 그룹)
          // 코스 시트 열림/닫힘과 무관하게 항상 같은 하단 오프셋 사용.
          // ══════════════════════════════════════════════════════
          Positioned(
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 96,
            child: _RightPanel(
              onRecenter: _recenterMap,
              onZoomIn: () => _mlCtrl?.animateCamera(ml.CameraUpdate.zoomIn()),
              onZoomOut: () => _mlCtrl?.animateCamera(ml.CameraUpdate.zoomOut()),
            ),
          ),

          // ══════════════════════════════════════════════════════
          // LAYER 5 · Active state: distance badge (우측 상단)
          // ══════════════════════════════════════════════════════
          if (dest != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              right: 68,
              child: _DistanceBadge(distanceKm: interaction.distanceKm),
            ),

          // ══════════════════════════════════════════════════════
          // LAYER 6 · Touch: 경유지/목적지 floating labels
          //           (핀 탭 직후, 목적지 미확정 상태에서만 표시)
          // ══════════════════════════════════════════════════════
          if (_touchPoint != null && dest == null)
            Positioned(
              // 지도 중앙 약간 하단에 배치 (핀 근처)
              bottom: _showCourseSheet ? 270 : 140,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FloatingActionLabel(
                    label: '목적지',
                    color: AppColors.mapDestination,
                    onTap: () {
                      if (_touchPoint != null) {
                        _applyDestination(_touchPoint!);
                      }
                    },
                  ),
                ],
              ),
            ),

          // ══════════════════════════════════════════════════════
          // LAYER 7 · Bottom area (course sheet)
          //           SafeArea prevents overlap with gesture bar
          // ══════════════════════════════════════════════════════
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Course selection sheet (슬라이드 업)
                if (_showCourseSheet)
                  SlideTransition(
                    position: _sheetSlide,
                    child: CourseSheet(
                      routeMeta: interaction.allRouteMeta,
                      selectedIdx: selectedRouteIdx,
                      onSelect: _onRouteCardSelect,
                      onStart: _startNavigation,
                      onClose: _clearDestination,
                      waypointCount: interaction.waypoints.length,
                      waypointNames: interaction.waypointNames,
                      onWaypointEntryTap: () => _showWaypointSheet(context),
                      originName: interaction.stops.isNotEmpty
                          ? (interaction.stops.first.isCurrentLocation
                              ? '현재 위치'
                              : interaction.stops.first.name)
                          : null,
                      destinationName: interaction.stops.length >= 2
                          ? (interaction.destinationName ?? interaction.stops.last.name)
                          : null,
                    ),
                  ),
              ],
            ),
            ),
          ),

          // LAYER 8 · 야간 디밍 오버레이 (EENT 후 ~ 익일 BMNT)
          // 색 재지정 없이 반투명 검정으로 화면 밝기를 낮춤.
          // IgnorePointer로 터치 투명하게 처리.
          // ══════════════════════════════════════════════════════
          if (!isDay && mapNightDimEnabled)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                ),
              ),
            ),
        ],
      ),
      ), // Scaffold
    ); // PopScope
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _MapHeader extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onPoiSearch;

  const _MapHeader({
    required this.onSettings,
    required this.onPoiSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── 장소 검색 진입 버튼 (탭하면 POI 탐색 시트가 열림) ─────
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(34),
                onTap: onPoiSearch,
                child: Container(
                  height: 68,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(34),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.13),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 24, color: AppColors.secondary),
                      const SizedBox(width: 8),
                      Text(
                        '장소 검색',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          MapCtrlBtn(icon: Icons.settings_outlined, onTap: onSettings, size: 68),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Left Daylight bar  (좌측 배치 전용 래퍼)
// ─────────────────────────────────────────────────────────────────────────────

class _LeftDaylightBar extends ConsumerWidget {
  const _LeftDaylightBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daylightCycle = ref.watch(daylightCycleProvider);
    final daylightProgress = daylightCycle?.progress ?? 0.5;
    final isDay = daylightCycle?.isDay ?? true;
    final topLabel = daylightCycle != null
        ? DateFormat('HH:mm').format(daylightCycle.topTime)
        : '--:--';
    final bottomLabel = daylightCycle != null
        ? DateFormat('HH:mm').format(daylightCycle.bottomTime)
        : '--:--';

    return DaylightBar(
      progress: daylightProgress,
      sunriseLabel: topLabel,
      sunsetLabel: bottomLabel,
      isNightMode: !isDay,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Right Panel  (현위치 · 줌인 · 줌아웃 — 하단 고정 그룹)
// ─────────────────────────────────────────────────────────────────────────────

class _RightPanel extends StatelessWidget {
  final VoidCallback onRecenter;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _RightPanel({
    required this.onRecenter,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── 내 위치 복귀 ────────────────────────────────────
        MapCtrlBtn(icon: Icons.my_location, onTap: onRecenter, size: 68),

        const SizedBox(height: 34),

        // ── 줌 인 ─────────────────────────────────────────
        MapCtrlBtn(icon: Icons.add, onTap: onZoomIn, bold: true, size: 68),

        const SizedBox(height: 4),

        // ── 줌 아웃 ───────────────────────────────────────
        MapCtrlBtn(icon: Icons.remove, onTap: onZoomOut, bold: true, size: 68),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Distance badge (96km 스타일)
// ─────────────────────────────────────────────────────────────────────────────

class _DistanceBadge extends StatelessWidget {
  final double distanceKm;
  const _DistanceBadge({required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        '${distanceKm.toStringAsFixed(0)}km',
        style: AppTextStyles.titleSM.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating action labels (경유지 추가 / 목적지)
// 와이어프레임: 지도 위 핀 근처에 연두/빨강 라벨로 표시
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingActionLabel extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FloatingActionLabel({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: AppTextStyles.labelLG.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map markers
// ─────────────────────────────────────────────────────────────────────────────

// ignore: unused_element
class _OriginMarker extends StatelessWidget {
  final Color color;
  // ignore: unused_element_parameter
  const _OriginMarker({this.color = AppColors.mapOrigin});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 12,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline Banner
// Displayed when connectivity is lost; communicates cached-map fallback.
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFB71C1C).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.wifi_off_rounded, color: Colors.white, size: 15),
            SizedBox(width: 7),
            Text(
              '오프라인 — 캐시 지도 사용 중',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 즐겨찾기 ☆/★ 토글 (POI 팝업/주소·상호명 검색 결과 카드 공용)
// ─────────────────────────────────────────────────────────────────────────────

/// 검색 결과 카드/POI 확인시트 우측 상단에 붙는 ☆(미등록)/★(등록됨) 아이콘.
/// [favoritePlacesProvider]의 현재 목록과 (lat, lng)를 비교해 즉시 반영되므로
/// 별도 상태를 들고 있지 않다 — 등록/해제 후에도 provider 변경만으로 리빌드된다.
class _FavoriteStarButton extends ConsumerWidget {
  final double lat;
  final double lng;
  final String initialName;

  const _FavoriteStarButton({
    required this.lat,
    required this.lng,
    required this.initialName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritePlacesProvider).value ?? const [];
    final existing = FavoritePlace.findByLocation(favorites, lat, lng);
    final isFav = existing != null;

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () async {
        if (isFav) {
          await ref.read(favoritePlacesProvider.notifier).remove(existing.id);
          return;
        }
        await _showAddFavoriteSheet(
          context,
          ref,
          lat: lat,
          lng: lng,
          initialName: initialName,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          isFav ? Icons.star_rounded : Icons.star_border_rounded,
          size: 20,
          color: isFav ? const Color(0xFFFFB300) : Colors.grey.shade400,
        ),
      ),
    );
  }
}

/// ☆ 탭 시 뜨는 즐겨찾기 등록 시트 — 이름(수정 가능, 기본값은 카드에 이미
/// 표시돼 있던 이름/주소)과 카테고리(설정 > 즐겨찾기 카테고리에서 관리하는
/// 목록 + 항상 존재하는 "미분류")를 고른 뒤 확인하면 저장하고 시트를 닫는다.
Future<void> _showAddFavoriteSheet(
  BuildContext context,
  WidgetRef ref, {
  required double lat,
  required double lng,
  required String initialName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddFavoriteSheet(lat: lat, lng: lng, initialName: initialName),
  );
}

class _AddFavoriteSheet extends ConsumerStatefulWidget {
  final double lat;
  final double lng;
  final String initialName;

  const _AddFavoriteSheet({
    required this.lat,
    required this.lng,
    required this.initialName,
  });

  @override
  ConsumerState<_AddFavoriteSheet> createState() => _AddFavoriteSheetState();
}

class _AddFavoriteSheetState extends ConsumerState<_AddFavoriteSheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.initialName);
  String _selectedCategory = kUncategorizedFavoriteCategory;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(favoritePlacesProvider.notifier).add(
          FavoritePlace(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: name,
            lat: widget.lat,
            lng: widget.lng,
            category: _selectedCategory,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(favoriteCategoriesProvider);
    final categories = [
      kUncategorizedFavoriteCategory,
      ...(categoriesAsync.value ?? const <String>[]),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('즐겨찾기 등록',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: '이름',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('카테고리',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((c) {
                      final selected = c == _selectedCategory;
                      return ChoiceChip(
                        label: Text(c),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedCategory = c),
                        labelStyle: const TextStyle(fontSize: 12),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _confirm,
                      child: const Text('확인'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 라운드17 — 앱 종료 확인 카드 (안드로이드 전용)
// ─────────────────────────────────────────────────────────────────────────────

/// 하드웨어 뒤로가기(시스템 back) 시 뜨는 하단 슬라이드업 종료 확인 카드.
/// X 버튼/카드 바깥 탭 = 취소, 카드가 떠 있는 동안 뒤로가기 재입력 = 완전 종료.
void _showExitConfirmSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // 프레임워크 기본 barrier-tap(=maybePop)이 canPop:false와 만나 앱을 통째로
    // 종료시키는 버그가 있어 비활성화하고, 아래 Stack에서 탭-바깥-닫기를 직접 구현한다.
    isDismissible: false,
    builder: (_) => const _ExitConfirmSheet(),
  );
}

class _ExitConfirmSheet extends StatelessWidget {
  const _ExitConfirmSheet();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) SystemNavigator.pop(); // 카드가 뜬 상태에서 재입력 → 완전 종료
      },
      child: Stack(
        children: [
          // 카드 바깥(화면 전체) 탭 = 취소. Navigator.pop()을 직접 호출(=canPop 무시)하므로
          // X 버튼과 동일하게 안전하게 카드만 닫히고 앱이 종료되지 않는다.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // 카드 자체 탭은 무시(닫히지 않음)
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.textHint.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '앱을 종료하시겠습니까?',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: AppColors.textHint),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '뒤로 한 번 더 누르면 앱이 종료됩니다',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Container(
                          height: 90,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.textHint.withValues(alpha: 0.25)),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '광고 영역',
                            style: TextStyle(fontSize: 13, color: AppColors.textHint),
                          ),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 내 장소 시트 (즐겨찾기 + 최근 경로)
// ─────────────────────────────────────────────────────────────────────────────

class _PlacesSheet extends ConsumerWidget {
  final void Function(double lat, double lng) onSelectDest;
  final Future<void> Function(double lat, double lng, String name) onAddFavorite;
  final void Function(String id) onRemoveFavorite;

  const _PlacesSheet({
    required this.onSelectDest,
    required this.onAddFavorite,
    required this.onRemoveFavorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favAsync = ref.watch(favoritePlacesProvider);
    final recentAsync = ref.watch(recentRoutesProvider);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── 즐겨찾기 ────────────────────────────────────────────────────
              const Text('즐겨찾기',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              favAsync.when(
                data: (favs) => favs.isEmpty
                    ? const Text('저장된 장소 없음',
                        style: TextStyle(fontSize: 12, color: Colors.grey))
                    : Column(
                        children: favs.map((p) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.place_rounded,
                              color: AppColors.primary, size: 22),
                          title: Text(p.name,
                              style: const TextStyle(fontSize: 14)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}',
                                  style: const TextStyle(fontSize: 10)),
                              Text(p.category,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _confirmDeleteFavorite(
                              context,
                              () => onRemoveFavorite(p.id),
                            ),
                          ),
                          onTap: () => onSelectDest(p.lat, p.lng),
                        )).toList(),
                      ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    const Text('불러오기 실패', style: TextStyle(color: Colors.red)),
              ),

              const Divider(),

              // ── 최근 경로 ─────────────────────────────────────────────────────
              const Text('최근 경로',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              recentAsync.when(
                data: (recents) => recents.isEmpty
                    ? const Text('최근 경로 없음',
                        style: TextStyle(fontSize: 12, color: Colors.grey))
                    : Column(
                        children: recents.map((r) {
                          final date = '${r.at.month}/${r.at.day} ${r.at.hour.toString().padLeft(2,'0')}:${r.at.minute.toString().padLeft(2,'0')}';
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history_rounded,
                                color: AppColors.secondary, size: 22),
                            title: Text(
                              _routeTitle(r),
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(date,
                                style: const TextStyle(fontSize: 10)),
                            trailing: _FavoriteStarButton(
                              lat: r.destLat,
                              lng: r.destLng,
                              initialName: _routeTitle(r),
                            ),
                            onTap: () => onSelectDest(r.destLat, r.destLng),
                          );
                        }).toList(),
                      ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    const Text('불러오기 실패', style: TextStyle(color: Colors.red)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        ),
      ),
    );
  }

  String _routeTitle(RecentRoute r) {
    final n = r.destName;
    if (n != null && n.trim().isNotEmpty) return n;
    return '→ ${r.destLat.toStringAsFixed(3)}, ${r.destLng.toStringAsFixed(3)}';
  }

  /// 즐겨찾기 삭제 확인 다이얼로그 — `tour_summary_list_screen.dart`의
  /// `_confirmDelete` 패턴(AlertDialog, 제목+본문+취소/삭제)을 복제.
  Future<void> _confirmDeleteFavorite(
    BuildContext context,
    VoidCallback onConfirmed,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('즐겨찾기 삭제'),
        content: const Text('이 즐겨찾기를 삭제할까요?\n삭제하면 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirmed();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POI 탐색 시트 (13-1)
// ─────────────────────────────────────────────────────────────────────────────

/// 검색시트의 검색 모드 — 기본값 business로 기존 상호명 검색 동작을 그대로 보존한다.

class _PoiExploreSheet extends ConsumerStatefulWidget {
  final LatLng? origin;
  // 백그라운드 프리페치 캐시(5종 전체) — null이면 시트가 직접 조회(폴백).
  final List<Poi>? initialPois;
  final void Function(Poi poi) onSelectDest;
  final void Function(AddressResult result) onSelectAddress;

  const _PoiExploreSheet({
    required this.origin,
    this.initialPois,
    required this.onSelectDest,
    required this.onSelectAddress,
  });

  @override
  ConsumerState<_PoiExploreSheet> createState() => _PoiExploreSheetState();
}

class _PoiExploreSheetState extends ConsumerState<_PoiExploreSheet> {
  final Set<PoiType> _selectedTypes = {};
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _loading = false;
  bool _searchFocused = false;
  // origin 반경 내 5종 카테고리 전체 — 프리페치 캐시를 즉시 쓰거나(네트워크 대기
  // 없음), 없으면 이 시트에서 딱 한 번만 조회한다. 이후 칩/검색어 필터링은 전부
  // 클라이언트에서만 처리하고 재조회하지 않는다.
  List<Poi> _allPois = const [];

  // "주유소" 칩만 단독 선택된 상태에서 오피넷(가격 정렬) 조회 결과를 담는다. 그
  // 상태를 벗어나면 null로 비워 다음에 다시 들어올 때 새로 조회하게 한다.
  Future<List<GasStation>>? _gasStationFuture;

  // ── 주소 검색(V-World 지오코더 프록시) 관련 상태 ──────────────────────────
  final AddressSearchService _addressSearchService = AddressSearchService();
  List<AddressResult> _addressResults = [];
  bool _addressLoading = false;
  // "아직 검색 안 함"과 "검색했지만 0건"을 구분할 별도 플래그.
  bool _addressSearched = false;
  // 텍스트 변경(자동완성 포함) 후 자동 검색까지의 디바운스 타이머 — 키 입력마다
  // 쏘지 않고 입력이 잠시 멈췄을 때만 조회해 쿼터가 있는 외부 지오코더 호출량을
  // 억제한다(2026-07-18: OS 키보드 자동완성으로 채워넣으면 onSubmitted가 전혀
  // 발생하지 않아 "아무 반응 없음"으로 보이는 버그 리포트 → 디바운스 자동검색 추가).
  Timer? _addressDebounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    final initial = widget.initialPois;
    if (initial != null) {
      final origin = widget.origin;
      _allPois = List<Poi>.from(initial)
        ..sort((a, b) => origin == null
            ? 0
            : PoiService.haversineMeters(origin, a.location)
                .compareTo(PoiService.haversineMeters(origin, b.location)));
    } else if (widget.origin != null) {
      _loading = true;
      _fetchAll();
    }
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    super.dispose();
  }

  // 포커스 시 시트를 거의 전체화면으로 키워서(build()에서 사용) 키보드에
  // 검색창/결과가 가려지지 않게 한다.
  void _onSearchFocusChanged() {
    setState(() => _searchFocused = _searchFocusNode.hasFocus);
  }

  /// 상호명/주소 검색 모드 전환. 검색창 텍스트와 각 모드의 검색 결과 상태를
  /// 초기화해 모드가 바뀐 뒤 이전 모드의 잔여 텍스트/결과가 뒤섞여 보이는 걸 막는다.
/// V-World 지오코더 프록시(`AddressSearchService`) 호출. 명시적 제출(엔터/검색
  /// 버튼)과 디바운스 자동검색(`_onAddressTextChanged`) 양쪽에서 호출된다 — 어느
  /// 경로로 오든 아직 안 쏜 디바운스 타이머가 남아있으면 중복 호출을 막기 위해
  /// 먼저 취소한다(명시적 제출이 디바운스보다 먼저 도착한 경우 등).
  Future<void> _searchAddress(String query) async {
    _addressDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _addressLoading = true;
    });
    try {
      final rawResults = await _addressSearchService.search(trimmed);
      if (!mounted) return;
      // 응답 대기 중 사용자가 검색창을 지우거나 다른 텍스트로 바꿨으면(디바운스로
      // 이미 새 검색이 걸렸을 수도 있음) 이 낡은 응답으로 화면을 덮어쓰지 않는다.
      if (_searchCtrl.text.trim() != trimmed) return;
      final results = List<AddressResult>.from(rawResults);
      final origin = widget.origin;
      if (origin != null && results.length > 1) {
        results.sort((a, b) =>
            PoiService.haversineMeters(origin, a.location)
                .compareTo(PoiService.haversineMeters(origin, b.location)));
      }
      setState(() {
        _addressResults = results;
        _addressLoading = false;
        _addressSearched = true;
      });
    } on AddressSearchException {
      if (!mounted) return;
      if (_searchCtrl.text.trim() != trimmed) return;
      setState(() {
        _addressResults = [];
        _addressLoading = false;
        _addressSearched = true;
      });
    }
  }

  /// 필터칩이 선택돼 있으면 그것들, 없으면(검색어가 있을 때만) 서버 지원 카테고리
  /// 전체, 둘 다 없으면 빈 집합.
  Set<PoiType> get _effectiveTypes {
    if (_selectedTypes.isNotEmpty) return Set<PoiType>.from(_selectedTypes);
    if (_searchCtrl.text.trim().isNotEmpty) {
      return PoiService.serverSupportedTypes.toSet();
    }
    return const {};
  }

  /// _allPois 중 현재 유효 카테고리에 속하는 것만(검색어 필터 전) — API 자체가
  /// 이 카테고리에 결과가 없는지, 검색어 때문에 줄었는지 구분해 안내 문구를 고르는 데 쓴다.
  List<Poi> get _typeFilteredPois {
    final types = _effectiveTypes;
    if (types.isEmpty) return const [];
    return _allPois.where((p) => types.contains(p.type)).toList();
  }

  /// "주유소" 칩만 단독으로 선택돼 있는지 — `_effectiveTypes`가 아니라 사용자가
  /// 직접 고른 `_selectedTypes`만 본다(검색어만 있고 칩이 없을 때 5종 전체로
  /// 확장되는 `_effectiveTypes`는 이 분기를 타면 안 된다).
  bool get _isGasStationOnly =>
      _selectedTypes.length == 1 && _selectedTypes.single == PoiType.gasStation;

  void _onSearchChanged() {
    // Business: instant client-side filter
    setState(() {});
    ref.read(poiListProvider.notifier).set(_mapPinPois);
    // Address: debounced API call
    _onAddressTextChanged();
  }

  /// 주소 모드에서 검색창 텍스트가 바뀔 때마다(키 입력은 물론, OS 키보드
  /// 자동완성/자동교정처럼 `onSubmitted`를 거치지 않는 경로도 포함) 호출된다.
  /// 자동완성으로 채워넣기만 하고 엔터/검색버튼을 누르지 않으면 아무 반응이 없어
  /// "먹통"으로 보인다는 실기기 리포트(2026-07-18) 대응 — 매 키 입력마다 쏘면
  /// 쿼터가 있는 외부 지오코더를 과다 호출하므로 500ms 디바운스로 묶어 자동검색한다.
  void _onAddressTextChanged() {
    _addressDebounce?.cancel();
    final trimmed = _searchCtrl.text.trim();
    if (trimmed.isEmpty) {
      // 필드를 지웠는데 직전 검색 결과/에러/로딩 상태가 남아있으면 안 되므로 idle로
      // 리셋한다(_addressLoading도 포함 — 지우기 직전 요청이 진행 중이었을 수 있고,
      // 그 응답은 _searchAddress의 stale-guard가 별도로 무시하지만 로딩 스피너
      // 자체는 여기서 바로 꺼줘야 "영원히 스피닝" 없이 즉시 idle 문구로 돌아간다).
      setState(() {
        _addressResults = [];
        _addressLoading = false;
        _addressSearched = false;
      });
      return;
    }
    if (trimmed.length < 2) return; // 한 글자만으로는 조회하지 않음.
    _addressDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _searchAddress(trimmed),
    );
  }

  Future<void> _fetchAll() async {
    final origin = widget.origin;
    if (origin == null) return;
    final List<Poi> pois;
    try {
      pois = await ref.read(poiServiceProvider).fetchPois(
            center: origin,
            radiusMeters: 1500,
            types: PoiService.serverSupportedTypes,
            tag: 'search-sheet',
          );
    } on PoiFetchException {
      // 실패(429/네트워크 오류/서킷 오픈) — 스피너를 반드시 해제한다(안 하면
      // 무한 로딩). 이 화면엔 별도 오류 문구 경로가 없어 기존 "결과 없음" 빈
      // 상태로 자연히 폴백한다.
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    pois.sort((a, b) => PoiService.haversineMeters(origin, a.location)
        .compareTo(PoiService.haversineMeters(origin, b.location)));
    setState(() {
      _allPois = pois;
      _loading = false;
    });
    ref.read(poiListProvider.notifier).set(_mapPinPois);
  }

  void _toggleType(PoiType type) {
    setState(() {
      if (!_selectedTypes.add(type)) _selectedTypes.remove(type);
      // 주유소 단독 선택 상태를 벗어나면 캐시된 조회 future를 비워, 다음에 다시
      // 그 상태로 들어올 때(_buildGasStationBody의 ??= 가드) 새로 조회하게 한다.
      if (!_isGasStationOnly) _gasStationFuture = null;
    });
    ref.read(poiListProvider.notifier).set(_mapPinPois);
  }

  Future<List<GasStation>> _fetchGasStations() {
    final origin = widget.origin;
    if (origin == null) return Future.value(const []);
    return GasStationService.fetchNearby(
      lat: origin.latitude,
      lon: origin.longitude,
      fuel: 'B027',
    );
  }

  /// 검색어(있으면)로 클라이언트 필터링한 뒤 거리순으로 보여줄 목록.
  List<Poi> get _visibleResults {
    final byType = _typeFilteredPois;
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return byType;
    return byType.where((p) => p.name.toLowerCase().contains(query)).toList();
  }

  /// poiListProvider(지도 위 핀)에 넘길 때만 우선순위+분포 기반으로 20개 캡 — 번화가에서
  /// 스크롤 리스트는 그대로 두고 지도 핀만 "수십 개가 한꺼번에 표시" 되던 버그 수정.
  /// 시트 열릴 때 이미 구한 뷰포트 bounds가 없으므로(검색 시트는 리스트 전용, 지도
  /// 뷰포트 개념이 없음) origin을 중심으로 한 정사각형 근사 bounds를 사용한다.
  List<Poi> get _mapPinPois {
    final results = _visibleResults;
    final origin = widget.origin;
    if (origin == null) {
      // degenerate bounds(south==north)로 넘겨 selectForAmbientDisplay 자체의
      // priorityIndex 가드(미매핑 타입 방어)를 그대로 재사용 — 별도 정렬 로직 중복 방지.
      return PoiService.selectForAmbientDisplay(
        candidates: results,
        south: 0,
        north: 0,
        west: 0,
        east: 0,
        center: const LatLng(0, 0),
        maxCount: 20,
      );
    }
    const delta = 0.02; // ~2.2km, 그리드 분산용 근사치일 뿐 실제 필터링엔 영향 없음.
    return PoiService.selectForAmbientDisplay(
      candidates: results,
      south: origin.latitude - delta,
      north: origin.latitude + delta,
      west: origin.longitude - delta,
      east: origin.longitude + delta,
      center: origin,
      maxCount: 20,
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    // 키보드가 뜨면 그 높이만큼 시트 전체를 밀어올려 하단(검색창)이 가려지지 않게 한다.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        constraints: BoxConstraints(
          // 검색창에 포커스가 가면 거의 전체화면으로 확장 — 그 전엔 기존 75%.
          maxHeight: _searchFocused
              ? MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  16
              : MediaQuery.of(context).size.height * 0.75,
        ),
        child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  const Expanded(
                    child: Text('주변 탐색',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── 검색 입력창 ───────────────────────────────────────────────
              TextField(
                controller: _searchCtrl,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: '장소명 또는 주소 입력',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: null,
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: _searchAddress,
              ),
              const SizedBox(height: 10),

              // ── 카테고리 필터 칩 ──────────────────────────────────────────
              SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final type in PoiService.serverSupportedTypes)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(type.label),
                            selected: _selectedTypes.contains(type),
                            onSelected: (_) => _toggleType(type),
                            selectedColor:
                                Color(type.colorValue).withValues(alpha: 0.18),
                            checkmarkColor: Color(type.colorValue),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: _selectedTypes.contains(type)
                                  ? Color(type.colorValue)
                                  : Colors.grey.shade300,
                            ),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _selectedTypes.contains(type)
                                  ? Color(type.colorValue)
                                  : AppColors.secondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(),

              _buildBody(),
              const SizedBox(height: 8),
            ],
          ),
        ),
        ),
      ),
      ),
    );
  }

  Widget _buildBody() {
    // 검색창에 포커스가 있고 텍스트가 비어있으면 최근 검색 이력을 표시한다.
    if (_searchFocused && _searchCtrl.text.trim().isEmpty) {
      return _buildHistoryBody();
    }
    final origin = widget.origin;
    if (origin == null) {
      // 주소 검색 결과도 확인시트/거리표시에 origin이 필요하므로 두 모드 공용.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('GPS 위치를 확인하는 중입니다',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }
    if (_searchCtrl.text.trim().isNotEmpty) {
      return _buildUnifiedBody(origin);
    }
    return _buildBusinessBody(origin);
  }

  Widget _buildUnifiedBody(LatLng origin) {
    if (_isGasStationOnly) return _buildGasStationBody();

    final visible = _visibleResults;

    // POI 섹션
    late final Widget poiSection;
    if (_loading) {
      poiSection = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (visible.isNotEmpty) {
      poiSection = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('상호명',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...visible.map((poi) {
            final dist = PoiService.haversineMeters(origin, poi.location);
            final address = poi.address;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Color(poi.type.colorValue),
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(poi.name, style: const TextStyle(fontSize: 14)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_formatDistance(dist),
                      style: const TextStyle(fontSize: 11)),
                  if (address != null)
                    Text(
                      address,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: _FavoriteStarButton(
                lat: poi.location.latitude,
                lng: poi.location.longitude,
                initialName: poi.name,
              ),
              onTap: () {
                ref
                    .read(searchHistoryProvider.notifier)
                    .add(SearchHistoryItem(
                      query: poi.name,
                      lat: poi.location.latitude,
                      lng: poi.location.longitude,
                      type: 'poi',
                      timestamp: DateTime.now(),
                    ));
                widget.onSelectDest(poi);
              },
            );
          }),
        ],
      );
    } else {
      poiSection = const SizedBox.shrink();
    }

    // 주소 섹션
    late final Widget addressSection;
    if (_addressLoading) {
      addressSection = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_addressResults.isNotEmpty) {
      addressSection = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
                top: visible.isNotEmpty ? 8.0 : 0.0, bottom: 4.0),
            child: const Text('주소',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600)),
          ),
          ..._addressResults.map((r) {
            final dist = PoiService.haversineMeters(origin, r.location);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_on_outlined, size: 20),
              title: Text(r.address, style: const TextStyle(fontSize: 14)),
              subtitle: Text(_formatDistance(dist),
                  style: const TextStyle(fontSize: 11)),
              trailing: _FavoriteStarButton(
                lat: r.location.latitude,
                lng: r.location.longitude,
                initialName: r.address,
              ),
              onTap: () {
                ref
                    .read(searchHistoryProvider.notifier)
                    .add(SearchHistoryItem(
                      query: r.address,
                      lat: r.location.latitude,
                      lng: r.location.longitude,
                      type: 'address',
                      timestamp: DateTime.now(),
                    ));
                widget.onSelectAddress(r);
              },
            );
          }),
        ],
      );
    } else {
      addressSection = const SizedBox.shrink();
    }

    // 둘 다 비고 검색 완료인 경우 "결과 없음" 표시
    if (visible.isEmpty &&
        !_loading &&
        _addressResults.isEmpty &&
        !_addressLoading &&
        _addressSearched) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('검색 결과가 없습니다',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [poiSection, addressSection],
    );
  }

  Widget _buildHistoryBody() {
    final historyAsync = ref.watch(searchHistoryProvider);
    return historyAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('최근 검색 없음',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('최근 검색',
                      style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(searchHistoryProvider.notifier).clear(),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.grey,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('전체 삭제'),
                ),
              ],
            ),
            for (final item in items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, size: 18, color: Colors.grey),
                title: Text(item.query, style: const TextStyle(fontSize: 13)),
                onTap: () {
                  final lat = item.lat;
                  final lng = item.lng;
                  if (lat != null && lng != null) {
                    // 좌표가 있으면 바로 목적지 설정
                    widget.onSelectAddress(AddressResult(
                      address: item.query,
                      location: LatLng(lat, lng),
                    ));
                  } else {
                    // 좌표 없으면 검색창에 채워서 재검색 유도
                    _searchCtrl.text = item.query;
                    _searchCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: item.query.length),
                    );
                  }
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildBusinessBody(LatLng origin) {
    if (_isGasStationOnly) {
      return _buildGasStationBody();
    }
    if (_effectiveTypes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('카테고리를 선택하거나 상호명을 검색하세요',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_typeFilteredPois.isEmpty) {
      // API 자체가 0건(NODATA 포함)을 반환한 경우.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('주변에 결과가 없습니다',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }
    final visible = _visibleResults;
    if (visible.isEmpty) {
      // 조회는 됐지만 상호명 검색어 필터 결과가 0건인 경우.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('검색 결과가 없습니다',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }
    return Column(
      children: visible.map((poi) {
        final dist = PoiService.haversineMeters(origin, poi.location);
        final address = poi.address;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Color(poi.type.colorValue),
              shape: BoxShape.circle,
            ),
          ),
          title: Text(poi.name, style: const TextStyle(fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatDistance(dist), style: const TextStyle(fontSize: 11)),
              if (address != null)
                Text(
                  address,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          trailing: _FavoriteStarButton(
            lat: poi.location.latitude,
            lng: poi.location.longitude,
            initialName: poi.name,
          ),
          onTap: () {
            ref.read(searchHistoryProvider.notifier).add(SearchHistoryItem(
              query: poi.name,
              lat: poi.location.latitude,
              lng: poi.location.longitude,
              type: 'poi',
              timestamp: DateTime.now(),
            ));
            widget.onSelectDest(poi);
          },
        );
      }).toList(),
    );
  }

  /// "주유소" 칩 단독 선택 시 소상공인 POI 대신 오피넷(가격순) 목록을 보여준다.
  /// 검색창(_searchCtrl)은 이 분기에서 관여하지 않는다 — 칩 행은 계속 보이지만
  /// 상호명 필터링은 적용되지 않는다(범위 밖).
  Widget _buildGasStationBody() {
    _gasStationFuture ??= _fetchGasStations();
    return FutureBuilder<List<GasStation>>(
      future: _gasStationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final stations = snapshot.data ?? [];
        if (stations.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('5km 내 주유소 정보를 찾을 수 없습니다',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < stations.length; i++)
              _buildGasStationTile(stations[i], i),
          ],
        );
      },
    );
  }

  Widget _buildGasStationTile(GasStation station, int index) {
    final rankColor = Color(PoiType.gasStation.colorValue);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: rankColor.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: rankColor,
            ),
          ),
        ),
      ),
      title: Text(
        station.name,
        style: const TextStyle(fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_formatDistance(station.distanceM)}  •  ${station.brand.isNotEmpty ? station.brand : "기타"}',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
      trailing: station.price != null
          ? Text(
              '${_formatGasPrice(station.price!)}원',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            )
          : null,
      onTap: () {
        final poi = Poi(
          id: '${station.lat}_${station.lon}',
          name: station.name,
          type: PoiType.gasStation,
          location: LatLng(station.lat, station.lon),
          address: station.address.isEmpty ? null : station.address,
        );
        widget.onSelectDest(poi);
      },
    );
  }

  String _formatGasPrice(int price) {
    final s = price.toString();
    if (s.length <= 3) return s;
    return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 검색 결과 → 경로 추가 선택 시트
// ─────────────────────────────────────────────────────────────────────────────

/// 검색 결과 아이템 탭 시 "어디로 추가할까요?" 선택지를 보여주는 바텀시트.
///
/// - 출발지로 설정: [_RouteAddAction.origin] 반환
/// - 경유지로 추가: [_RouteAddAction.waypoint] 반환 ([hasDest]가 true일 때만 활성)
/// - 목적지로 설정: [_RouteAddAction.destination] 반환
class _AddToRouteSheet extends StatelessWidget {
  final String name;
  /// 목적지가 이미 설정된 경우 true — 경유지 추가 버튼 활성화 여부 결정.
  final bool hasDest;
  final double lat;
  final double lng;

  const _AddToRouteSheet({
    required this.name,
    required this.hasDest,
    required this.lat,
    required this.lng,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FavoriteStarButton(lat: lat, lng: lng, initialName: name),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.trip_origin, size: 16, color: AppColors.primary),
                        label: const Text(
                          '출발',
                          style: TextStyle(color: AppColors.primary),
                          softWrap: false,
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          overlayColor: AppColors.primary.withValues(alpha: 0.15),
                        ),
                        onPressed: () => Navigator.pop(context, _RouteAddAction.origin),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(
                          Icons.add_location_alt_outlined,
                          size: 16,
                          color: hasDest ? AppColors.primary : Colors.grey.shade300,
                        ),
                        label: Text(
                          '경유지',
                          style: TextStyle(
                            color: hasDest ? AppColors.primary : Colors.grey.shade300,
                          ),
                          softWrap: false,
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: hasDest ? AppColors.primary : Colors.grey.shade200,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          overlayColor: AppColors.primary.withValues(alpha: 0.15),
                        ),
                        onPressed: hasDest
                            ? () => Navigator.pop(context, _RouteAddAction.waypoint)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.flag_outlined, size: 16, color: AppColors.primary),
                        label: const Text(
                          '도착',
                          style: TextStyle(color: AppColors.primary),
                          softWrap: false,
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          overlayColor: AppColors.primary.withValues(alpha: 0.15),
                        ),
                        onPressed: () => Navigator.pop(context, _RouteAddAction.destination),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

