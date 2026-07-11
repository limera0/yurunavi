/// A basic spacing scale, part of the same swappable design-token bundle as
/// `YuruNaviPalette` / `YuruNaviTypography` (see palette.dart /
/// typography.dart). Nothing in the app currently reads tokenized spacing —
/// screens still use raw `EdgeInsets`/`SizedBox` literals — so this exists
/// purely as scaffolding for the future migration.
abstract class YuruNaviSpacing {
  double get xs;
  double get sm;
  double get md;
  double get lg;
  double get xl;
}

/// "Template #1" — default 4/8-based scale, chosen to match the spacing
/// values already most common throughout the app's existing
/// `EdgeInsets`/`SizedBox` literals (4, 8, 16, 24, ...). Not derived from any
/// single existing constant (there was no prior `AppSpacing` class to wrap),
/// but picked to be a drop-in match for current visual spacing.
class ClassicYuruNaviSpacing implements YuruNaviSpacing {
  const ClassicYuruNaviSpacing();

  @override
  double get xs => 4;
  @override
  double get sm => 8;
  @override
  double get md => 16;
  @override
  double get lg => 24;
  @override
  double get xl => 32;
}
