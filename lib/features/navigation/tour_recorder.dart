import 'dart:io';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../models/tour_log.dart';
import 'tour_track_writer.dart';

/// GPS fix 스트림으로부터 주행 트랙을 기록하고, 종료 시 [TourLog] 요약을
/// 생성하는 순수 Dart 레코더. 트랙 포인트 자체는 [TourTrackWriter]를 통해
/// 파일에 즉시 append되며 메모리에 버퍼링하지 않는다.
class TourRecorder {
  final TourTrackWriter _writer;
  TourRecorder({TourTrackWriter? writer}) : _writer = writer ?? TourTrackWriter();

  static const Distance _distance = Distance();

  String? _id;
  DateTime? _startedAt;
  LatLng? _startPos;
  LatLng? _lastPos; // 최근 fix 위치(거리 적분 기준용, 채택 게이트와 무관)
  DateTime? _lastFixAt;
  LatLng? _lastAcceptedTrackPos; // 트랙 파일에 실제로 기록된 마지막 위치
  DateTime? _lastAcceptedTrackAt;
  double _distanceM = 0;
  double _maxSpeedKmh = 0;

  /// 현재(또는 마지막으로) 기록 중이던 트랙 파일 경로. start()를 호출하기
  /// 전이면 null.
  String? get trackFilePath => _writer.filePath;

  /// 가장 최근에 관측된 fix 위치(트랙 파일 채택 여부와 무관하게 매 fix마다
  /// 갱신된다). start()를 호출하기 전이면 null.
  LatLng? get lastPos => _lastPos;

  Future<void> start(
    LatLng pos,
    DateTime at, {
    Directory? baseDirOverride,
  }) async {
    final id = at.millisecondsSinceEpoch.toString();
    _id = id;
    _startedAt = at;
    _startPos = pos;
    _distanceM = 0;
    _maxSpeedKmh = 0;

    await _writer.open(id, baseDirOverride: baseDirOverride);
    // 아주 짧은 주행이라도 트랙 포인트가 1개 이상은 남도록 즉시 기록한다.
    _writer.writePoint(
      epochMs: at.millisecondsSinceEpoch,
      lat: pos.latitude,
      lng: pos.longitude,
      speedKmh: 0,
    );

    _lastPos = pos;
    _lastFixAt = at;
    _lastAcceptedTrackPos = pos;
    _lastAcceptedTrackAt = at;
  }

  void onFix(LatLng pos, double speedKmh, DateTime at) {
    if (_startedAt == null) return;

    // 1. 거리 적분 — 백그라운드 전환 등으로 인한 오래된/드문 tick이 한 번에
    //    비정상적으로 큰 거리를 더하지 않도록 dt를 최대 3초로 clamp한다.
    final dtSeconds = math.min(
      at.difference(_lastFixAt!).inMilliseconds / 1000,
      3.0,
    );
    _distanceM += (speedKmh / 3.6) * dtSeconds;
    _lastPos = pos;
    _lastFixAt = at;

    // 2. 최고 속도
    if (speedKmh > _maxSpeedKmh) {
      _maxSpeedKmh = speedKmh;
    }

    // 3. 트랙 포인트 채택 게이트 — 위 거리/속도 적분과는 독립적으로 동작하며
    //    이 fix를 트랙 파일에 기록할지 여부만 결정한다.
    final distFromLastAccepted =
        _distance.as(LengthUnit.Meter, pos, _lastAcceptedTrackPos!);
    final secsSinceLastAccepted =
        at.difference(_lastAcceptedTrackAt!).inSeconds;

    final impliedKmh = distFromLastAccepted /
        math.max(secsSinceLastAccepted.toDouble(), 0.001) *
        3.6;
    if (impliedKmh > 200) {
      // GPS 노이즈로 간주. 기준점(_lastAcceptedTrack*)은 갱신하지 않고
      // 그대로 둔다 — 다음 fix는 이 잡음이 아닌 마지막 정상 채택 지점과
      // 비교된다(의도된 동작).
      return;
    }

    final accepted = distFromLastAccepted >= 20.0 ||
        (secsSinceLastAccepted >= 8 && distFromLastAccepted >= 3.0);
    if (accepted) {
      _writer.writePoint(
        epochMs: at.millisecondsSinceEpoch,
        lat: pos.latitude,
        lng: pos.longitude,
        speedKmh: speedKmh,
      );
      _lastAcceptedTrackPos = pos;
      _lastAcceptedTrackAt = at;
    }
  }

  /// 기록을 종료한다. 트랙 파일을 닫는다. 최소 기준(기본 60초, 150m)을
  /// 만족하지 못하면 방금 기록한 트랙 파일을 삭제하고 null을 반환한다 —
  /// 이 경우 아무것도 저장되어서는 안 된다. 그렇지 않으면 트랙/주소/메모를
  /// 다음과 같이 남겨둔 [TourLog]를 반환한다: trackFilePath는 이 레코더가
  /// 기록한 파일, startAddress/endAddress는 null(역지오코딩은 호출자가
  /// 채운다), memo는 null, id는 파일명에 쓰인 것과 동일한 id.
  Future<TourLog?> finish(
    LatLng endPos,
    DateTime endedAt, {
    int minDurationS = 60,
    double minDistanceM = 150,
  }) async {
    final id = _id;
    final startedAt = _startedAt;
    final startPos = _startPos;
    if (id == null || startedAt == null || startPos == null) {
      return null;
    }

    await _writer.close();

    final durationS = endedAt.difference(startedAt).inSeconds;
    if (durationS < minDurationS || _distanceM < minDistanceM) {
      await _writer.deleteFile();
      return null;
    }

    final avgSpeedKmh =
        durationS == 0 ? 0.0 : (_distanceM / 1000) / (durationS / 3600);

    return TourLog(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt,
      startLat: startPos.latitude,
      startLng: startPos.longitude,
      endLat: endPos.latitude,
      endLng: endPos.longitude,
      distanceM: _distanceM,
      durationS: durationS,
      avgSpeedKmh: avgSpeedKmh,
      maxSpeedKmh: _maxSpeedKmh,
      trackFilePath: _writer.filePath ?? '',
    );
  }
}
