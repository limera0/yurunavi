import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileLogger {
  /// true면 YNAV_CAM도 파일 기록(카메라 디버깅용). 기본 false.
  static const bool logCam = false;
  static IOSink? _sink;
  static Timer? _flushTimer;

  static Future<void> init() async {
    final orig = debugPrint;
    try {
      Directory? dir = await getExternalStorageDirectory();
      dir ??= await getApplicationDocumentsDirectory();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final f = File('${dir.path}/ynav_$ts.log');
      _sink = f.openWrite(mode: FileMode.writeOnlyAppend);
      _rotate(dir);
      _flushTimer?.cancel();
      _flushTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _sink?.flush(),
      );
      debugPrint = (String? msg, {int? wrapWidth}) {
        orig(msg, wrapWidth: wrapWidth);
        if (msg == null || !msg.startsWith('YNAV_')) return;
        if (!logCam && msg.startsWith('YNAV_CAM')) return;
        _sink?.writeln('${DateTime.now().toIso8601String()} $msg');
      };
      orig('YNAV_LOGINIT ok path=${f.path}', wrapWidth: null);
      debugPrint(
        'YNAV_SESSION os=${Platform.operatingSystem} '
        'osVer="${Platform.operatingSystemVersion}" release=$kReleaseMode',
      );
    } catch (e, st) {
      orig('YNAV_LOGINIT FAIL $e', wrapWidth: null);
      orig('$st', wrapWidth: null);
    }
  }

  /// 네이티브(Kotlin/엔진) 로그 브리지 전용 진입점. `YNAV_NATIVE ` 접두어를 붙여
  /// `_sink`에 직접 쓴다 — `debugPrint`를 절대 거치지 마라. `debugPrint`는 이미
  /// stdout→logcat으로 나가므로, 여기서 받은 줄(logcat에서 읽은 줄)을 다시
  /// `debugPrint`로 흘리면 debugPrint → logcat → 네이티브 펌프 → debugPrint로
  /// 무한 증폭되는 루프가 된다.
  static void writeRaw(String line) {
    _sink?.writeln('${DateTime.now().toIso8601String()} YNAV_NATIVE $line');
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
