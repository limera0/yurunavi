import 'dart:async';
import 'dart:math' show sin, cos, sqrt, asin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/widgets/daylight_bar.dart';
import '../../../services/routing_service.dart';
import '../../map/providers/map_providers.dart';

/// Camera-framing default only — never treated as the rider's location.
/// The real position arrives from the GPS stream below.
const LatLng _kInitialMapView = LatLng(37.5665, 126.9780);

class NavScreen extends ConsumerStatefulWidget {
  final LatLng? destination;
  final List<LatLng> waypoints;
  final List<LatLng> routePolyline;
  final List<ManeuverStep> maneuvers;

  const NavScreen({
    super.key,
    this.destination,
    this.waypoints = const [],
    this.routePolyline = const [],
    this.maneuvers = const [],
  });

  @override
  ConsumerState<NavScreen> createState() => _NavScreenState();
}

class _NavScreenState extends ConsumerState<NavScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  // Nullable until the first real GPS fix arrives — prevents the position
  // marker from rendering at a hardcoded mock location.
  LatLng? _currentPos;
  double _speedKmh = 0;
  bool _isManualMode = false;
  Timer? _recenterTimer;
  StreamSubscription<Position>? _locationSub;

  // 속도계 노이즈 제거
  final _speedBuffer = <double>[];
  static const _kBufSize = 3; // 이동평균 샘플 수
  DateTime? _lastSpeedAt; // 적응 갱신 타이밍

  // 도착 감지
  bool _arrived = false;
  static const _kArrivalRadiusM = 30.0; // 목적지 도달 판정 반경

  // 속도 연동 줌
  double _navZoom = 15.0; // 현재 보간 중인 줌 레벨

  // 이탈 재탐색
  List<LatLng> _routePoints = []; // widget.routePolyline 의 가변 복사본
  bool _isRerouting = false;
  Timer? _offRouteDebounce;
  static const _kOffRouteM = 20.0; // 이탈 판정 거리 (미터)
  static const _kDebounceSec = 3;  // 연속 이탈 확인 시간 (초)

  late final List<_TurnStep> _steps; // Valhalla maneuvers 또는 더미 폴백
  int _stepIdx = 0;

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
    // Valhalla maneuvers → _TurnStep 변환 (없으면 더미 폴백)
    _steps = widget.maneuvers.isNotEmpty
        ? widget.maneuvers.map(_TurnStep.fromManeuver).toList()
        : const [
            _TurnStep(Icons.play_arrow_rounded, '경로 안내 시작', ''),
            _TurnStep(Icons.straight_rounded,   '직진',         ''),
            _TurnStep(Icons.flag_rounded,        '목적지 도착',  ''),
          ];
    if (widget.destination == null) {
      // 목적지 없이 진입하면 즉시 빠져나간다
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _startLocation();
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.dark,
    ));
    _recenterTimer?.cancel();
    _offRouteDebounce?.cancel();
    _locationSub?.cancel();
    _pulseCtrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // 모든 이벤트 수신; 속도 갱신은 내부에서 적응 조절
      ),
    ).listen(_onPosition);
  }

  void _onPosition(Position pos) {
    final loc = LatLng(pos.latitude, pos.longitude);
    ref.read(currentLocationProvider.notifier).set(loc);
    if (!_isManualMode) _recenter(loc);

    final now = DateTime.now();
    // 적응 갱신: ≤10 km/h → 2Hz(500ms), 나머지 → 1Hz(1000ms)
    final intervalMs = _speedKmh <= 10.0 ? 500 : 1000;
    final elapsedMs = _lastSpeedAt == null
        ? intervalMs
        : now.difference(_lastSpeedAt!).inMilliseconds;

    if (elapsedMs < intervalMs) {
      setState(() => _currentPos = loc);
      return;
    }
    _lastSpeedAt = now;

    // 데드존: GPS 노이즈 < 2.5 km/h 또는 정확도 불량(>20m) → 0 처리
    final rawKmh = (pos.speed.isNaN || pos.speed < 0) ? 0.0 : pos.speed * 3.6;
    final clamped = (rawKmh < 2.5 || pos.accuracy > 20.0) ? 0.0 : rawKmh;

    // 이동평균으로 튐 완화
    _speedBuffer.add(clamped);
    if (_speedBuffer.length > _kBufSize) _speedBuffer.removeAt(0);
    final avg = _speedBuffer.reduce((a, b) => a + b) / _speedBuffer.length;

    setState(() {
      _currentPos = loc;
      _speedKmh = avg < 2.0 ? 0.0 : avg; // 평균에도 최종 데드존 적용
    });

    _checkArrival(loc);
    if (!_arrived && _routePoints.length >= 2) _checkOffRoute(loc);
  }

  void _checkOffRoute(LatLng loc) {
    if (_isRerouting) return;
    var minDist = double.maxFinite;
    for (int i = 0; i < _routePoints.length - 1; i++) {
      final d = _segmentDistM(loc, _routePoints[i], _routePoints[i + 1]);
      if (d < minDist) minDist = d;
    }
    if (minDist > _kOffRouteM) {
      // 디바운스: 3초 연속 이탈 확인 후 재탐색
      _offRouteDebounce ??= Timer(const Duration(seconds: _kDebounceSec), () {
        _offRouteDebounce = null;
        // 타이머 발화 시점의 현재 위치로 재탐색 (생성 시점 loc보다 최신)
        final current = _currentPos;
        if (current != null) _reroute(current);
      });
    } else {
      _offRouteDebounce?.cancel();
      _offRouteDebounce = null;
    }
  }

  // 점-선분 최단거리 (미터)
  double _segmentDistM(LatLng p, LatLng a, LatLng b) {
    final ax = b.latitude - a.latitude;
    final ay = b.longitude - a.longitude;
    final lenSq = ax * ax + ay * ay;
    final t = lenSq < 1e-12
        ? 0.0
        : (((p.latitude - a.latitude) * ax + (p.longitude - a.longitude) * ay) / lenSq)
            .clamp(0.0, 1.0);
    return _distanceM(
      LatLng(a.latitude + t * ax, a.longitude + t * ay),
      p,
    );
  }

  Future<void> _reroute(LatLng origin) async {
    if (_isRerouting || !mounted) return;
    final dest = widget.destination;
    if (dest == null) return;
    setState(() => _isRerouting = true);
    try {
      final routes = await RoutingService.fetchRoutes(
        origin: origin,
        destination: dest,
        waypoints: widget.waypoints,
      );
      if (mounted && routes.isNotEmpty) setState(() => _routePoints = routes[0].points);
    } on RoutingException {
      // 재탐색 실패 — 기존 경로 유지
    } finally {
      if (mounted) setState(() => _isRerouting = false);
    }
  }

  void _checkArrival(LatLng loc) {
    if (_arrived) return;
    final dest = widget.destination;
    if (dest == null) return;
    if (_distanceM(loc, dest) <= _kArrivalRadiusM) {
      _arrived = true;
      _showArrivalDialog();
    }
  }

  double _distanceM(LatLng a, LatLng b) {
    const r = 6371000.0;
    const deg2rad = 0.017453292519943295;
    final lat1 = a.latitude * deg2rad;
    final lat2 = b.latitude * deg2rad;
    final dLat = (b.latitude - a.latitude) * deg2rad;
    final dLon = (b.longitude - a.longitude) * deg2rad;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(sqrt(h));
  }

  void _showArrivalDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.flag_rounded, color: Color(0xFF008080)),
          SizedBox(width: 8),
          Text('도착했습니다!'),
        ]),
        content: const Text('목적지에 도착했습니다.\n내비게이션을 종료합니다.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // 다이얼로그 닫기
              if (mounted) Navigator.of(context).pop(); // 내비 화면 종료 → 홈
            },
            child: const Text('확인'),
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

  void _recenter(LatLng loc) {
    final target = _zoomForSpeed(_speedKmh);
    // GPS 이벤트당 최대 0.5레벨씩 부드럽게 수렴
    final diff = target - _navZoom;
    _navZoom += diff.clamp(-0.5, 0.5);
    _mapCtrl.move(loc, _navZoom);
  }

  void _onMapGesture() {
    setState(() => _isManualMode = true);
    _recenterTimer?.cancel();
    _recenterTimer = Timer(const Duration(seconds: 10), () {
      final pos = _currentPos;
      setState(() => _isManualMode = false);
      if (pos != null) _recenter(pos);
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_stepIdx];
    final daylightCycle = ref.watch(daylightCycleProvider);
    final daylightProgress = daylightCycle?.progress ?? 0.5;
    final isDay = daylightCycle?.isDay ?? true;
    final cs = Theme.of(context).colorScheme;
    final routeKm = _polylineKm(widget.routePolyline);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // ── 지도 ────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _currentPos ?? _kInitialMapView,
              initialZoom: 15,
              // Lock north-up: rotation gestures during pinch-zoom were
              // disorienting riders on the bar mount.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapEvent: (event) {
                if (event is MapEventMoveStart && event.source != MapEventSource.mapController) {
                  _onMapGesture();
                }
              },
            ),
            children: [
              // OSM standard tiles — readable at all times of day.
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.westinx.yurunavi',
                maxZoom: 19,
              ),
              // 경로 폴리라인 (_routePoints: 재탐색 시 자동 갱신)
              if (_routePoints.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _routePoints,
                    color: const Color(0xFFF28C28).withValues(alpha: 0.9),
                    strokeWidth: 4.5,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ]),

              MarkerLayer(markers: [
                // 현위치 — only after a real GPS fix arrives.
                if (_currentPos != null)
                  Marker(
                    point: _currentPos!,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.tertiary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(color: cs.tertiary.withValues(alpha: 0.5), blurRadius: 12),
                        ],
                      ),
                    ),
                  ),
                // 경유지
                ...widget.waypoints.map(
                  (wp) => Marker(
                    point: wp,
                    width: 34,
                    height: 34,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_pin,
                      color: Color(0xFFFFB300),
                      size: 34,
                    ),
                  ),
                ),
                // 목적지
                if (widget.destination != null)
                  Marker(
                    point: widget.destination!,
                    width: 38,
                    height: 38,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_pin, color: Colors.redAccent, size: 38),
                  ),
              ]),
            ],
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

          // ── 상단 회전 안내 ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: GestureDetector(
                onTap: () {
                  if (_stepIdx < _steps.length - 1) setState(() => _stepIdx++);
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
                                child: Icon(step.icon, color: Colors.white, size: 30),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (step.dist.isNotEmpty)
                                      Text(
                                        step.dist,
                                        style: TextStyle(
                                          color: cs.tertiary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    Text(
                                      step.label,
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
              child: _Speedometer(speedKmh: _speedKmh),
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
                    final pos = _currentPos;
                    if (pos == null) return;
                    _recenterTimer?.cancel();
                    setState(() => _isManualMode = false);
                    _recenter(pos);
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
                              '14:32 도착',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                Text('38분', style: TextStyle(color: cs.tertiary, fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                Text(routeKm > 0 ? '${routeKm.toStringAsFixed(1)}km' : '--', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: cs.outline, margin: const EdgeInsets.symmetric(horizontal: 16)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
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
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Speedometer extends StatelessWidget {
  final double speedKmh;
  const _Speedometer({required this.speedKmh});

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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            speedKmh.toStringAsFixed(0),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.tertiary, height: 1.0),
          ),
          Text('km/h', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _NavIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavIconBtn({required this.icon, required this.onTap});

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
  const _TurnStep(this.icon, this.label, this.dist);

  factory _TurnStep.fromManeuver(ManeuverStep m) {
    return _TurnStep(
      _iconForType(m.type),
      _labelForType(m.type),
      _formatDist(m.distanceKm),
    );
  }

  static IconData _iconForType(int type) {
    switch (type) {
      case 1: case 2: case 3: return Icons.play_arrow_rounded;
      case 4: case 5: case 6: return Icons.flag_rounded;
      case 8: return Icons.straight_rounded;
      case 9: case 17: return Icons.turn_slight_right;
      case 10: case 25: return Icons.turn_right_rounded;
      case 11: return Icons.turn_right_rounded; // sharp right
      case 12: case 13: return Icons.u_turn_right_rounded;
      case 14: return Icons.turn_left_rounded;  // sharp left
      case 15: case 26: return Icons.turn_left_rounded;
      case 16: case 18: return Icons.turn_slight_left;
      default: return Icons.straight_rounded;
    }
  }

  static String _labelForType(int type) {
    switch (type) {
      case 1: case 2: case 3: return '출발';
      case 4: case 5: case 6: return '목적지 도착';
      case 7: return '도로명 변경';
      case 8: return '직진';
      case 9: return '약간 우회전';
      case 10: return '우회전';
      case 11: return '급우회전';
      case 12: case 13: return '유턴';
      case 14: return '급좌회전';
      case 15: return '좌회전';
      case 16: return '약간 좌회전';
      case 17: return '진출로 직진';
      case 25: return '진출로 우측';
      case 26: return '진출로 좌측';
      case 27: return '우측 출구';
      case 28: return '좌측 출구';
      default: return '직진';
    }
  }

  static String _formatDist(double km) {
    if (km <= 0) return '';
    if (km < 1.0) return '${(km * 1000).round()}m';
    return '${km.toStringAsFixed(1)}km';
  }
}
