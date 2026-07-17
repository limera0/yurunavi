import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 주행 중 GPS 트랙 포인트를 메모리에 버퍼링하지 않고 파일에 순차 append하는
/// writer. [lib/core/logging/file_logger.dart]와 동일한
/// "append 모드로 열고 주기적으로 flush" 패턴을 따른다.
class TourTrackWriter {
  IOSink? _sink;
  Timer? _flushTimer;
  String? _filePath;

  /// 현재(또는 마지막으로) open된 파일 경로. open된 적이 없으면 null.
  String? get filePath => _filePath;

  /// `<dir>/tours/tour_<id>.jsonl` 파일을 append 모드로 열고 2초 주기 flush
  /// 타이머를 시작한다(FileLogger와 동일한 주기). tours/ 하위 디렉터리가
  /// 없으면 생성한다. 열린 파일 경로를 반환한다.
  ///
  /// [baseDirOverride]는 테스트에서 실제 기기 저장소 대신 임시 디렉터리를
  /// 주입하기 위한 용도. 지정하지 않으면 path_provider의
  /// getApplicationDocumentsDirectory()를 사용한다.
  Future<String> open(String id, {Directory? baseDirOverride}) async {
    final baseDir = baseDirOverride ?? await getApplicationDocumentsDirectory();
    // id는 timestamp 유래 숫자 문자열이라 이미 파일시스템에 안전하지만
    // 방어적으로 한 번 더 정제한다.
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final toursDir = Directory('${baseDir.path}/tours');
    if (!await toursDir.exists()) {
      await toursDir.create(recursive: true);
    }
    final f = File('${toursDir.path}/tour_$safeId.jsonl');
    _sink = f.openWrite(mode: FileMode.writeOnlyAppend);
    _filePath = f.path;
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sink?.flush(),
    );
    return f.path;
  }

  /// 트랙 포인트 한 줄을 [epochMs, lat, lng, speedKmh] 형태의 컴팩트 JSON
  /// 배열로 append한다. 아직 open되지 않았으면 아무 동작도 하지 않는다.
  void writePoint({
    required int epochMs,
    required double lat,
    required double lng,
    required double speedKmh,
  }) {
    final sink = _sink;
    if (sink == null) return;
    sink.writeln(jsonEncode([epochMs, lat, lng, speedKmh]));
  }

  /// flush 타이머를 취소하고 sink를 flush 후 닫는다.
  Future<void> close() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  /// 이 writer가 열었던 파일을 삭제한다. 너무 짧은/의미 없는 주행이라
  /// 보존할 필요가 없을 때 사용한다(TourRecorder.finish() 참고).
  Future<void> deleteFile() async {
    final path = _filePath;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // 이미 삭제되었거나 실패해도 무시한다.
    }
  }
}
