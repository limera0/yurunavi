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
    debugPrint('YNAV_CRASH fatal error=${_truncate(details.exception.toString())}');
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('YNAV_CRASH fatal error=${_truncate(error.toString())}');
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

/// Crashlytics has the full detail — the file log only needs a short summary.
String _truncate(String s, [int maxLen = 300]) =>
    s.length <= maxLen ? s : '${s.substring(0, maxLen)}...';
