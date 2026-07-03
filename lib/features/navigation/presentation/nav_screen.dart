import 'dart:async';
import 'dart:convert';
import 'dart:math' show sin, cos, sqrt, asin;

import 'package:http/http.dart' as http;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart'; // 임시 오버레이용 — ②③에서 제거
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/widgets/daylight_bar.dart';
import '../../../services/voice_pack_service.dart';
import '../../../models/map_language.dart';
import '../../../services/routing_service.dart';
import '../../map/providers/map_providers.dart';
import '../../map/style_language_transform.dart';
import '../../settings/providers/settings_providers.dart';
import '../providers/nav_state_provider.dart';
import '../providers/route_progress_provider.dart';
import '../guidance_profile.dart';
import '../voice_engine.dart';
import '../../route/offset_origin.dart';

/// Camera-framing default only — never treated as the rider's location.
/// The real position arrives from the GPS stream below.
const LatLng _kInitialMapView = LatLng(37.5665, 126.9780);

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

  ml.Circle? _locMarker;
  static const String _kLocColor = '#00C853';

  static const _navRouteSourceId = 'nav-route-source';
  static const _navRouteLayerId  = 'nav-route-layer';

  bool _isManualMode = false;
  Timer? _recenterTimer;
  ProviderSubscription<NavigationState?>? _locationSub;

  // ETA — widget.durationMin 초기값, 재탐색 시 갱신
  int _durationMin = 0;

  // 도착 감지
  bool _arrived = false;
  bool _arrivalBannerVisible = false;
  List<({String name, String type})> _arrivalPois = const [];

  // 음성 안내
  FlutterTts? _tts;
  VoicePackService? _vps;
  int _lastAnnouncedIdx = -1;  // 중복 발화 방지 (_announceStep용)
  GuidanceProfile? _profile;
  VoiceEngine? _voiceEngine;

  // progress 구독
  ProviderSubscription<RouteProgress?>? _progressSub;

  // 속도 연동 줌
  double _navZoom = 15.0; // 현재 보간 중인 줌 레벨
  double? _lastHeadingDeg; // 정차/저속 시 최근 방향 유지용 (bottom-anchor 오프셋)

  // 이탈 재탐색
  List<LatLng> _routePoints = []; // widget.routePolyline 의 가변 복사본
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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.dark,
    ));
    _recenterTimer?.cancel();
    _offRouteDebounce?.cancel();
    _locationSub?.close();
    _progressSub?.close();
    _pulseCtrl.dispose();
    _tts?.stop();
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
        if (!_isManualMode) _recenter(loc, speedKmh: next.speedKmh, headingDeg: next.headingDeg);
        if (next.headingDeg != null && next.speedKmh > 2 && _styleLoaded) {
          _mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(next.headingDeg!));
        }
        _ensureLocationMarker();
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
        _handleVoice(prog);
        if (prog.arrived && !_arrived) {
          _arrived = true;
          _vps?.speak('arrival');
          setState(() => _arrivalBannerVisible = true);
          _fetchNearbyPois(widget.destination!).then((pois) {
            if (mounted) setState(() => _arrivalPois = pois);
          });
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

  void _handleVoice(RouteProgress prog) {
    if (_profile == null) return;
    final intents = _voiceEngine!.onProgress(
        prog.activeStepIdx, prog.distToNextTurnM, _maneuvers,
        speedKmh: ref.read(navStateProvider)?.speedKmh ?? 0);
    for (final it in intents) {
      _vps?.speak(it.key, vars: it.vars);
      debugPrint('YNAV_TTS key=${it.key} dist=${it.vars['dist']} step=${prog.activeStepIdx}');
    }
  }

  void _applyRouteGuidance(List<ManeuverStep> maneuvers) {
    _steps = maneuvers.isNotEmpty
        ? maneuvers.map(_TurnStep.fromManeuver).toList()
        : const [
            _TurnStep(Icons.play_arrow_rounded, '경로 안내 시작', '', 0),
            _TurnStep(Icons.straight_rounded,   '직진',         '', 0),
            _TurnStep(Icons.flag_rounded,        '목적지 도착',  '', 0),
          ];
    _maneuvers = maneuvers;
    _stepIdx = 0;
    _cardRemainingM = 0.0;
    _lastAnnouncedIdx = -1;
    _voiceEngine?.reset();
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
    }
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
    if (_isRerouting || !mounted) return;
    if (_arrivalBannerVisible) {
      setState(() {
        _arrivalBannerVisible = false;
        _arrivalPois = const [];
        _arrived = false;
      });
    }
    final dest = widget.destination;
    if (dest == null) return;
    setState(() => _isRerouting = true);
    final navState = ref.read(navStateProvider);
    final heading = (navState != null && navState.speedKmh > 2) ? navState.headingDeg : null;
    debugPrint('YNAV_REROUTE hdg_src spd=${navState?.speedKmh} rawHdg=${navState?.headingDeg} used=$heading');
    final off = offsetOrigin(origin.latitude, origin.longitude, heading, 40);
    final routeOrigin = LatLng(off.lat, off.lng);
    debugPrint('YNAV_REROUTE off origin hdg=$heading d=40');
    try {
      final routes = await RoutingService.fetchRoutes(
        origin: routeOrigin,
        destination: dest,
        waypoints: widget.waypoints,
      );
      if (mounted && routes.isNotEmpty) {
        final selIdx = ref.read(mapInteractionProvider).selectedRouteIdx.clamp(0, routes.length - 1);
        final newPoints = routes[selIdx].points;
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

  void _manualReroute() {
    final pos = ref.read(navStateProvider)?.pos;
    if (pos == null) return;
    _reroute(pos, silent: true);
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts!.setLanguage('ko-KR');
    await _tts!.setSpeechRate(0.5);
    await _tts!.setVolume(1.0);
    _vps = await VoicePackService.load('assets/voice_packs/default_ko.json', _tts!);
    _profile = await GuidanceProfile.load('assets/config/guidance_profile.json');
    _voiceEngine = VoiceEngine(_profile!);
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
              Navigator.of(ctx).pop();
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

  Future<void> _recenter(LatLng loc, {bool animate = false, double speedKmh = 0, double? headingDeg}) async {
    if (!_styleLoaded) return;
    final target = _zoomForSpeed(speedKmh);
    // GPS 이벤트당 최대 0.5레벨씩 부드럽게 수렴
    final diff = target - _navZoom;
    _navZoom += diff.clamp(-0.3, 0.3); // 수렴 속도 낮춤 (0~20km/h 구간 과도한 줌 방지)

    if (headingDeg != null) _lastHeadingDeg = headingDeg;
    final effectiveHeadingDeg = headingDeg ?? _lastHeadingDeg;

    var camTarget = loc;
    if (effectiveHeadingDeg != null) {
      final metersPerPixel = await _mlCtrl?.getMetersPerPixelAtLatitude(loc.latitude);
      if (metersPerPixel != null && mounted) {
        final screenHeightPx = MediaQuery.of(context).size.height;
        final metersAhead = metersPerPixel * screenHeightPx * 0.35;
        debugPrint('YNAV_CAM anchor hdg=$effectiveHeadingDeg mpp=$metersPerPixel mAhead=$metersAhead');
        final off = offsetOrigin(loc.latitude, loc.longitude, effectiveHeadingDeg, metersAhead);
        camTarget = LatLng(off.lat, off.lng);
      }
    }

    final update = ml.CameraUpdate.newLatLngZoom(_toMl(camTarget), _navZoom);
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

  Future<void> _initRouteLayer() async {
    final ctrl = _mlCtrl;
    if (ctrl == null) return;
    await ctrl.addGeoJsonSource(_navRouteSourceId, _buildRouteGeoJson([]));
    await ctrl.addLineLayer(
      _navRouteSourceId,
      _navRouteLayerId,
      const ml.LineLayerProperties(
        lineColor: '#F28C28', // nav 오렌지색 유지
        lineWidth: 6.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      // belowLayerId: ③에서 Circle 레이어 추가 후 z-order 삽입
    );
  }

  Future<void> _ensureLocationMarker() async {
    final c = _mlCtrl;
    if (c == null || !_styleLoaded) return;
    final p = ref.read(navStateProvider)?.pos;
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

  void _onStyleLoaded() {
    setState(() => _styleLoaded = true);
    // 레이어 설치 후 진입 시 이미 있는 경로 즉시 반영
    _initRouteLayer().whenComplete(() {
      if (_routePoints.length >= 2 && mounted) {
        _mlCtrl?.setGeoJsonSource(
            _navRouteSourceId, _buildRouteGeoJson(_routePoints));
      }
      _ensureLocationMarker(); // unawaited — ③
    });
  }

  void _onMapGesture() {
    setState(() => _isManualMode = true);
    _recenterTimer?.cancel();
    _recenterTimer = Timer(const Duration(seconds: 10), () {
      setState(() => _isManualMode = false);
      final pos = ref.read(navStateProvider)?.pos;
      if (pos != null) {
        final ns = ref.read(navStateProvider);
        _recenter(pos, animate: true, speedKmh: ns?.speedKmh ?? 0, headingDeg: ns?.headingDeg);
      }
    });
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

          // ── 임시 오버레이: flutter_map 폴리라인/마커 ────────────────────────
          // ② GeoJSON LineLayer로, ③ Circle/Symbol로 교체 후 이 블록 제거
          IgnorePointer(
            child: FlutterMap(
              options: MapOptions(
                backgroundColor: Colors.transparent, // MapLibreMap이 보이도록
                initialCenter: ref.read(navStateProvider)?.pos ?? _kInitialMapView,
                initialZoom: _navZoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                // PolylineLayer 제거 — GeoJSON LineLayer로 교체됨 (커밋 ②)
                MarkerLayer(markers: [
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
                          child: Text('목적지에 도착했습니다',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _arrivalBannerVisible = false),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.tertiary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text('종료',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
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
                    final pos = ref.read(navStateProvider)?.pos;
                    if (pos == null) return;
                    _recenterTimer?.cancel();
                    setState(() => _isManualMode = false);
                    final ns = ref.read(navStateProvider);
                    _recenter(pos, animate: true, speedKmh: ns?.speedKmh ?? 0, headingDeg: ns?.headingDeg);
                  },
                ),
                const SizedBox(height: 10),
                _NavIconBtn(
                  icon: Icons.refresh_rounded,
                  loading: _isRerouting,
                  enabled: navState?.pos != null,
                  onTap: _manualReroute,
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
  final bool loading;
  final bool enabled;
  const _NavIconBtn({
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = enabled && !loading;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(color: cs.outline, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8)],
        ),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.tertiary),
              )
            : Icon(icon, color: active ? cs.tertiary : cs.outline, size: 20),
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

  factory _TurnStep.fromManeuver(ManeuverStep m) {
    return _TurnStep(
      _iconForType(m.type),
      _labelForType(m.type, m.roundaboutExitCount),
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

  static String _labelForType(int type, [int? roundaboutExitCount]) {
    switch (type) {
      case 1: case 2: case 3: return '출발';
      case 4: case 5: case 6: return '목적지 도착';
      case 7: return '도로명 변경';
      case 8: case 22: return '직진';
      case 9: return '약간 우회전';
      case 10: return '우회전';
      case 11: return '급우회전';
      case 12: case 13: return '유턴';
      case 14: return '급좌회전';
      case 15: return '좌회전';
      case 16: return '약간 좌회전';
      case 17: return '램프 직진';
      case 18: return '램프 우측';
      case 19: return '램프 좌측';
      case 20: return '우측 출구';
      case 21: return '좌측 출구';
      case 23: return '우측 유지';
      case 24: return '좌측 유지';
      case 25: return '합류';
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
