import 'dart:convert';

/// 완료된 주행 1건의 요약 정보 (GPS 트랙 원본은 별도 파일[trackFilePath]에 저장).
class TourLog {
  final String id; // e.g. startedAt.millisecondsSinceEpoch.toString()
  final DateTime startedAt;
  final DateTime endedAt;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final String? startAddress; // nullable, filled by reverse geocoding later
  final String? endAddress;
  final double distanceM;
  final int durationS;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final String trackFilePath; // path to the per-trip .jsonl track file
  final String? memo; // nullable free-text note
  final String? resumedFromId; // 중단 전 원래 구간의 TourLog.id, 없으면 일반 투어

  const TourLog({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    this.startAddress,
    this.endAddress,
    required this.distanceM,
    required this.durationS,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.trackFilePath,
    this.memo,
    this.resumedFromId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'startLat': startLat,
        'startLng': startLng,
        'endLat': endLat,
        'endLng': endLng,
        if (startAddress != null) 'startAddress': startAddress,
        if (endAddress != null) 'endAddress': endAddress,
        'distanceM': distanceM,
        'durationS': durationS,
        'avgSpeedKmh': avgSpeedKmh,
        'maxSpeedKmh': maxSpeedKmh,
        'trackFilePath': trackFilePath,
        if (memo != null) 'memo': memo,
        if (resumedFromId != null) 'resumedFromId': resumedFromId,
      };

  factory TourLog.fromJson(Map<String, dynamic> j) => TourLog(
        id: j['id'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        endedAt: DateTime.parse(j['endedAt'] as String),
        startLat: (j['startLat'] as num).toDouble(),
        startLng: (j['startLng'] as num).toDouble(),
        endLat: (j['endLat'] as num).toDouble(),
        endLng: (j['endLng'] as num).toDouble(),
        startAddress: j['startAddress'] as String?,
        endAddress: j['endAddress'] as String?,
        distanceM: (j['distanceM'] as num).toDouble(),
        durationS: j['durationS'] as int,
        avgSpeedKmh: (j['avgSpeedKmh'] as num).toDouble(),
        maxSpeedKmh: (j['maxSpeedKmh'] as num).toDouble(),
        trackFilePath: j['trackFilePath'] as String,
        memo: j['memo'] as String?,
        resumedFromId: j['resumedFromId'] as String?,
      );

  String toJsonString() => jsonEncode(toJson());
  factory TourLog.fromJsonString(String s) =>
      TourLog.fromJson(jsonDecode(s) as Map<String, dynamic>);

  // startAddress/endAddress/memo는 null↔값을 오갈 수 있어야 하므로
  // copyWith(?? this) 패턴으로는 명시적 null 지정과 "미지정"을 구분할 수 없다
  // (lib/features/navigation/providers/nav_state_provider.dart:28 참고).
  // sentinel object로 "미지정"을 표현해 구분한다.
  static const _unset = Object();

  TourLog copyWith({
    String? id,
    DateTime? startedAt,
    DateTime? endedAt,
    double? startLat,
    double? startLng,
    double? endLat,
    double? endLng,
    Object? startAddress = _unset,
    Object? endAddress = _unset,
    double? distanceM,
    int? durationS,
    double? avgSpeedKmh,
    double? maxSpeedKmh,
    String? trackFilePath,
    Object? memo = _unset,
    Object? resumedFromId = _unset,
  }) =>
      TourLog(
        id: id ?? this.id,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        startLat: startLat ?? this.startLat,
        startLng: startLng ?? this.startLng,
        endLat: endLat ?? this.endLat,
        endLng: endLng ?? this.endLng,
        startAddress: identical(startAddress, _unset)
            ? this.startAddress
            : startAddress as String?,
        endAddress: identical(endAddress, _unset)
            ? this.endAddress
            : endAddress as String?,
        distanceM: distanceM ?? this.distanceM,
        durationS: durationS ?? this.durationS,
        avgSpeedKmh: avgSpeedKmh ?? this.avgSpeedKmh,
        maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
        trackFilePath: trackFilePath ?? this.trackFilePath,
        memo: identical(memo, _unset) ? this.memo : memo as String?,
        resumedFromId: identical(resumedFromId, _unset)
            ? this.resumedFromId
            : resumedFromId as String?,
      );
}
