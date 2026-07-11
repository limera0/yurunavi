// ── YuruNavi Theme Selector (skeleton) ──────────────────────────────────────
//
// WHAT THIS IS FOR
// -----------------
// This is the single switch that will let a future purchased/commissioned
// visual redesign (new palette + typography, eventually icon/mood too) be
// swapped into the app without rewriting every screen. Today, `AppColors` /
// `AppTextStyles` / `courseLineColor` in app_theme.dart are still what every
// screen under lib/features/* actually reads (see palette.dart /
// typography.dart doc comments) — this selector doesn't change that yet. It
// exists purely so there's a clear, obvious seam to migrate onto later.
//
// HOW TO ADD A NEW PURCHASED PALETTE (future work)
// ----------------------------------------------------
//   1. Implement `YuruNaviPalette` and `YuruNaviTypography` (see palette.dart
//      / typography.dart) with the new design's values, e.g.:
//        class SunsetYuruNaviPalette implements YuruNaviPalette { ... }
//        class SunsetYuruNaviTypography implements YuruNaviTypography { ... }
//   2. (Optional) implement `YuruNaviSpacing` too if the new design needs a
//      different scale; otherwise it can keep reusing
//      `ClassicYuruNaviSpacing`.
//   3. Flip the three `active*` fields below to point at the new
//      implementations. That's the one edit needed to register it.
//
// WHAT THIS DOES NOT DO YET
// ------------------------------
// Nothing in lib/features/* reads through this selector today — screens
// still call `AppColors.primary` / `AppTextStyles.bodyMD` directly, and this
// file is not imported anywhere else in the app. Migrating every call site
// to instead go through `AppThemeSelector.activePalette.primary` etc. is a
// separate, later task; this file only sets up the target to migrate toward.
//
// Deliberately plain Dart (no plugin loading / JSON-driven runtime theming /
// marketplace system) — there's only one real palette to prove the
// abstraction against so far, so keeping this minimal until a second one
// exists.

import 'palette.dart';
import 'spacing.dart';
import 'typography.dart';

/// The one place a future session flips to swap in a new purchased design.
class AppThemeSelector {
  AppThemeSelector._();

  static const YuruNaviPalette activePalette = ClassicYuruNaviPalette();
  static const YuruNaviTypography activeTypography =
      ClassicYuruNaviTypography();
  static const YuruNaviSpacing activeSpacing = ClassicYuruNaviSpacing();
}
