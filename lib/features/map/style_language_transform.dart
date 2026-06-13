import 'dart:convert';

import '../../models/map_language.dart';

const _languageLayerIds = <String>{
  'waterway-name', 'water-name-lakeline', 'water-name-other',
  'poi-level-3', 'poi-level-2', 'poi-level-1', 'poi-railway',
  'highway-name-path', 'highway-name-minor', 'highway-name-major',
  'airport-label-major', 'place-other', 'place-village', 'place-town',
  'place-city', 'place-city-capital',
  'water-name-ocean', 'place-state', 'place-country-other',
  'place-country-3', 'place-country-2', 'place-country-1', 'place-continent',
};

/// 23개 라벨 레이어의 text-field만 단일 언어 토큰으로 교체.
/// text-color / text-size / halo / symbol-placement 등 나머지 속성은 불변.
String applyMapLanguageToStyle(String styleJson, MapLanguage lang) {
  final token = switch (lang) {
    MapLanguage.korean  => '{name:nonlatin}',
    MapLanguage.english => '{name:latin}',
  };
  final root = jsonDecode(styleJson) as Map<String, dynamic>;
  final layers = (root['layers'] as List).cast<Map<String, dynamic>>();
  for (final layer in layers) {
    if (_languageLayerIds.contains(layer['id'])) {
      final layout = Map<String, dynamic>.from(
        (layer['layout'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      layout['text-field'] = token;
      layer['layout'] = layout;
    }
  }
  return jsonEncode(root);
}
