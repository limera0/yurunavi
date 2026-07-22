import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../skin.dart';
import '../skins/default_skin.dart';

class SkinLoader {
  static Future<AppSkin> fromAsset(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _JsonSkin(map);
    } catch (_) {
      return const DefaultSkin();
    }
  }
}

// ---------------------------------------------------------------------------
// Top-level skin
// ---------------------------------------------------------------------------

class _JsonSkin implements AppSkin {
  final Map<String, dynamic> _map;

  const _JsonSkin(this._map);

  @override
  String get id => _map['id'] as String? ?? 'unknown';

  @override
  String get displayName => _map['displayName'] as String? ?? id;

  @override
  bool get isPremium => _map['isPremium'] as bool? ?? false;

  @override
  SkinColors get colors =>
      _JsonColors(_map['colors'] as Map<String, dynamic>? ?? {});

  @override
  SkinTypography get typography => const DefaultSkin().typography;

  @override
  SkinMotion get motion =>
      _JsonMotion(_map['motion'] as Map<String, dynamic>? ?? {});

  @override
  SkinShapes get shapes =>
      _JsonShapes(_map['shapes'] as Map<String, dynamic>? ?? {});

  @override
  ThemeData toThemeData() => const DefaultSkin().toThemeData();
}

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

class _JsonColors implements SkinColors {
  final Map<String, dynamic> _m;

  const _JsonColors(this._m);

  Color _get(String key, Color fallback) {
    final v = _m[key];
    if (v is String) return _parseColor(v);
    return fallback;
  }

  static Color _parseColor(String hex) {
    final s = hex.startsWith('#') ? hex.substring(1) : hex;
    if (s.length == 6) {
      return Color(int.parse('FF$s', radix: 16) | 0xFF000000);
    }
    if (s.length == 8) {
      return Color(int.parse(s, radix: 16));
    }
    return Colors.transparent;
  }

  static final _def = const DefaultSkin().colors;

  @override
  Color get brand => _get('brand', _def.brand);

  @override
  Color get onBrand => _get('onBrand', _def.onBrand);

  @override
  Color get brandLight => _get('brandLight', _def.brandLight);

  @override
  Color get background => _get('background', _def.background);

  @override
  Color get surface => _get('surface', _def.surface);

  @override
  Color get surfaceVariant => _get('surfaceVariant', _def.surfaceVariant);

  @override
  Color get onSurface => _get('onSurface', _def.onSurface);

  @override
  Color get onSurfaceVariant =>
      _get('onSurfaceVariant', _def.onSurfaceVariant);

  @override
  Color get danger => _get('danger', _def.danger);

  @override
  Color get warning => _get('warning', _def.warning);

  @override
  Color get success => _get('success', _def.success);

  @override
  Color get routeLine => _get('routeLine', _def.routeLine);

  @override
  Color get structureAlert => _get('structureAlert', _def.structureAlert);

  @override
  Color get curveAlert => _get('curveAlert', _def.curveAlert);

  @override
  Color get speedometerBg => _get('speedometerBg', _def.speedometerBg);
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

class _JsonMotion implements SkinMotion {
  final Map<String, dynamic> _m;

  const _JsonMotion(this._m);

  Duration _ms(String key, Duration fallback) {
    final v = _m[key];
    if (v is int) return Duration(milliseconds: v);
    if (v is double) return Duration(milliseconds: v.round());
    return fallback;
  }

  static final _def = const DefaultSkin().motion;

  @override
  Duration get fast => _ms('fast', _def.fast);

  @override
  Duration get standard => _ms('standard', _def.standard);

  @override
  Duration get slow => _ms('slow', _def.slow);

  @override
  Duration get pulse => _ms('pulse', _def.pulse);

  // Curves cannot be serialised from JSON — always use DefaultSkin values.
  @override
  Curve get defaultCurve => _def.defaultCurve;

  @override
  Curve get emphasizedCurve => _def.emphasizedCurve;
}

// ---------------------------------------------------------------------------
// Shapes
// ---------------------------------------------------------------------------

class _JsonShapes implements SkinShapes {
  final Map<String, dynamic> _m;

  const _JsonShapes(this._m);

  double _d(String key, double fallback) {
    final v = _m[key];
    if (v is num) return v.toDouble();
    return fallback;
  }

  static final _def = const DefaultSkin().shapes;

  @override
  double get radiusXS => _d('radiusXS', _def.radiusXS);

  @override
  double get radiusS => _d('radiusS', _def.radiusS);

  @override
  double get radiusM => _d('radiusM', _def.radiusM);

  @override
  double get radiusL => _d('radiusL', _def.radiusL);

  @override
  double get radiusXL => _d('radiusXL', _def.radiusXL);
}
