import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/map_language.dart';
import '../../../services/language_service.dart';

final languageServiceProvider = Provider((_) => LanguageService());

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
