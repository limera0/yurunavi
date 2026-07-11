import 'package:flutter/material.dart';

import 'app_theme.dart' as legacy;

/// Every text style currently in [legacy.AppTextStyles], captured as an
/// interface so a purchased/commissioned redesign (new typeface, weights,
/// scale) can be swapped in later without touching call sites (once
/// they've been migrated — see app_theme_selector.dart).
///
/// Skeleton only: nothing consumes this yet. Screens still use
/// [legacy.AppTextStyles] directly.
abstract class YuruNaviTypography {
  TextStyle get headlineXL;
  TextStyle get headlineLG;
  TextStyle get headlineMD;
  TextStyle get titleSM;
  TextStyle get bodyLG;
  TextStyle get bodyMD;
  TextStyle get labelLG;
  TextStyle get labelMD;
  TextStyle get labelSM;
}

/// "Template #1" — wraps the type scale that's already live in
/// [legacy.AppTextStyles], unchanged. Formalizes the current visual
/// identity as the first swappable unit. Visual output is identical to
/// today's app; this is purely a naming/structure wrapper.
class ClassicYuruNaviTypography implements YuruNaviTypography {
  const ClassicYuruNaviTypography();

  @override
  TextStyle get headlineXL => legacy.AppTextStyles.headlineXL;
  @override
  TextStyle get headlineLG => legacy.AppTextStyles.headlineLG;
  @override
  TextStyle get headlineMD => legacy.AppTextStyles.headlineMD;
  @override
  TextStyle get titleSM => legacy.AppTextStyles.titleSM;
  @override
  TextStyle get bodyLG => legacy.AppTextStyles.bodyLG;
  @override
  TextStyle get bodyMD => legacy.AppTextStyles.bodyMD;
  @override
  TextStyle get labelLG => legacy.AppTextStyles.labelLG;
  @override
  TextStyle get labelMD => legacy.AppTextStyles.labelMD;
  @override
  TextStyle get labelSM => legacy.AppTextStyles.labelSM;
}
