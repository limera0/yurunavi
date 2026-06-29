import 'package:yurunavi/models/map_language.dart';

class PoiNameResolver {
  const PoiNameResolver(this._language);

  final MapLanguage _language;

  String? resolve(Map<String, dynamic> props) {
    final key = _language == MapLanguage.korean ? 'name:nonlatin' : 'name:latin';
    final preferred = props[key];
    if (preferred is String && preferred.isNotEmpty) return preferred;
    final fallback = props['name'];
    if (fallback is String && fallback.isNotEmpty) return fallback;
    return null;
  }
}
