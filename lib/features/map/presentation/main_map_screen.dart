import 'dart:async';
import 'dart:math' show Point, cos, sqrt, asin, min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator, rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/course_sheet.dart';
import '../../../core/widgets/daylight_bar.dart';
import '../../../models/map_language.dart';
import '../../../models/poi.dart';
import '../../../models/saved_place.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/map_cache_provider.dart'; // ignore: unused_import
import '../../../services/native_engine.dart';
import '../../../services/poi_service.dart';
import '../../../services/routing_service.dart';
import '../providers/map_providers.dart';
import '../style_language_transform.dart';
import '../../navigation/presentation/nav_screen.dart';
import '../../navigation/providers/nav_state_provider.dart';
import '../../settings/providers/settings_providers.dart';
import '../../settings/presentation/settings_screen.dart';
import '../poi_feature_picker.dart';
import '../poi_name_resolver.dart';
import '../poi_category.dart';

export 'main_map_screen.dart';

enum _TapAction { destination, waypoint }

class _TappedPoi {
  final String? name;
  final String? category;
  const _TappedPoi({this.name, this.category});
}

/// Last-resort map framing: first install + no last-known position.
/// Camera only — never treated as the rider's location.
const LatLng kInitialMapView = LatLng(36.5, 127.5); // 한국 지리 중심 (서울 아님)

// ─────────────────────────────────────────────────────────────────────────────
// Grid-based POI clustering
// ─────────────────────────────────────────────────────────────────────────────

class _ClusterCell {
  final List<Poi> pois;
  _ClusterCell(this.pois);
  Poi get representative => pois.first;
  int get count => pois.length;
  LatLng get center {
    final lat =
        pois.map((p) => p.location.latitude).reduce((a, b) => a + b) /
            pois.length;
    final lng =
        pois.map((p) => p.location.longitude).reduce((a, b) => a + b) /
            pois.length;
    return LatLng(lat, lng);
  }
}

List<_ClusterCell> _clusterPois(List<Poi> pois, double zoom) {
  final cellSize =
      zoom >= 14 ? 0.005 : zoom >= 12 ? 0.015 : 0.04;
  final Map<String, List<Poi>> grid = {};
  for (final p in pois) {
    final row = (p.location.latitude / cellSize).floor();
    final col = (p.location.longitude / cellSize).floor();
    final key = '$row:$col:${p.type.name}';
    grid.putIfAbsent(key, () => []).add(p);
  }
  return grid.values.map((ps) => _ClusterCell(ps)).toList();
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
  final MapController _mapCtrl = MapController();
  ml.MapLibreMapController? _mlCtrl; // M1~M4 동안 점진 연결
  bool _styleLoaded = false;

  static const _routeSourceId = 'route-source';
  static const _routeLayerId = 'route-layer';
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

  bool _locLayerReady = false;
  ml.Symbol? _destMarker;
  List<ml.Symbol> _waypointMarkers = [];
  static const String _kDestIcon = 'pointer_red';
  static const double _kDestIconSize = 1.05; // nav_screen과 동일 배율(96px 핀 기준)
  static const String _kWpIcon = 'pointer_yellow';
  static const double _kWpIconSize = 1.05; // nav_screen과 동일 배율
  static const String _kArrowIcon = 'nav_arrow';
  static const double _kArrowIconSize = 1.0; // nav_screen과 동일

  double? _lastHeadingDeg; // 정차/저속 시 최근 방향 유지용

  // latlong2.LatLng → maplibre_gl.LatLng 변환 (지도에 넘길 때만 사용)
  ml.LatLng _toMl(LatLng p) => ml.LatLng(p.latitude, p.longitude);

  // Nullable until the device returns a real GPS fix — prevents the origin
  // marker / distance badge from rendering at a hardcoded mock location.
  LatLng? _origin;
  LatLng? _lastKnown; // getLastKnownPosition() 결과 — GPS 스트림보다 먼저 도착
  ProviderSubscription<NavigationState?>? _locationSub;

  // 뒤로 연타 종료
  DateTime? _lastBackPress;

  // 마지막으로 페치한 3경로 전체 — 카드 전환 시 maneuvers 참조용
  List<RouteResult> _fetchedRoutes = const [];
  // 선택된 경로의 턴바이턴 maneuvers — NavScreen 으로 전달
  List<ManeuverStep> _selectedManeuvers = const [];
  double _currentZoom = 16.0; // z16 고정 초기 줌

  // 13-1b: 상시 표시 POI (ambient) — 검색 시트를 열지 않아도 줌 레벨에 따라
  // 자동으로 표시/갱신되는 별개 레이어의 로컬 상태.
  List<Poi> _ambientPois = const [];
  DateTime? _lastAmbientFetchAt;
  LatLng? _lastAmbientFetchCenter;
  Set<PoiType> _lastAmbientFetchTypes = const {};
  // 진행 중인 fetch보다 나중에 시작된 호출이 있으면 이전 응답은 버린다(stale-response 가드).
  int _ambientFetchGen = 0;

  // 6번: 검색 시트("장소 검색") 전용 백그라운드 프리페치 — ambient 레이어(위)와는
  // 완전히 별개. GPS 위치 갱신 시마다 5종 전체를 미리 받아 캐시해 둬서, 시트를
  // 열었을 때 네트워크 대기 없이 바로 칩 필터링이 가능하게 한다.
  List<Poi> _searchPrefetchPois = const [];
  LatLng? _searchPrefetchCenter;
  DateTime? _searchPrefetchAt;
  int _searchPrefetchGen = 0;

  // Course sheet
  bool _showCourseSheet = false;

  String? _rawStyle;   // 원본 JSON 1회 로드
  String? _styleJson;  // 언어 적용 후 주입 문자열

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
    setState(() {
      _rawStyle = raw;
      _styleJson = applyMapLanguageToStyle(raw, lang);
    });
  }

  @override
  void dispose() {
    _locationSub?.close();
    _mapCtrl.dispose();
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
        _mlCtrl?.animateCamera(
          ml.CameraUpdate.newLatLngZoom(_toMl(loc), _currentZoom.clamp(10.0, 14.0)),
        );
        _ensureLocationMarker(); // unawaited — B1
        unawaited(_maybeFetchSearchPrefetch(loc));
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
          _mlCtrl?.animateCamera(
            ml.CameraUpdate.newLatLngZoom(_toMl(loc), _currentZoom.clamp(10.0, 14.0)),
          );
        }
        final heading = _resolveHeading(next.speedKmh, next.headingDeg);
        _ensureLocationMarker(heading); // unawaited — B1
        unawaited(_maybeFetchSearchPrefetch(loc));
      },
      fireImmediately: true,
    );
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
                  },
                })
            .toList(),
      };

  Future<void> _initPoiLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null) return;
    await ctrl.addGeoJsonSource(_poiSourceId, _buildPoiGeoJson(const []));
    await ctrl.addCircleLayer(
      _poiSourceId,
      _poiLayerId,
      const ml.CircleLayerProperties(
        circleRadius: 7,
        circleColor: [
          'match',
          ['get', 'poiType'],
          'cafe', '#FF7700',
          'convenienceStore', '#2196F3',
          'gasStation', '#E53935',
          'supermarket', '#8E24AA',
          'restaurant', '#FFB300',
          '#9E9E9E',
        ],
        circleStrokeWidth: 2,
        circleStrokeColor: '#FFFFFF',
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
    await ctrl.addCircleLayer(
      _ambientPoiSourceId,
      _ambientPoiLayerId,
      const ml.CircleLayerProperties(
        circleRadius: 7,
        circleColor: [
          'match',
          ['get', 'poiType'],
          'cafe', '#FF7700',
          'convenienceStore', '#2196F3',
          'gasStation', '#E53935',
          'supermarket', '#8E24AA',
          'restaurant', '#FFB300',
          '#9E9E9E',
        ],
        circleStrokeWidth: 2,
        circleStrokeColor: '#FFFFFF',
      ),
    );
  }

  void _updateAmbientPoiLayer(List<Poi> pois) {
    if (!_styleLoaded) return;
    _mlCtrl?.setGeoJsonSource(_ambientPoiSourceId, _buildPoiGeoJson(pois));
  }

  /// 현재 줌 레벨에서 노출 대상인 카테고리를 계산하고, 필요 시(카테고리 변경 시
  /// 즉시 / 그 외엔 200m 이동 또는 15초 경과 디바운스) 뷰포트 중심 기준으로
  /// POI를 재조회해 ambient 레이어를 갱신한다. 화면에 실제 보이는 것만, 가까운
  /// 순 최대 10개로 제한한다.
  Future<void> _maybeFetchAmbientPois() async {
    final ctrl = _mlCtrl;
    if (ctrl == null || !_styleLoaded) return;

    final targetTypes =
        PoiType.values.where((t) => _currentZoom >= t.minZoomLevel).toSet();
    if (targetTypes.isEmpty) {
      _ambientFetchGen++; // 진행 중이던 fetch가 있으면 응답을 무효화
      if (_ambientPois.isNotEmpty) {
        _ambientPois = const [];
        _updateAmbientPoiLayer(const []);
      }
      _lastAmbientFetchTypes = const {};
      return;
    }

    // 디바운스 판단은 getVisibleRegion()(플랫폼 채널 호출) 없이도 가능한
    // 저비용 동기 카메라 중심점으로 먼저 끝낸다 — 실제로 재조회할 때만
    // getVisibleRegion()을 부른다. onCameraIdle 직후라 카메라가 정지해
    // 있으므로 이 값이 곧 뷰포트 중심과 사실상 같다(회전/기울기 잠금이라
    // bounds가 target 기준으로 대칭).
    final camTarget = ctrl.cameraPosition?.target;
    if (camTarget == null) return;
    final approxCenter = LatLng(camTarget.latitude, camTarget.longitude);

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

    // 이 호출 시작 시점의 세대를 기록 — 아래 두 await(getVisibleRegion,
    // fetchPois) 도중 더 최신 호출이 시작되면(_ambientFetchGen이 바뀌면)
    // 이 응답은 stale이니 버린다. getVisibleRegion 앞에서 찍어야
    // 그 await 도중 끼어든 최신 호출까지 감지된다.
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
    final radius = min(
      2000.0,
      PoiService.haversineMeters(
        center,
        LatLng(bounds.northeast.latitude, bounds.northeast.longitude),
      ),
    );

    final pois = await ref.read(poiServiceProvider).fetchPois(
          center: center,
          radiusMeters: radius,
          types: targetTypes.toList(),
        );
    if (!mounted || myGen != _ambientFetchGen) return;

    final visible = pois
        .where((p) =>
            p.location.latitude >= bounds.southwest.latitude &&
            p.location.latitude <= bounds.northeast.latitude &&
            p.location.longitude >= bounds.southwest.longitude &&
            p.location.longitude <= bounds.northeast.longitude)
        .toList()
      ..sort((a, b) => PoiService.haversineMeters(center, a.location)
          .compareTo(PoiService.haversineMeters(center, b.location)));
    final limited = visible.take(10).toList();

    _ambientPois = limited;
    _updateAmbientPoiLayer(limited);
    _lastAmbientFetchAt = DateTime.now();
    _lastAmbientFetchCenter = center;
    _lastAmbientFetchTypes = targetTypes;
  }

  /// GPS 위치가 갱신될 때마다(캐시된 마지막 위치 포함) 호출 — 검색 시트(_PoiExploreSheet)용
  /// 5종 카테고리 전체를 1500m 반경으로 미리 받아둔다. 500m 이동 또는 60초 경과 전엔
  /// 재조회하지 않는다 — ambient 레이어보다 완화된 디바운스(반경이 넓어 약간의 위치 오차가
  /// 결과에 큰 영향을 주지 않고, 검색은 ambient만큼 실시간성이 필요하지 않음).
  Future<void> _maybeFetchSearchPrefetch(LatLng center) async {
    final lastCenter = _searchPrefetchCenter;
    final lastAt = _searchPrefetchAt;
    final movedEnough =
        lastCenter == null || PoiService.haversineMeters(lastCenter, center) >= 500;
    final staleEnough =
        lastAt == null || DateTime.now().difference(lastAt) >= const Duration(seconds: 60);
    if (!movedEnough && !staleEnough) return;

    final myGen = ++_searchPrefetchGen;
    final pois = await ref.read(poiServiceProvider).fetchPois(
          center: center,
          radiusMeters: 1500,
          types: PoiType.values,
        );
    if (!mounted || myGen != _searchPrefetchGen) return;

    _searchPrefetchPois = pois;
    _searchPrefetchCenter = center;
    _searchPrefetchAt = DateTime.now();
  }

  Future<void> _ensureLocationMarker([double? heading]) async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded || !_locLayerReady) return;
    final p = _origin ?? _lastKnown;
    if (p == null) return;
    await c.setGeoJsonSource(_locSourceId, _buildLocGeoJson(p, heading));
  }

  Future<void> _ensureDestMarker(LatLng dest) async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded) return;
    final geo = _toMl(dest);
    if (_destMarker == null) {
      _destMarker = await c.addSymbol(ml.SymbolOptions(
        geometry: geo,
        iconImage: _kDestIcon,
        iconSize: _kDestIconSize,
        iconAnchor: 'bottom',
        zIndex: 10,
      ));
    } else {
      await c.updateSymbol(_destMarker!, ml.SymbolOptions(geometry: geo));
    }
  }

  Future<void> _removeDestMarker() async {
    final c = _mlCtrl;
    if (c != null && _destMarker != null) {
      await c.removeSymbol(_destMarker!);
    }
    _destMarker = null;
  }

  Future<void> _syncWaypointMarkers(List<LatLng> waypoints) async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded) return;
    for (final s in _waypointMarkers) {
      await c.removeSymbol(s);
    }
    _waypointMarkers = [];
    for (final wp in waypoints) {
      final s = await c.addSymbol(ml.SymbolOptions(
        geometry: _toMl(wp),
        iconImage: _kWpIcon,
        iconSize: _kWpIconSize,
        iconAnchor: 'bottom',
        zIndex: 5,
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

  // ── Map tap ───────────────────────────────────────────────────────────────

Future<void> _onMapTap(TapPosition _, LatLng tapped) async {
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
    final hasRoute = _showCourseSheet;
    final act = await _showTapConfirmSheet(tapped, poi, hasRoute);
    if (!mounted) return;

    if (act == _TapAction.waypoint) {
      ref.read(mapInteractionProvider.notifier).addWaypoint(tapped);
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
      return;
    }
    if (act != _TapAction.destination) return;

    setState(() {
      _touchPoint = tapped;
      _touchDistKm = _haversineKm(origin, tapped);
    });
    await _applyDestination(tapped, preResolved: poi?.name);
  }

  Future<_TapAction?> _showTapConfirmSheet(LatLng tapped, _TappedPoi? poi, bool hasRoute) {
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
                const SizedBox(height: 4),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Color(0xFF008080)),
                  title: const Text('여기로 안내'),
                  onTap: () => Navigator.pop(context, _TapAction.destination),
                ),
                if (hasRoute)
                  ListTile(
                    leading: const Icon(Icons.add_location_alt_outlined,
                        color: Color(0xFF008080)),
                    title: const Text('경유지 추가'),
                    subtitle: const Text('현재 경로에 경유지를 삽입합니다',
                        style: TextStyle(fontSize: 12)),
                    onTap: () => Navigator.pop(context, _TapAction.waypoint),
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

  Future<void> _applyDestination(LatLng dest, {String? preResolved}) async {
    final origin = _origin ?? _lastKnown;
    if (origin == null) return;
    final dist = _haversineKm(origin, dest);
    ref.read(mapInteractionProvider.notifier).setDestination(dest, dist);

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

    _ensureDestMarker(dest); // unawaited — B2

    // Valhalla 3회 병렬 호출 (시골길·지방도로·국도) → 3카드 동시 표시
    _fetchAndStoreAllRoutes(origin, dest);

    if (preResolved != null) {
      ref.read(mapInteractionProvider.notifier).setDestinationName(preResolved);
    } else {
      final resolved = await _resolveTappedPoi(dest);
      if (mounted) {
        ref.read(mapInteractionProvider.notifier).setDestinationName(resolved?.name);
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
        onSelectDest: (dest) {
          Navigator.pop(ctx);
          _applyDestination(dest);
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
    _syncWaypointMarkers(const []); // unawaited — 경유지 핀 전체 제거
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
    final selIdx = ref.read(mapInteractionProvider).selectedRouteIdx
        .clamp(0, _fetchedRoutes.length - 1);
    final durationMin = selIdx < _fetchedRoutes.length
        ? _fetchedRoutes[selIdx].durationMin
        : 0;
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

  // ── POI markers ───────────────────────────────────────────────────────────

  // ignore: unused_element
  List<Marker> _buildPoiMarkers(List<Poi> pois) {
    return _clusterPois(pois, _currentZoom).map((cell) {
      final color = Color(cell.representative.type.colorValue);
      return Marker(
        point: cell.center,
        width: cell.count > 1 ? 36 : 18,
        height: cell.count > 1 ? 36 : 18,
        child: cell.count > 1
            ? _ClusterDot(color: color, count: cell.count)
            : _PoiDot(color: color),
      );
    }).toList();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
        _syncWaypointMarkers(next.waypoints); // unawaited
      }
      if (prev?.selectedRouteIdx != next.selectedRouteIdx) {
        _recolorRouteLayer(next.selectedRouteIdx); // unawaited
      }
    });

    ref.listen<List<Poi>>(poiListProvider, (prev, next) {
      _updatePoiLayer(next);
    });
    final isOnline = ref.watch(isOnlineProvider);
    final riderMode = ref.watch(riderModeProvider);
    final isDay = ref.watch(isDayProvider);

    ref.listen<AsyncValue<MapLanguage>>(mapLanguageProvider, (_, next) {
      final raw = _rawStyle;
      if (raw == null) return;
      final lang = next.value ?? MapLanguage.korean;
      if (mounted) setState(() => _styleJson = applyMapLanguageToStyle(raw, lang));
    });

    // Theme-adaptive colors for map overlays. (M2~M3에서 마커에 재사용)
    // ignore: unused_local_variable
    final originColor =
        riderMode ? RiderModeColors.mapOrigin : AppColors.mapOrigin;
    // ignore: unused_local_variable
    final destColor =
        riderMode ? RiderModeColors.mapDestination : AppColors.mapDestination;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          SystemNavigator.pop(); // Android 완전 종료
          return;
        }
        _lastBackPress = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('뒤로 한 번 더 누르면 앱이 종료됩니다'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        backgroundColor:
            riderMode ? RiderModeColors.background : AppColors.background,
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
            initialCameraPosition: ml.CameraPosition(
              target: _toMl(_origin ?? _lastKnown ?? kInitialMapView),
              zoom: _currentZoom,
            ),
            // 오토바이 거치 — 회전 잠금 (North-up 고정)
            rotateGesturesEnabled: false,
            // 기울기도 잠금 (2D 유지)
            tiltGesturesEnabled: false,
            compassEnabled: false,
            onMapCreated: (c) => _mlCtrl = c,
            onStyleLoadedCallback: () async {
              _styleLoaded = true;
              // 스타일 재주입 시 네이티브 어노테이션 매니저가 파괴·재생성되므로
              // Dart 레퍼런스를 초기화해 재생성 경로를 타도록 한다.
              _destMarker = null;
              _waypointMarkers = <ml.Symbol>[];
              _locLayerReady = false;
              await _initRouteLayer();
              // 스타일 로드 시점에 이미 경로가 있으면 즉시 반영
              final poly =
                  ref.read(mapInteractionProvider).routePolyline;
              if (poly.isNotEmpty) _updateRouteLayer(poly);
              // B2: 목적지/경유지 핀 이미지 1회 등록 (addSymbol 호출보다 먼저)
              final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
              await _mlCtrl!.addImage('pointer_red', pinBytes.buffer.asUint8List());
              final wpBytes = await rootBundle.load('assets/images/pointer_yellow.png');
              await _mlCtrl!.addImage(_kWpIcon, wpBytes.buffer.asUint8List());
              final arrowBytes = await rootBundle.load('assets/images/arrow_puck.png');
              await _mlCtrl!.addImage(_kArrowIcon, arrowBytes.buffer.asUint8List());
              await _mlCtrl!.setSymbolIconAllowOverlap(true);
              // B1: 현위치 화살표 puck — 경로 레이어 위에 그려지도록 마지막에 추가
              await _initLocationLayer();
              await _ensureLocationMarker();
              // 13-1: POI 탐색 결과 원형 레이어
              await _initPoiLayer();
              final pois = ref.read(poiListProvider);
              if (pois.isNotEmpty) _updatePoiLayer(pois);
              // 13-1b: 검색 시트와 무관한 상시 표시 POI 레이어
              await _initAmbientPoiLayer();
            },
            onMapClick: (point, latLng) {
              _onMapTap(
                const TapPosition(Offset.zero, null),
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
                riderMode: riderMode,
                onRiderModeToggle: () =>
                    ref.read(riderModeProvider.notifier).toggle(),
                onCourseRegister: () {},
                onTourSummary: () {},
                onSavedCourses: _showPlacesSheet,
                onSettings: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                onPoiSearch: _showPoiExploreSheet,
              ),
            ),
          ),

          // ══════════════════════════════════════════════════════
          // LAYER 4 · Right panel  (Daylight + map controls)
          // ══════════════════════════════════════════════════════
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: _RightPanel(
                showCourseSheet: _showCourseSheet,
                onRecenter: _recenterMap,
                onZoomIn: () => _mlCtrl?.animateCamera(ml.CameraUpdate.zoomIn()),
                onZoomOut: () => _mlCtrl?.animateCamera(ml.CameraUpdate.zoomOut()),
              ),
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
      ), // Scaffold
    ); // PopScope
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _MapHeader extends StatelessWidget {
  final bool riderMode;
  final VoidCallback onRiderModeToggle;
  final VoidCallback onCourseRegister;
  final VoidCallback onTourSummary;
  final VoidCallback onSavedCourses;
  final VoidCallback onSettings;
  final VoidCallback onPoiSearch;

  const _MapHeader({
    required this.riderMode,
    required this.onRiderModeToggle,
    required this.onCourseRegister,
    required this.onTourSummary,
    required this.onSavedCourses,
    required this.onSettings,
    required this.onPoiSearch,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = riderMode
        ? RiderModeColors.surface.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);

    return Container(
      color: bgColor,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── 로고 ─────────────────────────────────────────────
              _LogoBadge(riderMode: riderMode),
              const Spacer(),
              // ── 라이더 모드 토글 (햇빛 아이콘) ───────────────────
              _HeaderIcon(
                icon: riderMode ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                onTap: onRiderModeToggle,
                active: riderMode,
                activeColor: RiderModeColors.primary,
                activeBg: RiderModeColors.surface,
              ),
              const SizedBox(width: 6),
              _HeaderIcon(icon: Icons.image_outlined, onTap: onCourseRegister),
              const SizedBox(width: 6),
              _HeaderIcon(icon: Icons.history_rounded, onTap: onTourSummary),
              const SizedBox(width: 6),
              _HeaderIcon(icon: Icons.bookmark_border_rounded, onTap: onSavedCourses),
              const SizedBox(width: 6),
              _HeaderIcon(icon: Icons.settings_outlined, onTap: onSettings),
            ],
          ),
          const SizedBox(height: 8),
          // ── 장소 검색 진입 버튼 (탭하면 POI 탐색 시트가 열림) ─────
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onPoiSearch,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
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
                    Icon(Icons.search, size: 20, color: AppColors.secondary),
                    const SizedBox(width: 8),
                    Text(
                      '장소 검색',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  final bool riderMode;
  const _LogoBadge({this.riderMode = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: riderMode
            ? RiderModeColors.surface
            : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: riderMode
              ? RiderModeColors.primary.withValues(alpha: 0.4)
              : AppColors.primary.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Image.asset(
        'assets/images/yuru_2line.jpeg',
        height: 32,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'YURU',
                  style: GoogleFontsHelper.logoStyle.copyWith(
                    color: riderMode
                        ? RiderModeColors.primary
                        : AppColors.primary,
                  ),
                ),
                TextSpan(
                  text: 'NAVI',
                  style: GoogleFontsHelper.logoStyle.copyWith(
                    color: riderMode
                        ? RiderModeColors.secondary
                        : AppColors.secondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// google_fonts 없이도 동작하는 helper
class GoogleFontsHelper {
  static TextStyle get logoStyle => const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        height: 1.0,
      );
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;
  final Color? activeBg;

  const _HeaderIcon({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.activeColor,
    this.activeBg,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active
              ? (activeBg ?? AppColors.primary.withValues(alpha: 0.15))
              : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 19,
          color: active
              ? (activeColor ?? AppColors.primary)
              : AppColors.secondary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Right Panel  (Daylight bar + compass + zoom controls)
// 와이어프레임: 일출 아이콘·라벨 → 세로 게이지 바 → 일몰 아이콘·라벨 → 나침반 → + → 슬라이더 → -
// ─────────────────────────────────────────────────────────────────────────────

class _RightPanel extends ConsumerWidget {
  final bool showCourseSheet;
  final VoidCallback onRecenter;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _RightPanel({
    required this.showCourseSheet,
    required this.onRecenter,
    required this.onZoomIn,
    required this.onZoomOut,
  });

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

    // 코스 시트가 올라왔을 때 패널 하단 여유 조절
    final bottomPad = showCourseSheet ? 220.0 : 60.0;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad, top: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── 공용 DaylightBar (메인/내비 동일 위젯) ──────────
          Flexible(
            child: DaylightBar(
              progress: daylightProgress,
              sunriseLabel: topLabel,
              sunsetLabel: bottomLabel,
              isNightMode: !isDay,
            ),
          ),

          const SizedBox(height: 14),

          // ── 내 위치 복귀 ────────────────────────────────────
          _MapCtrlBtn(icon: Icons.my_location, onTap: onRecenter),

          const SizedBox(height: 20),

          // ── 줌 인 ─────────────────────────────────────────
          _MapCtrlBtn(icon: Icons.add, onTap: onZoomIn, bold: true),

          const SizedBox(height: 4),

          // ── 줌 슬라이더 (시각 요소) ─────────────────────────
          _ZoomTrackDivider(),

          const SizedBox(height: 4),

          // ── 줌 아웃 ───────────────────────────────────────
          _MapCtrlBtn(icon: Icons.remove, onTap: onZoomOut, bold: true),
        ],
      ),
    );
  }
}

/// 줌 +/- 사이의 점선 구분선
class _ZoomTrackDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1),
        color: AppColors.textHint.withValues(alpha: 0.35),
      ),
    );
  }
}

class _MapCtrlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool bold;

  const _MapCtrlBtn({
    required this.icon,
    required this.onTap,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.13),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: bold ? 22 : 20,
          color: AppColors.secondary,
          weight: bold ? 700 : 400,
        ),
      ),
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

class _PoiDot extends StatelessWidget {
  final Color color;
  const _PoiDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
          ],
        ),
      );
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

class _ClusterDot extends StatelessWidget {
  final Color color;
  final int count;
  const _ClusterDot({required this.color, required this.count});

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.88),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6),
          ],
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
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
                          subtitle: Text(
                              '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}',
                              style: const TextStyle(fontSize: 10)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => onRemoveFavorite(p.id),
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
    );
  }

  String _routeTitle(RecentRoute r) {
    final n = r.destName;
    if (n != null && n.trim().isNotEmpty) return n;
    return '→ ${r.destLat.toStringAsFixed(3)}, ${r.destLng.toStringAsFixed(3)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POI 탐색 시트 (13-1)
// ─────────────────────────────────────────────────────────────────────────────

class _PoiExploreSheet extends ConsumerStatefulWidget {
  final LatLng? origin;
  // 백그라운드 프리페치 캐시(5종 전체) — null이면 시트가 직접 조회(폴백).
  final List<Poi>? initialPois;
  final void Function(LatLng dest) onSelectDest;

  const _PoiExploreSheet({
    required this.origin,
    this.initialPois,
    required this.onSelectDest,
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

  /// 필터칩이 선택돼 있으면 그것들, 없으면(검색어가 있을 때만) 5종 전체, 둘 다 없으면 빈 집합.
  Set<PoiType> get _effectiveTypes {
    if (_selectedTypes.isNotEmpty) return Set<PoiType>.from(_selectedTypes);
    if (_searchCtrl.text.trim().isNotEmpty) return PoiType.values.toSet();
    return const {};
  }

  /// _allPois 중 현재 유효 카테고리에 속하는 것만(검색어 필터 전) — API 자체가
  /// 이 카테고리에 결과가 없는지, 검색어 때문에 줄었는지 구분해 안내 문구를 고르는 데 쓴다.
  List<Poi> get _typeFilteredPois {
    final types = _effectiveTypes;
    if (types.isEmpty) return const [];
    return _allPois.where((p) => types.contains(p.type)).toList();
  }

  void _onSearchChanged() {
    setState(() {});
    ref.read(poiListProvider.notifier).set(_visibleResults);
  }

  Future<void> _fetchAll() async {
    final origin = widget.origin;
    if (origin == null) return;
    final pois = await ref.read(poiServiceProvider).fetchPois(
          center: origin,
          radiusMeters: 1500,
          types: PoiType.values,
        );
    if (!mounted) return;
    pois.sort((a, b) => PoiService.haversineMeters(origin, a.location)
        .compareTo(PoiService.haversineMeters(origin, b.location)));
    setState(() {
      _allPois = pois;
      _loading = false;
    });
    ref.read(poiListProvider.notifier).set(_visibleResults);
  }

  void _toggleType(PoiType type) {
    setState(() {
      if (!_selectedTypes.add(type)) _selectedTypes.remove(type);
    });
    ref.read(poiListProvider.notifier).set(_visibleResults);
  }

  /// 검색어(있으면)로 클라이언트 필터링한 뒤 거리순으로 보여줄 목록.
  List<Poi> get _visibleResults {
    final byType = _typeFilteredPois;
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return byType;
    return byType.where((p) => p.name.toLowerCase().contains(query)).toList();
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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
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

              // ── 상호명 검색 ─────────────────────────────────────────────
              TextField(
                controller: _searchCtrl,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: '상호명으로 검색 (예: 스타벅스)',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 20),
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
              ),
              const SizedBox(height: 10),

              // ── 카테고리 필터 칩 ────────────────────────────────────────────
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final type in PoiType.values)
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
    );
  }

  Widget _buildBody() {
    final origin = widget.origin;
    if (origin == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('GPS 위치를 확인하는 중입니다',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
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
          onTap: () => widget.onSelectDest(poi.location),
        );
      }).toList(),
    );
  }
}

