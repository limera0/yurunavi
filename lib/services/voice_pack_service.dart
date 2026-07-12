import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoicePackService {
  final Map<String, String> _templates;
  final FlutterTts _tts;
  Future<void> _queue = Future.value();

  VoicePackService._(this._templates, this._tts);

  static Future<VoicePackService> load(String assetPath, FlutterTts tts) async {
    final raw = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final templates = (data['templates'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
    return VoicePackService._(templates, tts);
  }

  // Returns resolved template text with _fast → base-key fallback for pack compat.
  static String? resolveTemplate(Map<String, String> templates, String key) {
    final t = templates[key];
    if (t != null) return t;
    if (key.endsWith('_fast')) {
      return templates[key.substring(0, key.length - 5)];
    }
    if (key.endsWith('_named')) {
      return templates[key.substring(0, key.length - 6)];
    }
    return null;
  }

  // 겹치는 speak() 호출이 네이티브로 동시에 나가면 flutter_tts의 단일
  // audioFocusRequest 변수가 덮어써져 이전 발화의 오디오 포커스가 leak된다
  // (블루투스 음악 덕킹 미복구 버그). 내부 큐로 직렬화해 항상 이전 발화가
  // 끝난 뒤에만 다음 _tts.speak()가 나가도록 강제한다. 한 발화가 에러가
  // 나도 체인은 끊기지 않고 다음 speak를 막지 않는다.
  Future<void> speak(String key, {Map<String, String> vars = const {}}) {
    final template = resolveTemplate(_templates, key);
    if (template == null) return Future.value();
    var text = template;
    for (final entry in vars.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    // flutter_tts 4.2.5 네이티브 결함: onError(utteranceId[, code])가
    // speakCompletion()을 호출하지 않아 speak()의 Future가 영원히 안 끝나는
    // 경우가 있다(onDone/onStop이 아닌 onError 경로). 타임아웃 없이는 그
    // 순간 이 큐가 영구히 막혀 이후 모든 발화가 조용히 먹통이 된다 —
    // 가장 긴 안내 문구보다 넉넉한 8초로 강제 settle시킨다.
    final task = _queue.then((_) => _tts
        .speak(text, focus: true)
        .timeout(const Duration(seconds: 8), onTimeout: () => null));
    _queue = task.then((_) {}, onError: (_) {});
    return task.then((_) {}, onError: (_) {});
  }
}
