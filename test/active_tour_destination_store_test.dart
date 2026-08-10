import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:yurunavi/services/active_tour_destination_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('active_tour_dest_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ActiveTourDestinationStore', () {
    test('record() 후 read()로 목적지가 그대로 왕복된다', () async {
      final store = ActiveTourDestinationStore();
      await store.record(
        id: '1000',
        destLat: 37.5665,
        destLng: 126.9780,
        destName: '서울시청',
        waypoints: const [LatLng(37.1, 127.1), LatLng(37.2, 127.2)],
        baseDirOverride: tempDir,
      );

      final read = await store.read('1000', baseDirOverride: tempDir);
      expect(read, isNotNull);
      expect(read!['destLat'], 37.5665);
      expect(read['destLng'], 126.9780);
      expect(read['destName'], '서울시청');
      final waypoints = read['waypoints'] as List;
      expect(waypoints.length, 2);
      expect(waypoints[0], [37.1, 127.1]);
      expect(waypoints[1], [37.2, 127.2]);
    });

    test('destName/waypoints를 생략해도 record()가 성공하고 read()가 값을 반환한다', () async {
      final store = ActiveTourDestinationStore();
      await store.record(
        id: '2000',
        destLat: 35.1,
        destLng: 129.0,
        baseDirOverride: tempDir,
      );

      final read = await store.read('2000', baseDirOverride: tempDir);
      expect(read, isNotNull);
      expect(read!['destLat'], 35.1);
      expect(read['destLng'], 129.0);
      expect(read.containsKey('destName'), isFalse);
      expect(read['waypoints'], isEmpty);
    });

    test('파일이 없으면 read()는 null을 반환한다', () async {
      final store = ActiveTourDestinationStore();
      final read = await store.read('nonexistent', baseDirOverride: tempDir);
      expect(read, isNull);
    });

    test('delete() 후에는 read()가 null을 반환한다', () async {
      final store = ActiveTourDestinationStore();
      await store.record(
        id: '3000',
        destLat: 36.0,
        destLng: 128.0,
        baseDirOverride: tempDir,
      );
      expect(await store.read('3000', baseDirOverride: tempDir), isNotNull);

      await store.delete('3000', baseDirOverride: tempDir);
      expect(await store.read('3000', baseDirOverride: tempDir), isNull);
    });

    test('존재하지 않는 id를 delete()해도 예외 없이 조용히 끝난다', () async {
      final store = ActiveTourDestinationStore();
      await store.delete('never-recorded', baseDirOverride: tempDir);
      // 예외 없이 여기 도달하면 통과.
    });

    test('손상된 JSON 파일이면 read()가 null을 반환한다', () async {
      final toursDir = Directory('${tempDir.path}/tours');
      await toursDir.create(recursive: true);
      final f = File('${toursDir.path}/tour_broken.dest.json');
      await f.writeAsString('{not valid json');

      final store = ActiveTourDestinationStore();
      final read = await store.read('broken', baseDirOverride: tempDir);
      expect(read, isNull);
    });
  });
}
