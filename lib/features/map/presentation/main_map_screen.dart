import 'dart:async';
import 'dart:math' show cos, sqrt, asin;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/slider_start_button.dart';
import '../../../models/poi.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/map_cache_provider.dart';
import '../../../services/native_engine.dart';
import '../providers/map_providers.dart';
import '../../navigation/presentation/nav_screen.dart';

export 'main_map_screen.dart';

const LatLng kDefaultOrigin = LatLng(37.5665, 126.9780);

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
  LatLng _origin = kDefaultOrigin;
  StreamSubscription<Position>? _locationSub;
  double _currentZoom = 11.0;

  // Course sheet
  bool _showCourseSheet = false;

  // Touch overlay
  LatLng? _touchPoint;
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
  }

  @override
  void dispose() {
    _locationSub?.cancel();
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

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      final loc = LatLng(pos.latitude, pos.longitude);
      ref.read(currentLocationProvider.notifier).set(loc);
      setState(() => _origin = loc);
    });
  }

  void _recenterMap() =>
      _mapCtrl.move(_origin, _currentZoom.clamp(10.0, 14.0));

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
    final interaction = ref.read(mapInteractionProvider);
    if (interaction.isLoading) return;

    ref.read(mapInteractionProvider.notifier).setLoading(true);
    setState(() {
      _touchPoint = tapped;
      _touchDistKm = _haversineKm(_origin, tapped);
    });

    final poiSvc = ref.read(poiServiceProvider);
    try {
      final result = await poiSvc.snapDestination(
        origin: _origin,
        tapped: tapped,
        radiusKm: 1.0,
      );
      ref.read(poiListProvider.notifier).set(result.allPois);

      LatLng dest;
      if (result.snappedPoi != null) {
        dest = result.snappedPoi!.location;
        _showSnapToast(result.snappedPoi!);
      } else {
        final expand = await _showNoPoiDialog();
        if (!mounted) return;
        if (expand == true) {
          final r2 = await poiSvc.snapDestination(
            origin: _origin,
            tapped: tapped,
            radiusKm: 3.0,
          );
          ref.read(poiListProvider.notifier).set(r2.allPois);
          dest = r2.snappedPoi?.location ?? tapped;
          if (r2.snappedPoi != null) _showSnapToast(r2.snappedPoi!);
        } else {
          dest = tapped;
        }
      }
      _applyDestination(dest);
    } finally {
      if (mounted) {
        ref.read(mapInteractionProvider.notifier).setLoading(false);
      }
    }
  }

  void _applyDestination(LatLng dest) {
    final dist = _haversineKm(_origin, dest);
    ref.read(mapInteractionProvider.notifier).setDestination(dest, dist);

    final sw = LatLng(
      _origin.latitude < dest.latitude ? _origin.latitude : dest.latitude,
      _origin.longitude < dest.longitude
          ? _origin.longitude
          : dest.longitude,
    );
    final ne = LatLng(
      _origin.latitude > dest.latitude ? _origin.latitude : dest.latitude,
      _origin.longitude > dest.longitude
          ? _origin.longitude
          : dest.longitude,
    );
    _mapCtrl.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(sw, ne),
        padding: const EdgeInsets.fromLTRB(50, 110, 80, 260),
      ),
    );

    setState(() {
      _showCourseSheet = true;
      _touchPoint = null;
    });
    _sheetCtrl.forward();

    // 기본 선택 경로(국도)로 즉시 경로 계산 시작
    _onRouteCardSelect(
      ref.read(mapInteractionProvider).selectedRouteIdx,
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
  }

  void _startNavigation() {
    final state = ref.read(mapInteractionProvider);
    final dest = state.destination;
    if (dest == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NavScreen(
          destination: dest,
          waypoints: state.waypoints,
          routePolyline: state.routePolyline,
        ),
      ),
    );
  }

  Future<void> _onRouteCardSelect(int idx) async {
    final state = ref.read(mapInteractionProvider);
    final dest = state.destination;
    if (dest == null) return;

    ref.read(mapInteractionProvider.notifier).setSelectedRouteIdx(idx);
    ref.read(mapInteractionProvider.notifier).setLoading(true);

    try {
      final points = await NativeEngine.calcDummyRoute(
        origin: _origin,
        destination: dest,
        waypoints: state.waypoints,
        routeType: idx,
      );
      if (mounted) {
        ref.read(mapInteractionProvider.notifier).setRoutePolyline(points);
      }
    } finally {
      if (mounted) {
        ref.read(mapInteractionProvider.notifier).setLoading(false);
      }
    }
  }

  // ── Toasts / Dialogs ──────────────────────────────────────────────────────

  void _showSnapToast(Poi poi) {
    final msg = poi.type == PoiType.cafe
        ? '근처 카페로 목적지를 조정했어요'
        : '근처 편의점으로 목적지를 조정했어요';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            poi.type == PoiType.cafe ? Icons.local_cafe : Icons.store,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: AppTextStyles.bodyMD.copyWith(color: Colors.white))),
        ]),
        backgroundColor: AppColors.primary,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool?> _showNoPoiDialog() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            const Icon(Icons.search_off, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('쉴 곳을 못 찾았어요',
                style: AppTextStyles.headlineMD),
          ]),
          content: Text(
            '목적지 근처에 카페나 편의점이 없어요.\n범위를 넓혀 찾아볼까요?',
            style: AppTextStyles.bodyMD,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('이대로'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('범위 넓혀 찾기'),
            ),
          ],
        ),
      );

  // ── POI markers ───────────────────────────────────────────────────────────

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
    final pois = ref.watch(poiListProvider);
    final dest = interaction.destination;
    final waypoint = interaction.waypoint;
    final routePolyline = interaction.routePolyline;
    final selectedRouteIdx = interaction.selectedRouteIdx;
    final isOnline = ref.watch(isOnlineProvider);
    final riderMode = ref.watch(riderModeProvider);

    // Theme-adaptive colors for map overlays.
    final routeColor =
        riderMode ? RiderModeColors.mapRoute : AppColors.primary;
    final originColor =
        riderMode ? RiderModeColors.mapOrigin : AppColors.mapOrigin;
    final destColor =
        riderMode ? RiderModeColors.mapDestination : AppColors.mapDestination;

    return Scaffold(
      backgroundColor:
          riderMode ? RiderModeColors.background : AppColors.background,
      body: Stack(
        children: [
          // ══════════════════════════════════════════════════════
          // LAYER 1 · OSM Map
          // ══════════════════════════════════════════════════════
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _origin,
              initialZoom: _currentZoom,
              // Disable rotation: lock North-up for motorcycle mount
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: _onMapTap,
              onMapEvent: (event) {
                if (event is MapEventMoveEnd) {
                  setState(() => _currentZoom = _mapCtrl.camera.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yurunavi.app',
                maxZoom: 19,
                tileProvider: buildCachedTileProvider(),
              ),

              // ── ZOOM TIER 1 (any zoom): route polyline ──────────────
              // Always rendered — it's the primary navigation element.
              // Stroke widens as the rider zooms in for precision.
              // In rider mode the stroke is thicker for glove-hand legibility.
              if (routePolyline.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: routePolyline,
                    color: routeColor.withValues(alpha: 0.92),
                    strokeWidth: riderMode
                        ? (_currentZoom >= 13 ? 9.0 : _currentZoom >= 10.5 ? 7.0 : 5.0)
                        : (_currentZoom >= 13 ? 6.0 : _currentZoom >= 10.5 ? 4.0 : 3.0),
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ]),

              // ── ZOOM TIER 2 (zoom ≥ 10.5): POI clusters ────────────
              // Hide all POI detail at wide view — only the route matters
              // at motorway speeds. Clusters appear once the rider slows.
              if (pois.isNotEmpty && _currentZoom >= 10.5)
                MarkerLayer(markers: _buildPoiMarkers(pois)),

              // ── ZOOM TIER 3 (zoom ≥ 13): detail overlays ───────────
              // Tap-radius circle and destination radius only at street
              // level; at wide zoom they cover too much of the screen.
              if (_touchPoint != null && _currentZoom >= 13)
                CircleLayer(circles: [
                  CircleMarker(
                    point: _origin,
                    radius: _touchDistKm * 1000,
                    useRadiusInMeter: true,
                    color:
                        AppColors.secondary.withValues(alpha: 0.06),
                    borderColor:
                        AppColors.secondary.withValues(alpha: 0.35),
                    borderStrokeWidth: 1.2,
                  ),
                ]),

              if (dest != null && _currentZoom >= 10.5)
                CircleLayer(circles: [
                  CircleMarker(
                    point: _origin,
                    radius: interaction.distanceKm * 1000,
                    useRadiusInMeter: true,
                    color: AppColors.mapOrigin.withValues(alpha: 0.05),
                    borderColor:
                        AppColors.mapOrigin.withValues(alpha: 0.25),
                    borderStrokeWidth: 1.0,
                  ),
                ]),

              // Origin + destination + waypoint markers
              // Origin dot is always visible; dest/waypoint pins shown
              // only at zoom ≥ 10.5 where they are legible.
              // Rider mode: markers scale up for glove-friendly visibility.
              MarkerLayer(markers: [
                Marker(
                  point: _origin,
                  width: riderMode ? 28 : 22,
                  height: riderMode ? 28 : 22,
                  child: _OriginMarker(color: originColor),
                ),
                if (waypoint != null && _currentZoom >= 10.5)
                  Marker(
                    point: waypoint,
                    width: riderMode ? 48 : 36,
                    height: riderMode ? 48 : 36,
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_pin,
                        color: riderMode
                            ? RiderModeColors.tertiary
                            : const Color(0xFFFFB300),
                        size: riderMode ? 48 : 36),
                  ),
                if (dest != null && _currentZoom >= 10.5)
                  Marker(
                    point: dest,
                    width: riderMode ? 48 : 36,
                    height: riderMode ? 48 : 36,
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_pin,
                        color: destColor,
                        size: riderMode ? 48 : 36),
                  ),
              ]),
            ],
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
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('좋은 장소를 찾고 있어요…',
                              style: AppTextStyles.bodyMD),
                        ]),
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
                onSavedCourses: () {},
                onSettings: () {},
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
                onZoomIn: () => _mapCtrl.move(
                  _mapCtrl.camera.center,
                  (_mapCtrl.camera.zoom + 1).clamp(1.0, 19.0),
                ),
                onZoomOut: () => _mapCtrl.move(
                  _mapCtrl.camera.center,
                  (_mapCtrl.camera.zoom - 1).clamp(1.0, 19.0),
                ),
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
                    label: '경유지 추가',
                    color: const Color(0xFFFFB300),
                    onTap: () {
                      if (_touchPoint != null) {
                        ref
                            .read(mapInteractionProvider.notifier)
                            .setWaypoint(_touchPoint!);
                        setState(() => _touchPoint = null);
                      }
                    },
                  ),
                  const SizedBox(width: 10),
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
          // LAYER 7 · Bottom area (course sheet + ad banner)
          // ══════════════════════════════════════════════════════
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Course selection sheet (슬라이드 업)
                if (_showCourseSheet)
                  SlideTransition(
                    position: _sheetSlide,
                    child: _CourseSheet(
                      distanceKm: interaction.distanceKm,
                      selectedIdx: selectedRouteIdx,
                      onSelect: _onRouteCardSelect,
                      onStart: _startNavigation,
                      onClose: _clearDestination,
                    ),
                  ),
                // Ad banner
                const _AdBanner(),
              ],
            ),
          ),
        ],
      ),
    );
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
    return Image.asset(
      'assets/images/yuru_2line.jpeg',
      height: 40,
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
    final daylightProgress = ref.watch(daylightProgressProvider);
    final daylightTimes = ref.watch(daylightTimesProvider);

    final sunriseLabel = daylightTimes != null
        ? DateFormat('HH:mm').format(daylightTimes.bmnt)
        : '--:--';
    final sunsetLabel = daylightTimes != null
        ? DateFormat('HH:mm').format(daylightTimes.eent)
        : '--:--';

    // 코스 시트가 올라왔을 때 패널 하단 여유 조절
    final bottomPad = showCourseSheet ? 220.0 : 60.0;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad, top: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── 일출 ───────────────────────────────────────────
          _DaylightLabel(
            icon: Icons.wb_sunny_rounded,
            label: sunriseLabel,
            color: AppColors.sunrise,
          ),

          const SizedBox(height: 4),

          // ── Daylight 게이지 바 ─────────────────────────────
          Flexible(
            child: _DaylightTrack(progress: daylightProgress),
          ),

          const SizedBox(height: 4),

          // ── 일몰 ───────────────────────────────────────────
          _DaylightLabel(
            icon: Icons.nightlight_round,
            label: sunsetLabel,
            color: AppColors.sunset,
            iconFirst: false,
          ),

          const SizedBox(height: 14),

          // ── 나침반 (GPS 복귀) ──────────────────────────────
          _MapCtrlBtn(icon: Icons.explore_outlined, onTap: onRecenter),

          const SizedBox(height: 8),

          // ── 줌 인 ─────────────────────────────────────────
          _MapCtrlBtn(icon: Icons.add, onTap: onZoomIn, bold: true),

          const SizedBox(height: 2),

          // ── 줌 슬라이더 (시각 요소) ─────────────────────────
          _ZoomTrackDivider(),

          const SizedBox(height: 2),

          // ── 줌 아웃 ───────────────────────────────────────
          _MapCtrlBtn(icon: Icons.remove, onTap: onZoomOut, bold: true),
        ],
      ),
    );
  }
}

class _DaylightLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool iconFirst;

  const _DaylightLabel({
    required this.icon,
    required this.label,
    required this.color,
    this.iconFirst = true,
  });

  @override
  Widget build(BuildContext context) {
    final iconW = Icon(icon, size: 16, color: color);
    final labelW = Text(
      label,
      style: AppTextStyles.labelSM.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 8),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: iconFirst
          ? [iconW, const SizedBox(height: 1), labelW]
          : [labelW, const SizedBox(height: 1), iconW],
    );
  }
}

/// 세로 그라디언트 트랙 + 현재 위치 핸들
class _DaylightTrack extends StatelessWidget {
  final double progress;
  const _DaylightTrack({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      constraints: const BoxConstraints(minHeight: 80),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalH = constraints.maxHeight;
          final handleY = (totalH * progress.clamp(0.0, 1.0)) - 8;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 그라디언트 트랙
              Container(
                width: 10,
                height: totalH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFD54F),
                      Color(0xFFFFB300),
                      Color(0xFF90CAF9),
                      Color(0xFF3949AB),
                    ],
                    stops: [0.0, 0.4, 0.72, 1.0],
                  ),
                ),
              ),

              // 현재 위치 핸들 (주황 테두리 흰 원)
              Positioned(
                top: handleY.clamp(0.0, totalH - 16),
                left: -5,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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
  final double distanceKm;
  final int selectedIdx;
  final ValueChanged<int> onSelect;
  final VoidCallback onStart;
  final VoidCallback onClose;

  const _CourseSheet({
    required this.distanceKm,
    required this.selectedIdx,
    required this.onSelect,
    required this.onStart,
    required this.onClose,
  });

  static const _routes = [
    _RouteInfo('시골길로\n느긋하게', 1.55, 38, AppColors.mapCourse),
    _RouteInfo('지방도로\n여유롭게', 1.22, 52, AppColors.tertiary),
    _RouteInfo('국도로\n빠르게', 1.0, 68, AppColors.primary),
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

          // 닫기 버튼 (우측)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 14, 0),
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
                final dist = distanceKm * r.multiplier;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 5,
                      right: i == 2 ? 0 : 5,
                    ),
                    child: _RouteCard(
                      info: r,
                      distKm: dist,
                      duration: _dur(dist, r.avgKmh),
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

  String _dur(double km, double avgKmh) {
    final m = (km / avgKmh * 60).round();
    final h = m ~/ 60;
    final min = m % 60;
    return h > 0 ? '$h시간 $min분' : '$min분';
  }
}

class _RouteInfo {
  final String label;
  final double multiplier;
  final double avgKmh;
  final Color color;
  const _RouteInfo(this.label, this.multiplier, this.avgKmh, this.color);
}

class _RouteCard extends StatelessWidget {
  final _RouteInfo info;
  final double distKm;
  final String duration;
  final bool isSelected;
  final VoidCallback onTap;

  const _RouteCard({
    required this.info,
    required this.distKm,
    required this.duration,
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
              '${distKm.toStringAsFixed(0)}km',
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
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ad Banner  (와이어프레임: 살구색 배경 + "Ads" 텍스트)
// ─────────────────────────────────────────────────────────────────────────────

class _AdBanner extends StatelessWidget {
  const _AdBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      color: const Color(0xFFFFDFC4), // 살구색 (와이어프레임 일치)
      alignment: Alignment.center,
      child: Text(
        'Ads',
        style: AppTextStyles.labelMD.copyWith(
          color: const Color(0xFFB08060),
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map markers
// ─────────────────────────────────────────────────────────────────────────────

class _OriginMarker extends StatelessWidget {
  final Color color;
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
