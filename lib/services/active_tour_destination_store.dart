import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

/// 내비게이션 시작 시점의 목적지를 `tours/tour_<id>.dest.json`에 즉시 저장한다.
/// TourRecoveryService의 orphan id 스킴과 동일 id를 공유해, 프로세스가
/// 중간에 죽어도(트랙 .jsonl과 마찬가지로) 목적지 정보가 함께 남는다.
class ActiveTourDestinationStore {
  Future<void> record({
    required String id,
    required double destLat,
    required double destLng,
    String? destName,
    List<LatLng> waypoints = const [],
    Directory? baseDirOverride,
  }) async {
    final baseDir = baseDirOverride ?? await getApplicationDocumentsDirectory();
    final toursDir = Directory('${baseDir.path}/tours');
    if (!await toursDir.exists()) await toursDir.create(recursive: true);
    final f = File('${toursDir.path}/tour_$id.dest.json');
    await f.writeAsString(jsonEncode({
      'destLat': destLat,
      'destLng': destLng,
      'destName': ?destName,
      'waypoints': waypoints.map((w) => [w.latitude, w.longitude]).toList(),
    }));
  }

  Future<Map<String, dynamic>?> read(String id, {Directory? baseDirOverride}) async {
    final baseDir = baseDirOverride ?? await getApplicationDocumentsDirectory();
    final f = File('${baseDir.path}/tours/tour_$id.dest.json');
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null; // 손상된 파일 — 없는 것과 동일하게 취급
    }
  }

  Future<void> delete(String id, {Directory? baseDirOverride}) async {
    final baseDir = baseDirOverride ?? await getApplicationDocumentsDirectory();
    final f = File('${baseDir.path}/tours/tour_$id.dest.json');
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
