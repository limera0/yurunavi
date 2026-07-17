import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Thin wrapper around the native `com.westinx.yurunavi/nav_service` MethodChannel
/// (see `NavForegroundService.kt` / `MainActivity.kt`). Keeps the process (and TTS
/// audio) alive as a foreground service while the user switches away from the app
/// mid-ride. Android-only — no-ops on other platforms since this repo has no iOS
/// background-navigation scope yet.
///
/// No state is tracked here; callers (nav_screen.dart) own when to start/update/stop.
class NavForegroundService {
  NavForegroundService._();

  static const MethodChannel _channel =
      MethodChannel('com.westinx.yurunavi/nav_service');

  /// Starts the foreground service with an initial notification body [text].
  static Future<void> start(String text) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('start', {'text': text});
  }

  /// Updates the running foreground service's notification body to [text].
  static Future<void> update(String text) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('update', {'text': text});
  }

  /// Stops the foreground service and removes its notification.
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('stop');
  }
}
