import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../features/map/providers/map_providers.dart';
import '../core/widgets/daylight_bar.dart';

/// Camera-framing default only — never treated as the rider's location.
/// The real position arrives from the GPS stream below.
const LatLng kInitialMapView = LatLng(37.5665, 126.9780);

// ── 다크 모드 색상 팔레트 ─────────────────────────────────────
const _kBg          = Color(0xFF0D0D0D);
const _kSurface2    = Color(0xFF242424);
const _kAccent      = Color(0xFF00BFAE);  // 틸 강조
const _kTextPrimary = Color(0xFFF0F0F0);
const _kTextSub     = Color(0xFF888888);
const _kCard        = Color(0xFF1E1E1E);

class DrivingScreen extends ConsumerStatefulWidget {
  final LatLng? destination;
  const DrivingScreen({super.key, this.destination});

  @override
  ConsumerState<DrivingScreen> createState() => _DrivingScreenState();
}

class _DrivingScreenState extends ConsumerState<DrivingScreen>
    with SingleTickerProviderStateMixin {

  final MapController _mapCtrl = MapController();
  // Nullable until the device returns a real GPS fix.
  LatLng? _currentPos;
  double _speedKmh = 0;
  bool _isManualMode = false;
  Timer? _autoRecenterTimer;
  static const _recenterDelay = Duration(seconds: 15);
  StreamSubscription<Position>? _locationSub;

  final List<_TurnStep> _steps = const [
    _TurnStep(icon: Icons.turn_right_rounded, text: '300m 후 우회전', road: '강남대로', distLabel: '300m'),
    _TurnStep(icon: Icons.straight_rounded,   text: '1.2km 직진',    road: '테헤란로', distLabel: '1.2km'),
    _TurnStep(icon: Icons.turn_left_rounded,  text: '500m 후 좌회전', road: '영동대로', distLabel: '500m'),
    _TurnStep(icon: Icons.flag_rounded,       text: '목적지 도착',    road: '',        distLabel: ''),
  ];
  int _stepIndex = 0;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    // 주행 화면 진입 시 상태바를 투명으로 — 몰입감 극대화
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _startLocationTracking();
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    _autoRecenterTimer?.cancel();
    _locationSub?.cancel();
    _pulseCtrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    bool svcEnabled = await Geolocator.isLocationServiceEnabled();
    if (!svcEnabled) return;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final loc = LatLng(pos.latitude, pos.longitude);
      ref.read(currentLocationProvider.notifier).set(loc);
      // Raw device speed (m/s) → km/h. Defaults to 0 when stationary,
      // negative or NaN. No simulator override.
      final raw = pos.speed;
      final kmh = (raw.isNaN || raw <= 0) ? 0.0 : raw * 3.6;
      setState(() {
        _currentPos = loc;
        _speedKmh = kmh;
      });
      if (!_isManualMode) _recenter(loc);
    });
  }

  void _onCameraMove(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    setState(() => _isManualMode = true);
    _autoRecenterTimer?.cancel();
    _autoRecenterTimer = Timer(_recenterDelay, () {
      final pos = _currentPos;
      setState(() => _isManualMode = false);
      if (pos != null) _recenter(pos);
    });
  }

  void _recenter(LatLng loc) {
    _mapCtrl.move(loc, 15.0);
  }

  void _nextStep() {
    if (_stepIndex < _steps.length - 1) {
      setState(() => _stepIndex++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_stepIndex];
    final daylightProgress = ref.watch(daylightProgressProvider);
    final daylightTimes = ref.watch(daylightTimesProvider);
    final safeTop = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // ── OSM 지도 (다크 틸트 스타일) ──────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: widget.destination ?? _currentPos ?? kInitialMapView,
              initialZoom: 15,
              // Lock north-up: rotation gestures during pinch-zoom were
              // disorienting riders on the bar mount.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapEvent: (event) {
                if (event is MapEventMoveStart) {
                  _onCameraMove(event.camera, true);
                }
              },
            ),
            children: [
              // Carto Dark Matter — minimalist dark basemap for night riding.
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.westinx.yurunavi',
                maxZoom: 19,
              ),
              // 현재 위치 — only after a real GPS fix arrives.
              MarkerLayer(
                markers: [
                  if (_currentPos != null)
                    Marker(
                      point: _currentPos!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _kAccent,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: _kAccent.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (widget.destination != null)
                    Marker(
                      point: widget.destination!,
                      width: 36,
                      height: 36,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.redAccent,
                        size: 36,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ── 수동 조작 중 복귀 안내 ────────────────────────
          if (_isManualMode)
            Positioned(
              top: safeTop + 80,
              left: 60,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.gps_fixed, color: _kAccent, size: 14),
                    SizedBox(width: 6),
                    Text(
                      '15초 후 현위치 복귀',
                      style:
                          TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          // ── 상단 회전 안내 카드 (구글맵 스타일 미니멀) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: GestureDetector(
                onTap: _nextStep,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
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
                        // 진행 단계 표시바
                        LinearProgressIndicator(
                          value: (_stepIndex + 1) / _steps.length,
                          backgroundColor:
                              _kSurface2,
                          color: _kAccent,
                          minHeight: 3,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              // 방향 아이콘 박스
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: _kAccent,
                                  borderRadius:
                                      BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  step.icon,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if (step.distLabel.isNotEmpty)
                                      Text(
                                        step.distLabel,
                                        style: const TextStyle(
                                          color: _kAccent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    Text(
                                      step.text,
                                      style: const TextStyle(
                                        color: _kTextPrimary,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (step.road.isNotEmpty)
                                      Text(
                                        step.road,
                                        style: const TextStyle(
                                          color: _kTextSub,
                                          fontSize: 13,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // 단계 도트
                              Column(
                                children: List.generate(
                                  _steps.length,
                                  (i) => AnimatedContainer(
                                    duration: const Duration(
                                        milliseconds: 200),
                                    width:
                                        i == _stepIndex ? 8 : 5,
                                    height:
                                        i == _stepIndex ? 8 : 5,
                                    margin:
                                        const EdgeInsets.symmetric(
                                            vertical: 2.5),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i == _stepIndex
                                          ? _kAccent
                                          : _kTextSub,
                                    ),
                                  ),
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

          // ── 좌측 속도계 ──────────────────────────────────
          Positioned(
            left: 12,
            bottom: 110,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: _DarkSpeedometer(speedKmh: _speedKmh),
            ),
          ),

          // ── 우측 Daylight 바 ──────────────────────────────
          Positioned(
            right: 12,
            top: 200,
            bottom: 110,
            child: DaylightBar(
              progress: daylightProgress,
              sunriseLabel: daylightTimes != null
                  ? DateFormat('HH:mm').format(daylightTimes.bmnt)
                  : '--:--',
              sunsetLabel: daylightTimes != null
                  ? DateFormat('HH:mm').format(daylightTimes.eent)
                  : '--:--',
            ),
          ),

          // ── 우측 보조 버튼 ────────────────────────────────
          Positioned(
            right: 12,
            bottom: 110,
            child: Column(
              children: [
                _DarkRoundBtn(
                  icon: Icons.volume_up_rounded,
                  onTap: () {},
                ),
                const SizedBox(height: 10),
                _DarkRoundBtn(
                  icon: _isManualMode
                      ? Icons.gps_fixed
                      : Icons.my_location,
                  onTap: () {
                    final pos = _currentPos;
                    if (pos == null) return;
                    _autoRecenterTimer?.cancel();
                    setState(() => _isManualMode = false);
                    _recenter(pos);
                  },
                ),
              ],
            ),
          ),

          // ── 하단 ETA 바 (네이버맵 스타일 직관성) ─────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      // 주요 정보: 도착 시간 크게
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '14:32 도착',
                              style: TextStyle(
                                color: _kTextPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Text(
                                  '38분',
                                  style: TextStyle(
                                    color: _kAccent,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '23.4km',
                                  style: TextStyle(
                                    color: _kTextSub,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // 구분선
                      Container(
                        width: 1,
                        height: 40,
                        color: _kSurface2,
                        margin:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      // 종료 버튼
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900
                                .withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close_rounded,
                                  color: Colors.white, size: 20),
                              SizedBox(height: 2),
                              Text(
                                '종료',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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

// ── 다크 속도계 ───────────────────────────────────────────────

class _DarkSpeedometer extends StatelessWidget {
  final double speedKmh;
  const _DarkSpeedometer({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kCard,
        border: Border.all(color: _kAccent, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withValues(alpha: 0.25),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            speedKmh.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _kAccent,
              height: 1.0,
            ),
          ),
          const Text(
            'km/h',
            style: TextStyle(fontSize: 10, color: _kTextSub),
          ),
        ],
      ),
    );
  }
}

// ── 다크 원형 버튼 ────────────────────────────────────────────

class _DarkRoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _DarkRoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kCard,
          border: Border.all(color: _kSurface2, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, color: _kAccent, size: 20),
      ),
    );
  }
}

// ── 회전 단계 데이터 클래스 ───────────────────────────────────

class _TurnStep {
  final IconData icon;
  final String text;
  final String road;
  final String distLabel;
  const _TurnStep({
    required this.icon,
    required this.text,
    required this.road,
    required this.distLabel,
  });
}
