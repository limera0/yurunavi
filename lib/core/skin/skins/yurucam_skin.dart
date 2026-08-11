import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../skin.dart';
import 'default_skin.dart';

/// A안 — 새 기본(무료) 스킨. 코랄/파스텔 톤 "유루캠 무드".
/// 브랜드 방향성 확정(2026-07-29, loop/HANDOFF_0729_brand_skins.md) 3안 중 A.
class YuruCamSkin implements AppSkin {
  const YuruCamSkin();

  @override
  String get id => 'yurucam';

  @override
  String get displayName => '노을빛';

  @override
  bool get isPremium => false;

  @override
  SkinColors get colors => const _YuruCamColors();

  @override
  SkinTypography get typography => const DefaultSkinTypography();

  @override
  SkinMotion get motion => const DefaultSkinMotion();

  @override
  SkinShapes get shapes => const DefaultSkinShapes();

  @override
  ThemeData toThemeData() => AppTheme.light;
}

class _YuruCamColors implements SkinColors {
  const _YuruCamColors();

  @override
  Color get brand => const Color(0xFFE2896F);

  @override
  Color get onBrand => const Color(0xFFFFFFFF);

  @override
  Color get brandLight => const Color(0x26E2896F);

  @override
  Color get background => const Color(0xFFFBF1E7);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceVariant => const Color(0xFFF2E1D2);

  @override
  Color get onSurface => const Color(0xFF4A3B33);

  @override
  Color get onSurfaceVariant => const Color(0xFF8A776C);

  @override
  Color get danger => const Color(0xFFC94F3F);

  @override
  Color get warning => const Color(0xFFE8A63D);

  @override
  Color get success => const Color(0xFF6E9B6B);

  @override
  Color get routeLine => const Color(0xFFE2896F);

  // 안전 경고색은 스킨과 무관하게 항상 동일 — DefaultSkin과 같은 고정값.
  @override
  Color get structureAlert => const Color(0xFFFF8F00);

  @override
  Color get curveAlert => const Color(0xFFE64A19);

  @override
  Color get speedometerBg => surface;

  @override
  Map<int, Color> get courseLineColor => skinCourseLineColor;
}
