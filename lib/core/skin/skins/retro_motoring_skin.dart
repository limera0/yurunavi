import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../skin.dart';
import 'default_skin.dart';

/// B안 — 무료 스킨. 청록/머스터드 톤 "레트로 모터링".
/// 브랜드 방향성 확정(2026-07-29, loop/HANDOFF_0729_brand_skins.md) 3안 중 B.
class RetroMotoringSkin implements AppSkin {
  const RetroMotoringSkin();

  @override
  String get id => 'retro_motoring';

  @override
  String get displayName => '박하빛';

  @override
  bool get isPremium => false;

  @override
  SkinColors get colors => const _RetroMotoringColors();

  @override
  SkinTypography get typography => const DefaultSkinTypography();

  @override
  SkinMotion get motion => const DefaultSkinMotion();

  @override
  SkinShapes get shapes => const DefaultSkinShapes();

  @override
  ThemeData toThemeData() => AppTheme.light;
}

class _RetroMotoringColors implements SkinColors {
  const _RetroMotoringColors();

  @override
  Color get brand => const Color(0xFF78B4AC);

  @override
  Color get onBrand => const Color(0xFFFFFFFF);

  @override
  Color get brandLight => const Color(0x2678B4AC);

  @override
  Color get background => const Color(0xFFF4F0E6);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceVariant => const Color(0xFFEAE0CC);

  @override
  Color get onSurface => const Color(0xFF3C3A33);

  @override
  Color get onSurfaceVariant => const Color(0xFF837E70);

  @override
  Color get danger => const Color(0xFFC15B4E);

  @override
  Color get warning => const Color(0xFFD9A54A);

  @override
  Color get success => const Color(0xFF6FA37C);

  @override
  Color get routeLine => const Color(0xFF78B4AC);

  // 안전 경고색은 스킨과 무관하게 항상 동일 — DefaultSkin과 같은 고정값.
  @override
  Color get structureAlert => const Color(0xFFFF8F00);

  @override
  Color get curveAlert => const Color(0xFFE64A19);

  @override
  Color get speedometerBg => surface;

  @override
  Map<int, Color> get courseLineColor => const {
        0: Color(0xFF78B4AC),
        1: Color(0xFFC7A768),
        2: Color(0xFFDFA79E),
      };
}
