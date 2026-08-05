// Crashlytics bootstrap — wired up in main().
//
// `initCrashReporting` takes `FirebaseOptions` as a parameter rather than
// importing `lib/firebase_options.dart` directly, so this file has no
// compile-time dependency on the generated config. `main.dart` passes
// `DefaultFirebaseOptions.currentPlatform` from that file.
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Initializes Firebase + Crashlytics and wires up global error handlers.
///
/// Called as the first two lines of `main()`, after
/// `WidgetsFlutterBinding.ensureInitialized()`.
Future<void> initCrashReporting(FirebaseOptions options) async {
  await Firebase.initializeApp(options: options);

  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = _truncate(details.exception.toString());
    final suppressed = _suppression.shouldEmit(msg);
    if (suppressed == null) return;
    debugPrint(
      'YNAV_CRASH fatal error=$msg${suppressed > 0 ? ' suppressed=$suppressed' : ''}',
    );
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    final msg = _truncate(error.toString());
    final suppressed = _suppression.shouldEmit(msg);
    if (suppressed == null) return true;
    debugPrint(
      'YNAV_CRASH fatal error=$msg${suppressed > 0 ? ' suppressed=$suppressed' : ''}',
    );
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

/// Crashlytics has the full detail — the file log only needs a short summary.
String _truncate(String s, [int maxLen = 300]) =>
    s.length <= maxLen ? s : '${s.substring(0, maxLen)}...';

/// 동일 예외 문자열(truncate 후)이 초당 여러 번 터지는 폭주(예: 렌더 루프의
/// clamp 예외)에 대비해 debugPrint(→디스크 append)와 Crashlytics 업로드를
/// 시그니처당 "최초 1회 + 이후 60초에 1회"로 제한한다. 억제된 횟수는 유실하지
/// 않고 다음 발행 시 `suppressed=N`으로 함께 남긴다.
final _suppression = _CrashSuppression();

class _CrashSuppression {
  static const _window = Duration(seconds: 60);
  static const _maxSignatures = 50;

  final _lastEmitted = <String, DateTime>{};
  final _suppressedSince = <String, int>{};

  /// null을 반환하면 이번 발생은 억제(카운터만 증가, 아무것도 출력/업로드하지
  /// 않음). null이 아니면 이번엔 발행해야 하고, 반환값은 직전 발행 이후
  /// 억제된 횟수(처음 보는 시그니처면 0)다.
  int? shouldEmit(String signature) {
    final now = DateTime.now();
    final last = _lastEmitted[signature];
    if (last != null && now.difference(last) < _window) {
      _suppressedSince[signature] = (_suppressedSince[signature] ?? 0) + 1;
      return null;
    }
    final suppressed = _suppressedSince[signature] ?? 0;
    _lastEmitted[signature] = now;
    _suppressedSince[signature] = 0;
    _evictOldestIfOverCap();
    return suppressed;
  }

  void _evictOldestIfOverCap() {
    if (_lastEmitted.length <= _maxSignatures) return;
    final oldestKey = _lastEmitted.entries
        .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
        .key;
    _lastEmitted.remove(oldestKey);
    _suppressedSince.remove(oldestKey);
  }
}
