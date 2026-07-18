import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../../core/theme/app_theme.dart';
import '../../../models/map_language.dart';
import '../../../models/tour_log.dart';
import '../../map/providers/map_providers.dart';
import '../../map/style_language_transform.dart';
import '../../settings/providers/settings_providers.dart';
import '../tour_log_format.dart';

/// 완료된 투어 한 건의 상세 화면 — 상단 통계 헤더 + 배경 전체를 채우는
/// 지도(주행 궤적 폴리라인 + 출발/도착 핀).
class TourSummaryDetailScreen extends ConsumerStatefulWidget {
  final TourLog tourLog;
  const TourSummaryDetailScreen({super.key, required this.tourLog});

  @override
  ConsumerState<TourSummaryDetailScreen> createState() =>
      _TourSummaryDetailScreenState();
}

class _TourSummaryDetailScreenState extends ConsumerState<TourSummaryDetailScreen> {
  static const _routeSourceId = 'tour_detail_route';
  static const _routeLayerId = 'tour_detail_route_layer';

  ml.MapLibreMapController? _mlCtrl;
  String? _styleJson;

  List<LatLng> _track = const [];
  bool _trackLoaded = false;
  bool _trackUnavailable = false; // 파일 없음/손상/빈 트랙 — 인라인 메시지로 대체
  bool _styleLoaded = false;
  bool _drawn = false; // addGeoJsonSource 등은 한 번만 실행되도록 가드

  @override
  void initState() {
    super.initState();
    unawaited(_loadStyle());
    unawaited(_loadTrack());
  }

  Future<void> _loadStyle() async {
    final raw = await rootBundle.loadString('assets/images/osm_liberty_yurunavi.json');
    if (!mounted) return;
    final lang = ref.read(mapLanguageProvider).value ?? MapLanguage.korean;
    setState(() => _styleJson = applyMapLanguageToStyle(raw, lang));
  }

  /// TourTrackWriter가 기록한 `[epochMs, lat, lng, speedKmh]` 형식의
  /// .jsonl 트랙 파일을 읽어 LatLng 리스트로 변환한다. 파일이 없거나
  /// 손상되었어도 크래시 없이 빈 트랙으로 처리한다.
  Future<void> _loadTrack() async {
    final points = <LatLng>[];
    var unavailable = false;
    try {
      final file = File(widget.tourLog.trackFilePath);
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final decoded = jsonDecode(line) as List<dynamic>;
            points.add(LatLng((decoded[1] as num).toDouble(), (decoded[2] as num).toDouble()));
          } catch (_) {
            // 손상된 한 줄만 건너뛰고 계속 진행한다.
          }
        }
      } else {
        unavailable = true;
      }
    } catch (_) {
      unavailable = true;
    }
    if (!mounted) return;
    setState(() {
      _track = points;
      _trackLoaded = true;
      _trackUnavailable = unavailable || points.isEmpty;
    });
    await _maybeDrawTrack();
  }

  void _onStyleLoaded() {
    _styleLoaded = true;
    unawaited(_maybeDrawTrack());
  }

  /// 스타일 로드와 트랙 파일 읽기 중 나중에 끝나는 쪽에서 실질적으로
  /// 실행된다 (둘 다 비동기, 순서 보장 없음).
  Future<void> _maybeDrawTrack() async {
    if (_drawn || !_styleLoaded || !_trackLoaded) return;
    final ctrl = _mlCtrl;
    if (ctrl == null || _track.isEmpty) return;
    _drawn = true;

    if (_track.length >= 2) {
      await ctrl.addGeoJsonSource(_routeSourceId, _buildRouteGeoJson(_track));
      await ctrl.addLineLayer(
        _routeSourceId,
        _routeLayerId,
        ml.LineLayerProperties(
          lineColor: colorToHex(courseLineColor[2]!),
          lineWidth: 5.0,
          lineCap: 'round',
          lineJoin: 'round',
        ),
      );
    }

    final riderMode = ref.read(riderModeProvider);
    await ctrl.addCircle(ml.CircleOptions(
      geometry: _toMl(_track.first),
      circleRadius: 8.0,
      circleColor: colorToHex(
          riderMode ? RiderModeColors.mapOrigin : AppColors.mapOrigin),
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 2.0,
    ));
    await ctrl.addCircle(ml.CircleOptions(
      geometry: _toMl(_track.last),
      circleRadius: 8.0,
      circleColor: colorToHex(
          riderMode ? RiderModeColors.mapDestination : AppColors.mapDestination),
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 2.0,
    ));

    // 0/1개 좌표는 bounds가 퇴화하므로 카메라 fit을 건너뛴다.
    if (_track.length < 2) return;
    final minLat = _track.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = _track.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLng = _track.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = _track.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    await ctrl.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: ml.LatLng(minLat, minLng),
          northeast: ml.LatLng(maxLat, maxLng),
        ),
        left: 40,
        top: 100,
        right: 40,
        bottom: 40,
      ),
    );
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
                    'coordinates': points.map((p) => [p.longitude, p.latitude]).toList(),
                  },
                  'properties': <String, dynamic>{},
                }
              ],
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tourLog = widget.tourLog;
    final timeRange =
        '${DateFormat('HH:mm').format(tourLog.startedAt)} – ${DateFormat('HH:mm').format(tourLog.endedAt)}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          if (_styleJson == null)
            const Center(child: CircularProgressIndicator())
          else
            Positioned.fill(
              child: ml.MapLibreMap(
                styleString: _styleJson!,
                initialCameraPosition: ml.CameraPosition(
                  target: ml.LatLng(tourLog.startLat, tourLog.startLng),
                  zoom: 12,
                ),
                onMapCreated: (c) => _mlCtrl = c,
                onStyleLoadedCallback: _onStyleLoaded,
              ),
            ),

          if (_trackLoaded && _trackUnavailable)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '이 투어의 이동 경로 데이터를 찾을 수 없어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
            ),

          // ── 상단 통계 헤더 ────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Icon(Icons.arrow_back, color: cs.onSurface),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            timeRange,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatItem(label: '거리', value: formatTourDistanceKm(tourLog.distanceM)),
                        _StatItem(label: '평균', value: formatTourSpeedKmh(tourLog.avgSpeedKmh)),
                        _StatItem(label: '최고', value: formatTourSpeedKmh(tourLog.maxSpeedKmh)),
                      ],
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

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}
