import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Raw connectivity stream: emits `true` when any non-none result is present.
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));
});

/// Synchronous bool that flips whenever the stream emits.
/// Starts `true` (optimistic) so the map loads tiles immediately on launch.
final isOnlineProvider =
    NotifierProvider<_OnlineNotifier, bool>(_OnlineNotifier.new);

class _OnlineNotifier extends Notifier<bool> {
  @override
  bool build() {
    // ref.listen auto-disposes with this notifier.
    ref.listen<AsyncValue<bool>>(connectivityProvider, (_, next) {
      final online = next.value;
      if (online != null && state != online) {
        state = online;
        debugPrint('[Connectivity] → ${online ? "ONLINE" : "OFFLINE"}');
      }
    });
    return true; // optimistic default
  }
}
