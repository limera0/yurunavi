import 'package:flutter/material.dart';

import 'app_theme.dart' as legacy;

/// Every color slot the app currently themes through [legacy.AppColors] /
/// [legacy.courseLineColor], captured as an interface so a purchased or
/// commissioned redesign can be swapped in later without touching call
/// sites (once they've been migrated — see app_theme_selector.dart).
///
/// Skeleton only: nothing consumes this yet. Screens still use
/// [legacy.AppColors] directly.
abstract class YuruNaviPalette {
  // Brand
  Color get primary;
  Color get secondary;
  Color get tertiary;

  // Background / Surface
  Color get background;
  Color get surface;
  Color get surfaceVariant;

  // Text
  Color get onPrimary;
  Color get onSecondary;
  Color get textPrimary;
  Color get textSecondary;
  Color get textHint;

  // Semantic
  Color get success;
  Color get error;
  Color get warning;

  // Map overlays
  Color get mapCourse;
  Color get mapCafe;
  Color get mapRoute;
  Color get mapOrigin;
  Color get mapDestination;

  // Daylight bar
  Color get sunrise;
  Color get sunset;

  /// Route-line color keyed by course index (0: 시골길/rural-scenic,
  /// 1: 지방도/regional, 2: 국도/national-fast). Mirrors the top-level
  /// `courseLineColor` map in app_theme.dart.
  Map<int, Color> get courseLineColor;
}

/// "Template #1" — wraps the palette that's already live in
/// [legacy.AppColors] / [legacy.courseLineColor], unchanged. Formalizes the
/// current visual identity as the first swappable unit. Visual output is
/// identical to today's app; this is purely a naming/structure wrapper.
class ClassicYuruNaviPalette implements YuruNaviPalette {
  const ClassicYuruNaviPalette();

  @override
  Color get primary => legacy.AppColors.primary;
  @override
  Color get secondary => legacy.AppColors.secondary;
  @override
  Color get tertiary => legacy.AppColors.tertiary;

  @override
  Color get background => legacy.AppColors.background;
  @override
  Color get surface => legacy.AppColors.surface;
  @override
  Color get surfaceVariant => legacy.AppColors.surfaceVariant;

  @override
  Color get onPrimary => legacy.AppColors.onPrimary;
  @override
  Color get onSecondary => legacy.AppColors.onSecondary;
  @override
  Color get textPrimary => legacy.AppColors.textPrimary;
  @override
  Color get textSecondary => legacy.AppColors.textSecondary;
  @override
  Color get textHint => legacy.AppColors.textHint;

  @override
  Color get success => legacy.AppColors.success;
  @override
  Color get error => legacy.AppColors.error;
  @override
  Color get warning => legacy.AppColors.warning;

  @override
  Color get mapCourse => legacy.AppColors.mapCourse;
  @override
  Color get mapCafe => legacy.AppColors.mapCafe;
  @override
  Color get mapRoute => legacy.AppColors.mapRoute;
  @override
  Color get mapOrigin => legacy.AppColors.mapOrigin;
  @override
  Color get mapDestination => legacy.AppColors.mapDestination;

  @override
  Color get sunrise => legacy.AppColors.sunrise;
  @override
  Color get sunset => legacy.AppColors.sunset;

  @override
  Map<int, Color> get courseLineColor => legacy.courseLineColor;
}
