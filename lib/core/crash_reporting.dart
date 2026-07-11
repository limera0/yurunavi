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

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}
