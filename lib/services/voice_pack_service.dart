import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoicePackService {
  final Map<String, String> _templates;
  final FlutterTts _tts;

  VoicePackService._(this._templates, this._tts);

  static Future<VoicePackService> load(String assetPath, FlutterTts tts) async {
    final raw = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final templates = (data['templates'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
    return VoicePackService._(templates, tts);
  }

  Future<void> speak(String key, {Map<String, String> vars = const {}}) async {
    final template = _templates[key];
    if (template == null) return;
    var text = template;
    for (final entry in vars.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    await _tts.speak(text);
  }
}
