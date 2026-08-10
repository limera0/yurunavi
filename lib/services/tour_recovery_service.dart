import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../models/tour_log.dart';
import 'active_tour_destination_store.dart';
import 'geocoding_service.dart';
import 'tour_log_service.dart';

/// 앱 프로세스가 통째로 강제 종료된 경우(태스크 스와이프, OEM 배터리
/// 매니저, OOM kill) 발생하는 "고아 트랙 파일"을 다음 콜드 스타트에서
/// 감지해 요약 [TourLog]로 복구하는 서비스.
///
/// 원시 GPS 트랙(.jsonl)은 [TourTrackWriter]가 이미 즉시 디스크에
/// append하므로 데이터 자체는 유실되지 않는다. 하지만 히스토리 화면에
/// 실제로 표시되는 요약([TourLog]: 거리/시간/평균속도/주소)은
/// `TourRecorder.finish()`가 끝까지 실행됐을 때만 계산·저장되므로,
/// 프로세스가 그 전에 죽으면 트랙 파일은 남아도 히스토리에는 아무 것도
/// 나타나지 않는다 (`loop/RECON_tour_history_lost.md` 참고).
///
/// 이 서비스는 매 콜드 스타트마다 `tours/` 디렉터리를 훑어, 이미
/// [TourLogService]에 저장된 id가 아닌 트랙 파일(=고아)을 찾아 파일 내용만
/// 으로 요약을 다시 계산하고 저장한다. 복구할 것이 없는 통상적인 경우에는
/// 디렉터리 목록 조회 1회 + `loadAll()` 1회만 수행하고 네트워크 호출 없이
/// 끝난다.
///
/// 주의: 여기서 계산되는 distanceM/durationS/maxSpeedKmh는
/// `TourRecorder.onFix()`가 매 GPS fix마다 수행하는 실시간 적분과 동일하지
/// 않다 — `TourRecorder`는 트랙 채택 게이트(20m 이동 또는 8초+3m) 이전
/// 단계에서 모든 fix를 적분/추적하지만, 이 서비스는 그 게이트를 이미 통과해
/// 파일에 남은(다운샘플된) 포인트들만 볼 수 있다. 따라서 distanceM은 그
/// 포인트들 사이의 직선(chord) 거리 합으로 계산되며, 굽은 도로(급커브·헤어핀)
/// 에서는 실제 주행 경로보다 체계적으로 짧게 나온다. 또한 주행이 정지 상태로
/// 끝난 경우 채택 게이트에 걸려 마지막 지점 이후로 새 포인트가 기록되지
/// 않으므로 durationS/endedAt이 실제 종료 시각보다 이르게 잡힐 수 있다. 이는
/// 폴백 복구 경로로서 감내 가능한 근사치이며, 정상 종료 시 `TourRecorder`가
/// 남기는 정확한 요약을 재현하려는 것이 아니다.
class TourRecoveryService {
  final TourLogService _tourLogService;
  final GeocodingService _geocodingService;
  final ActiveTourDestinationStore _destStore;

  TourRecoveryService({
    TourLogService? tourLogService,
    GeocodingService? geocodingService,
    ActiveTourDestinationStore? destinationStore,
  })  : _tourLogService = tourLogService ?? TourLogService(),
        _geocodingService = geocodingService ?? GeocodingService(),
        _destStore = destinationStore ?? ActiveTourDestinationStore();

  static const Distance _distance = Distance();

  // TourRecorder.finish()와 동일한 임계값(60초/150m) — 일관성을 위해 그대로
  // 사용한다. 단, 이 임계값과 비교되는 durationS/distanceM 자체는 아래
  // _recoverOne()에서 설명하는 근사치임에 유의.
  static const int _minDurationS = 60;
  static const double _minDistanceM = 150;

  static final RegExp _idPattern = RegExp(r'^tour_(.+)\.jsonl$');

  /// `<baseDirOverride ?? getApplicationDocumentsDirectory()>/tours/*.jsonl`
  /// 중 아직 [TourLogService]에 저장되지 않은(id 불일치) 고아 파일을 찾아
  /// 요약을 계산하고 저장한다. 파일 하나의 처리 실패가 나머지 파일 복구를
  /// 막지 않도록 각 파일을 개별 try/catch로 감싼다. 이 메서드 자체도
  /// 예외를 밖으로 던지지 않는다 — 앱 시작 시 fire-and-forget으로 호출되기
  /// 때문이다.
  ///
  /// [resumeThresholdHours]가 null이면(기본값) 발견된 고아는 모두 즉시
  /// finalize한다(기존 동작 그대로 — 회귀 없음). 값이 주어지면, 각 고아의
  /// 마지막 트랙 포인트 시각이 그 임계치 이내이고 동시에
  /// [ActiveTourDestinationStore]에 목적지 사이드카가 남아있는("재개 가능"
  /// 판정) 경우에는 finalize하지 않고 파일을 그대로 둔 채 건너뛴다 — 그
  /// 판정·재개는 [findResumableOrphan]/[finalizeAsInterrupted]가 전담한다.
  ///
  /// 알려진 한계: "고아"의 유일한 판별 신호는 "파일명이 tour_*.jsonl 패턴과
  /// 일치하고 id가 아직 TourLogService에 없다"는 것뿐이라, 개념적으로는
  /// "이번 세션에서 방금 시작해 아직 끝나지 않은 정상 진행 중인 투어"와
  /// 구분되지 않는다. 문제되지 않는다 — 재개 가능 판정이 서는 고아는 위에서
  /// 설명한 대로 여기서 스킵하고 [findResumableOrphan]/[finalizeAsInterrupted]
  /// 만 건드리며, 새로 시작되는 재개 세션은 항상 새 id(현재 시각 기준)로
  /// 시작해 이 파일을 다시 열지 않으므로 활성 투어를 고아로 오인해 조기
  /// 종료 처리하는 경합이 발생하지 않는다.
  Future<void> recoverOrphans({
    Directory? baseDirOverride,
    int? resumeThresholdHours,
  }) async {
    try {
      final baseDir =
          baseDirOverride ?? await getApplicationDocumentsDirectory();
      final toursDir = Directory('${baseDir.path}/tours');
      if (!await toursDir.exists()) return;

      final entries = await toursDir.list().toList();
      final files = entries
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .toList();

      // 복구할 것이 없어도(통상 케이스) 이 한 번의 loadAll()만 수행한다 —
      // 네트워크 호출은 실제 고아가 있을 때만(역지오코딩) 발생한다.
      final knownIds =
          (await _tourLogService.loadAll()).map((l) => l.id).toSet();

      for (final file in files) {
        try {
          final name = file.uri.pathSegments.last;
          final match = _idPattern.firstMatch(name);
          if (match == null) continue;
          final id = match.group(1)!;
          if (knownIds.contains(id)) continue; // 이미 정상 저장됨 — 건드리지 않음

          final lines = await file.readAsLines();

          if (resumeThresholdHours != null) {
            final lastPoint = _lastTrackPointFromLines(lines);
            if (lastPoint != null &&
                DateTime.now().difference(lastPoint.at) <=
                    Duration(hours: resumeThresholdHours)) {
              final dest = await _destStore.read(
                id,
                baseDirOverride: baseDirOverride,
              );
              if (dest != null) {
                continue; // 재개 가능 판정 — finalize하지 않고 스킵
              }
            }
          }

          await _recoverOne(id, file, lines);
        } catch (e) {
          debugPrint('YNAV_TOUR_RECOVERY file failed path=${file.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('YNAV_TOUR_RECOVERY failed: $e');
    }
  }

  /// 재개 임계치([thresholdHours]) 이내의 마지막 트랙 포인트를 갖고 있고
  /// 동시에 목적지 사이드카([ActiveTourDestinationStore])가 남아있는(=재개
  /// 가능 판정) 고아들 중, 가장 최근에 움직인 1건을 [ResumableOrphan]으로
  /// 반환한다. 없으면 null. 이 메서드는 finalize를 수행하지 않는다 — 순수
  /// 조회다.
  Future<ResumableOrphan?> findResumableOrphan({
    required int thresholdHours,
    Directory? baseDirOverride,
  }) async {
    try {
      final baseDir =
          baseDirOverride ?? await getApplicationDocumentsDirectory();
      final toursDir = Directory('${baseDir.path}/tours');
      if (!await toursDir.exists()) return null;

      final entries = await toursDir.list().toList();
      final files = entries
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .toList();

      final knownIds =
          (await _tourLogService.loadAll()).map((l) => l.id).toSet();

      ResumableOrphan? best;
      for (final file in files) {
        try {
          final name = file.uri.pathSegments.last;
          final match = _idPattern.firstMatch(name);
          if (match == null) continue;
          final id = match.group(1)!;
          if (knownIds.contains(id)) continue;

          final lines = await file.readAsLines();
          final lastPoint = _lastTrackPointFromLines(lines);
          if (lastPoint == null) continue;
          if (DateTime.now().difference(lastPoint.at) >
              Duration(hours: thresholdHours)) {
            continue;
          }

          final dest =
              await _destStore.read(id, baseDirOverride: baseDirOverride);
          if (dest == null) continue;
          final destLat = (dest['destLat'] as num?)?.toDouble();
          final destLng = (dest['destLng'] as num?)?.toDouble();
          if (destLat == null || destLng == null) continue;

          final waypointsRaw = dest['waypoints'] as List?;
          final waypoints = <LatLng>[
            if (waypointsRaw != null)
              for (final w in waypointsRaw)
                LatLng(
                  ((w as List)[0] as num).toDouble(),
                  (w[1] as num).toDouble(),
                ),
          ];

          final candidate = ResumableOrphan(
            id: id,
            lastPos: lastPoint.pos,
            lastPointAt: lastPoint.at,
            destLat: destLat,
            destLng: destLng,
            destName: dest['destName'] as String?,
            waypoints: waypoints,
          );
          if (best == null || candidate.lastPointAt.isAfter(best.lastPointAt)) {
            best = candidate;
          }
        } catch (e) {
          debugPrint(
              'YNAV_TOUR_RECOVERY findResumableOrphan file failed path=${file.path}: $e');
        }
      }
      return best;
    } catch (e) {
      debugPrint('YNAV_TOUR_RECOVERY findResumableOrphan failed: $e');
      return null;
    }
  }

  /// [id]의 고아 트랙을 (재개 여부와 무관하게) 기존 [_recoverOne] 로직으로
  /// 확정 저장하고, 목적지 사이드카([ActiveTourDestinationStore])를 정리한다.
  /// 스플래시의 "이어서 안내하기" 수락/거절 양쪽 경로에서 호출된다 — 재개를
  /// 수락해도(중단 전 구간을 별도 히스토리로 확정) 거절해도(그냥 일반 고아처럼
  /// 확정) 동일하게 이 메서드로 마무리한다.
  Future<TourLog?> finalizeAsInterrupted(
    String id, {
    Directory? baseDirOverride,
  }) async {
    TourLog? result;
    try {
      final baseDir =
          baseDirOverride ?? await getApplicationDocumentsDirectory();
      final file = File('${baseDir.path}/tours/tour_$id.jsonl');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        result = await _recoverOne(id, file, lines);
      }
    } catch (e) {
      debugPrint('YNAV_TOUR_RECOVERY finalizeAsInterrupted failed id=$id: $e');
    }
    await _destStore.delete(id, baseDirOverride: baseDirOverride);
    return result;
  }

  /// 트랙 라인 목록에서(뒤에서부터 훑어) 손상되지 않은 마지막 포인트의
  /// 시각/위치를 뽑아낸다. kill 도중 partial write된 마지막 줄 등 손상된
  /// 라인은 건너뛰고 그 앞의 유효한 라인을 사용한다. 유효한 라인이 하나도
  /// 없으면 null.
  ({DateTime at, LatLng pos})? _lastTrackPointFromLines(List<String> lines) {
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      try {
        final arr = jsonDecode(line) as List;
        return (
          at: DateTime.fromMillisecondsSinceEpoch((arr[0] as num).toInt()),
          pos: LatLng((arr[1] as num).toDouble(), (arr[2] as num).toDouble()),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<TourLog?> _recoverOne(String id, File file, List<String> lines) async {
    final points = <_TrackPoint>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final arr = jsonDecode(line) as List;
        points.add(_TrackPoint(
          epochMs: (arr[0] as num).toInt(),
          lat: (arr[1] as num).toDouble(),
          lng: (arr[2] as num).toDouble(),
          speedKmh: (arr[3] as num).toDouble(),
        ));
      } catch (_) {
        // kill 도중 partial write된 마지막 줄 등 — 그 줄만 건너뛴다.
      }
    }

    if (points.length < 2) {
      await _deleteQuietly(file);
      return null;
    }

    final first = points.first;
    final last = points.last;
    final startedAt = DateTime.fromMillisecondsSinceEpoch(first.epochMs);
    final endedAt = DateTime.fromMillisecondsSinceEpoch(last.epochMs);
    final durationS = endedAt.difference(startedAt).inSeconds;

    // 근사치 계산: 파일에 남은 것은 TourRecorder의 트랙 채택 게이트를 통과한
    // 다운샘플 포인트뿐이므로, distanceM은 그 포인트 사이의 직선(chord) 거리
    // 합이다 — 굽은 도로에서는 실제 주행 거리보다 적게 나온다(클래스
    // 헤더 참고). maxSpeedKmh 역시 다운샘플된 포인트들 중 최댓값이라
    // TourRecorder가 매 fix마다 추적하는 값보다 낮게 나올 수 있다.
    double distanceM = 0;
    double maxSpeedKmh = 0;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.speedKmh > maxSpeedKmh) maxSpeedKmh = p.speedKmh;
      if (i > 0) {
        final a = LatLng(points[i - 1].lat, points[i - 1].lng);
        final b = LatLng(p.lat, p.lng);
        distanceM += _distance.as(LengthUnit.Meter, a, b);
      }
    }

    if (durationS < _minDurationS || distanceM < _minDistanceM) {
      // TourRecorder.finish()와 동일한 임계값(60s/150m) 기준 미달 — 노이즈로
      // 간주하고 버린다. 위에서 설명한 근사 오차 때문에 실제로는 임계값을
      // 넘겼을 라이드가 여기서 걸러질 가능성이 있으나(과소평가 방향), 폴백
      // 경로이므로 감내한다.
      await _deleteQuietly(file);
      return null;
    }

    final avgSpeedKmh =
        durationS == 0 ? 0.0 : (distanceM / 1000) / (durationS / 3600);

    String? startAddress;
    String? endAddress;
    try {
      final results = await Future.wait([
        _geocodingService.reverseGeocode(first.lat, first.lng),
        _geocodingService.reverseGeocode(last.lat, last.lng),
      ]);
      startAddress = results[0];
      endAddress = results[1];
    } catch (e) {
      debugPrint('YNAV_TOUR_RECOVERY geocode failed id=$id: $e');
    }

    final log = TourLog(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt,
      startLat: first.lat,
      startLng: first.lng,
      endLat: last.lat,
      endLng: last.lng,
      startAddress: startAddress,
      endAddress: endAddress,
      distanceM: distanceM,
      durationS: durationS,
      avgSpeedKmh: avgSpeedKmh,
      maxSpeedKmh: maxSpeedKmh,
      trackFilePath: file.path,
      memo: '비정상 종료로 자동 복구됨',
    );

    await _tourLogService.add(log);
    debugPrint('YNAV_TOUR_RECOVERY recovered id=$id '
        'distanceM=${distanceM.toStringAsFixed(0)} '
        'durationS=$durationS '
        'avgKmh=${avgSpeedKmh.toStringAsFixed(1)} '
        'maxKmh=${maxSpeedKmh.toStringAsFixed(1)}');
    return log;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 이미 삭제되었거나 실패해도 무시한다.
    }
  }
}

/// [TourRecoveryService.findResumableOrphan]이 반환하는, "재개 가능" 판정을
/// 통과한 고아 트랙 1건의 요약. 트랙 파일 자체를 finalize하지 않은 채로
/// 재개 여부를 판단·표시하는 데 필요한 최소 정보만 담는다.
class ResumableOrphan {
  final String id;
  final LatLng lastPos;
  final DateTime lastPointAt;
  final double destLat;
  final double destLng;
  final String? destName;
  final List<LatLng> waypoints;

  const ResumableOrphan({
    required this.id,
    required this.lastPos,
    required this.lastPointAt,
    required this.destLat,
    required this.destLng,
    this.destName,
    this.waypoints = const [],
  });
}

class _TrackPoint {
  final int epochMs;
  final double lat;
  final double lng;
  final double speedKmh;
  _TrackPoint({
    required this.epochMs,
    required this.lat,
    required this.lng,
    required this.speedKmh,
  });
}
