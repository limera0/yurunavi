import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileLogger {
  /// true면 YNAV_CAM도 파일 기록(카메라 디버깅용). 기본 false.
  static const bool logCam = false;
  static IOSink? _sink;

  static Future<void> init() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final f = File('${dir.path}/ynav_$ts.log');
      _sink = f.openWrite(mode: FileMode.writeOnlyAppend);
      _rotate(dir);
      final orig = debugPrint;
      debugPrint = (String? msg, {int? wrapWidth}) {
        orig(msg, wrapWidth: wrapWidth);
        if (msg == null || !msg.startsWith('YNAV_')) return;
        if (!logCam && msg.startsWith('YNAV_CAM')) return;
        _sink?.writeln('${DateTime.now().toIso8601String()} $msg');
      };
    } catch (_) {
      // 로깅 실패는 앱 동작에 영향 없게 무시
    }
  }

  static void _rotate(Directory dir) {
    try {
      final logs = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('ynav_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in logs.skip(10)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }
}
