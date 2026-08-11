import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../skin.dart';
import 'default_skin.dart';

/// C안 — 무료 스킨. 테라코타/네이비 톤 "동네 라이딩 메이트".
/// 브랜드 방향성 확정(2026-07-29, loop/HANDOFF_0729_brand_skins.md) 3안 중 C.
class CubBuddySkin implements AppSkin {
  const CubBuddySkin();

  @override
  String get id => 'cub_buddy';

  @override
  String get displayName => '황토빛';

  @override
  bool get isPremium => false;

  @override
  SkinColors get colors => const _CubBuddyColors();

  @override
  SkinTypography get typography => const DefaultSkinTypography();

  @override
  SkinMotion get motion => const DefaultSkinMotion();

  @override
  SkinShapes get shapes => const DefaultSkinShapes();

  @override
  ThemeData toThemeData() => AppTheme.light;
}

class _CubBuddyColors implements SkinColors {
  const _CubBuddyColors();

  @override
  Color get brand => const Color(0xFFC05F4C);

  @override
  Color get onBrand => const Color(0xFFFFFFFF);

  @override
  Color get brandLight => const Color(0x26C05F4C);

  @override
  Color get background => const Color(0xFFF9F4E9);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceVariant => const Color(0xFFF0E3C9);

  @override
  Color get onSurface => const Color(0xFF232A3B);

  @override
  Color get onSurfaceVariant => const Color(0xFF5B6270);

  @override
  Color get danger => const Color(0xFFB0362A);

  @override
  Color get warning => const Color(0xFFD98A3D);

  @override
  Color get success => const Color(0xFF4F6B58);

  @override
  Color get routeLine => const Color(0xFFC05F4C);

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
