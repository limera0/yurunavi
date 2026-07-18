import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:yurunavi/services/voice_pack_service.dart';

// Regression coverage for the "덕킹 복구 안 됨" fix: overlapping speak()
// calls used to race on the native audioFocusRequest variable inside
// flutter_tts. VoicePackService now serializes speak() through an internal
// queue — this test verifies the *instance* speak() (not just the static
// resolveTemplate helper) actually waits for the previous native speak()
// call to settle before issuing the next one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('겹치는 speak() 호출은 직렬화되어 이전 발화가 끝난 뒤에만 다음 발화가 나간다', () async {
    final events = <String>[];
    final pending = <Completer<void>>[];

    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method != 'speak') return null;
      final text = call.arguments as String; // non-Android test host branch
      events.add('start:$text');
      final completer = Completer<void>();
      pending.add(completer);
      await completer.future;
      events.add('end:$text');
      return 1;
    });

    final tts = FlutterTts();
    final vps =
        await VoicePackService.load('assets/voice_packs/default_ko.json', tts);

    final f1 = vps.speak('departure');
    final f2 = vps.speak('arrival'); // fired without awaiting f1 first

    // Let the microtask/event queue drain enough for the first native call
    // to be dispatched, but the second speak() must still be waiting on
    // the internal queue — only one native 'speak' call should exist so far.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(pending.length, 1);
    expect(events, ['start:경로안내를 시작합니다']);

    // Resolve the first native call — only now should the second be issued.
    pending[0].complete();
    await f1;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(pending.length, 2);
    expect(events, ['start:경로안내를 시작합니다', 'end:경로안내를 시작합니다', 'start:목적지에 도착했습니다']);

    pending[1].complete();
    await f2;

    expect(events, [
      'start:경로안내를 시작합니다',
      'end:경로안내를 시작합니다',
      'start:목적지에 도착했습니다',
      'end:목적지에 도착했습니다',
    ]);
  });
}
