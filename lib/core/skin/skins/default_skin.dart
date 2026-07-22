import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../skin.dart';

class DefaultSkin implements AppSkin {
  const DefaultSkin();

  @override
  String get id => 'default';

  @override
  String get displayName => '기본';

  @override
  bool get isPremium => false;

  @override
  SkinColors get colors => const _DefaultColors();

  @override
  SkinTypography get typography => const _DefaultTypography();

  @override
  SkinMotion get motion => const _DefaultMotion();

  @override
  SkinShapes get shapes => const _DefaultShapes();

  @override
  ThemeData toThemeData() => AppTheme.light;
}

class _DefaultColors implements SkinColors {
  const _DefaultColors();

  @override
  Color get brand => AppColors.primary; // 0xFFF28C28 Orange

  @override
  Color get onBrand => AppColors.onPrimary; // white

  @override
  Color get brandLight => const Color(0x26F28C28); // primary @ 15% alpha

  @override
  Color get background => AppColors.background;

  @override
  Color get surface => AppColors.surface;

  @override
  Color get surfaceVariant => AppColors.surfaceVariant;

  @override
  Color get onSurface => AppColors.textPrimary;

  @override
  Color get onSurfaceVariant => AppColors.textSecondary;

  @override
  Color get danger => AppColors.error;

  @override
  Color get warning => AppColors.warning;

  @override
  Color get success => AppColors.success;

  @override
  Color get routeLine => AppColors.mapRoute;

  @override
  Color get structureAlert => const Color(0xFFFF8F00); // Colors.amber.shade800

  @override
  Color get curveAlert => const Color(0xFFE64A19); // Colors.deepOrange.shade700

  @override
  Color get speedometerBg => AppColors.surface;
}

class _DefaultTypography implements SkinTypography {
  const _DefaultTypography();

  @override
  String get fontFamily => 'PlusJakartaSans';

  @override
  TextStyle get headlineXL =>
      GoogleFonts.plusJakartaSans(fontSize: 38, fontWeight: FontWeight.w800);

  @override
  TextStyle get headlineL =>
      GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700);

  @override
  TextStyle get headlineM =>
      GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700);

  @override
  TextStyle get bodyL =>
      GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w400);

  @override
  TextStyle get bodyM =>
      GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w400);

  @override
  TextStyle get labelM =>
      GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500);

  @override
  TextStyle get labelS =>
      GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500);

  @override
  TextStyle get mono => const TextStyle(
        fontFamily: 'monospace',
        fontSize: 28,
        fontWeight: FontWeight.bold,
      );
}

class _DefaultMotion implements SkinMotion {
  const _DefaultMotion();

  @override
  Duration get fast => const Duration(milliseconds: 150);

  @override
  Duration get standard => const Duration(milliseconds: 300);

  @override
  Duration get slow => const Duration(milliseconds: 600);

  @override
  Duration get pulse => const Duration(milliseconds: 700);

  @override
  Curve get defaultCurve => Curves.easeInOut;

  @override
  Curve get emphasizedCurve => Curves.easeOutCubic;
}

class _DefaultShapes implements SkinShapes {
  const _DefaultShapes();

  @override
  double get radiusXS => 8;

  @override
  double get radiusS => 14;

  @override
  double get radiusM => 16;

  @override
  double get radiusL => 20;

  @override
  double get radiusXL => 24;
}
