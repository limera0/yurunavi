import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_language.dart';

class LanguageService {
  static const _key = 'map_language_v1';

  Future<MapLanguage> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return switch (raw) {
      'english' => MapLanguage.english,
      _ => MapLanguage.korean,
    };
  }

  Future<void> save(MapLanguage l) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, l.name);
  }
}
