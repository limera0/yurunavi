import 'dart:async';
import 'dart:math' show cos, sqrt, asin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator, rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/daylight_bar.dart';
import '../../../core/widgets/slider_start_button.dart';
import '../../../models/map_language.dart';
import '../../../models/poi.dart';
import '../../../models/saved_place.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/map_cache_provider.dart'; // ignore: unused_import
import '../../../services/native_engine.dart';
import '../../../services/routing_service.dart';
import '../providers/map_providers.dart';
import '../style_language_transform.dart';
import '../../navigation/presentation/nav_screen.dart';
import '../../navigation/providers/nav_state_provider.dart';
import '../../settings/providers/settings_providers.dart';
import '../../settings/presentation/settings_screen.dart';

export 'main_map_screen.dart';

enum _TapAction { destination, waypoint }

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

  ml.Circle? _locMarker;
  ml.Symbol? _destMarker;
  List<ml.Symbol> _waypointMarkers = [];
  static const String _kLocColor = '#00C853';
  static const String _kDestIcon = 'pointer_red';
  static const double _kDestIconSize = 1.5; // 폰 실측: 3x 적용
  static const String _kWpIcon = 'pointer_yellow';
  static const double _kWpIconSize = 1.5; // 96px PNG, 폰 실측으로 조정

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
        _ensureLocationMarker(); // unawaited — B1
      },
      fireImmediately: true,
    );
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
    // 경로선을 circle 마커 레이어 아래에 삽입하기 위해 circle layer id 산출
    final circleLyr = ctrl.circleManager?.layerIds.isNotEmpty == true
        ? ctrl.circleManager!.layerIds.first
        : null;
    debugPrint('[zorder] circleLyr=$circleLyr');
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
      belowLayerId: circleLyr,
    );
    // selected route layer (above bg)
    await ctrl.addGeoJsonSource(_routeSourceId, _buildRouteGeoJson([]));
    await ctrl.addLineLayer(
      _routeSourceId,
      _routeLayerId,
      const ml.LineLayerProperties(
        lineColor: '#1E5AFF',
        lineWidth: 6.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: circleLyr,
    );
  }

  // ── Marker helpers (B1/B2) ────────────────────────────────────────────────

  Future<void> _ensureLocationMarker() async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded) return;
    final p = _origin ?? _lastKnown;
    if (p == null) return;
    final geo = _toMl(p);
    if (_locMarker == null) {
      _locMarker = await c.addCircle(ml.CircleOptions(
        geometry: geo,
        circleRadius: 8,
        circleColor: _kLocColor,
        circleStrokeWidth: 3,
        circleStrokeColor: '#FFFFFF',
      ));
    } else {
      await c.updateCircle(_locMarker!, ml.CircleOptions(geometry: geo));
    }
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

    // 경로가 표시 중이면 도착지변경 vs 경유지추가 선택 시트 표시
    if (_showCourseSheet) {
      final action = await _showTapActionSheet(tapped);
      if (!mounted) return;
      if (action == _TapAction.waypoint) {
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
      if (action != _TapAction.destination) return; // cancelled
    }

    setState(() {
      _touchPoint = tapped;
      _touchDistKm = _haversineKm(origin, tapped);
    });
    _applyDestination(tapped);
  }

  Future<_TapAction?> _showTapActionSheet(LatLng tapped) {
    return showModalBottomSheet<_TapAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
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
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Color(0xFF008080)),
                title: const Text('도착지 변경'),
                onTap: () => Navigator.pop(context, _TapAction.destination),
              ),
              ListTile(
                leading: const Icon(Icons.add_location_alt_outlined, color: Color(0xFF008080)),
                title: const Text('경유지 추가'),
                subtitle: const Text('현재 경로에 경유지를 삽입합니다',
                    style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(context, _TapAction.waypoint),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _applyDestination(LatLng dest) {
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
      ref.read(recentRoutesProvider.notifier).add(RecentRoute(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            originLat: origin.latitude,
            originLng: origin.longitude,
            destLat: dest.latitude,
            destLng: dest.longitude,
            at: DateTime.now(),
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
    final pois = ref.watch(poiListProvider); // ignore: unused_local_variable
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
              _locMarker = null;
              _destMarker = null;
              _waypointMarkers = <ml.Symbol>[];
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
              await _mlCtrl!.setSymbolIconAllowOverlap(true);
              // B1: 현위치 마커 — 경로 레이어 위에 그려지도록 마지막에 추가
              await _ensureLocationMarker();
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
            },
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
                    child: _CourseSheet(
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

  const _MapHeader({
    required this.riderMode,
    required this.onRiderModeToggle,
    required this.onCourseRegister,
    required this.onTourSummary,
    required this.onSavedCourses,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = riderMode
        ? RiderModeColors.surface.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);

    return Container(
      color: bgColor,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
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

  const _MapCtrlBtn({required this.icon, required this.onTap, this.bold = false});

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
// Course Selection Sheet
// 와이어프레임: 카드 3개 → [Start your Engine 슬라이더]
// ─────────────────────────────────────────────────────────────────────────────

class _CourseSheet extends StatelessWidget {
  final List<({double km, int mins, double windingScore})> routeMeta;
  final int selectedIdx;
  final ValueChanged<int> onSelect;
  final VoidCallback onStart;
  final VoidCallback onClose;

  const _CourseSheet({
    required this.routeMeta,
    required this.selectedIdx,
    required this.onSelect,
    required this.onStart,
    required this.onClose,
  });

  static const _routes = [
    _RouteInfo('시골길로\n느긋하게', AppColors.mapCourse),
    _RouteInfo('지방도로\n여유롭게', AppColors.tertiary),
    _RouteInfo('국도로\n빠르게', AppColors.primary),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 닫기 버튼 행 (우측)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onClose,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(0, 0, 14, 0),
                child: Icon(Icons.close_rounded,
                    size: 20, color: AppColors.textHint),
              ),
            ),
          ),

          // 3가지 경로 카드
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Row(
              children: List.generate(_routes.length, (i) {
                final r = _routes[i];
                final hasMeta = routeMeta.length > i;
                final distKm = hasMeta ? routeMeta[i].km : 0.0;
                final mins = hasMeta ? routeMeta[i].mins : 0;
                final ws = hasMeta ? routeMeta[i].windingScore : 0.0;
                final distStr = hasMeta ? '${distKm.toStringAsFixed(0)}km' : '---';
                final durStr = hasMeta ? _durFromMins(mins) : '---';
                // best fun score among loaded routes
                final bestWs = routeMeta.isEmpty ? 0.0
                    : routeMeta.map((m) => m.windingScore).reduce((a, b) => a > b ? a : b);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 5,
                      right: i == 2 ? 0 : 5,
                    ),
                    child: _RouteCard(
                      info: r,
                      distStr: distStr,
                      duration: durStr,
                      windingScore: ws,
                      isBestFun: hasMeta && ws >= bestWs && ws > 0,
                      isSelected: selectedIdx == i,
                      onTap: () => onSelect(i),
                    ),
                  ),
                );
              }),
            ),
          ),

          // Start your Engine 슬라이더
          SliderStartButton(onSlideComplete: onStart),
        ],
      ),
    );
  }

  String _durFromMins(int m) {
    final h = m ~/ 60;
    final min = m % 60;
    return h > 0 ? '$h시간 $min분' : '$min분';
  }
}

class _RouteInfo {
  final String label;
  final Color color;
  const _RouteInfo(this.label, this.color);
}

class _RouteCard extends StatelessWidget {
  final _RouteInfo info;
  final String distStr;
  final String duration;
  final double windingScore;
  final bool isBestFun;
  final bool isSelected;
  final VoidCallback onTap;

  const _RouteCard({
    required this.info,
    required this.distStr,
    required this.duration,
    this.windingScore = 0.0,
    this.isBestFun = false,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = info.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.09) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.textHint.withValues(alpha: 0.28),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              info.label,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelMD.copyWith(
                color: isSelected ? color : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              distStr,
              style: AppTextStyles.titleSM.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            Text(
              duration,
              style: AppTextStyles.labelSM.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
            if (windingScore > 0)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isBestFun
                        ? info.color.withValues(alpha: 0.15)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isBestFun
                        ? '★ 재미 ${windingScore.toStringAsFixed(0)}'
                        : '재미 ${windingScore.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: isBestFun ? FontWeight.w700 : FontWeight.w400,
                      color: isBestFun ? info.color : AppColors.textHint,
                    ),
                  ),
                ),
              ),
          ],
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
                              '→ ${r.destLat.toStringAsFixed(3)}, ${r.destLng.toStringAsFixed(3)}',
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
}

