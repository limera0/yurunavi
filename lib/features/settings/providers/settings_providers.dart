import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/map_language.dart';
import '../../../services/language_service.dart';

final languageServiceProvider = Provider((_) => LanguageService());

// ── 내비 지도 방향 (헤딩업=true 기본, 노스업=false) ─────────────────────────
final navHeadingUpProvider =
    AsyncNotifierProvider<NavHeadingUpNotifier, bool>(NavHeadingUpNotifier.new);

class NavHeadingUpNotifier extends AsyncNotifier<bool> {
  static const _key = 'nav_heading_up_v1';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool headingUp) async {
    state = AsyncData(headingUp);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, headingUp);
  }
}

final mapLanguageProvider =
    AsyncNotifierProvider<MapLanguageNotifier, MapLanguage>(
        MapLanguageNotifier.new);

class MapLanguageNotifier extends AsyncNotifier<MapLanguage> {
  @override
  Future<MapLanguage> build() async =>
      ref.read(languageServiceProvider).load();

  Future<void> setLanguage(MapLanguage l) async {
    await ref.read(languageServiceProvider).save(l);
    state = AsyncData(l);
  }
}
