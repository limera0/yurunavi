import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── YuruNavi Design Token ─────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFFF28C28);    // Orange – action, active
  static const secondary = Color(0xFF1A2B3C);  // Dark Navy – appbar, text
  static const tertiary = Color(0xFF00B1F0);   // Light Blue – highlights

  // Background / Surface
  static const background = Color(0xFFF9F7F2); // Off-white scaffold
  static const surface = Colors.white;
  static const surfaceVariant = Color(0xFFF2F0EB);

  // Text
  static const onPrimary = Colors.white;
  static const onSecondary = Colors.white;
  static const textPrimary = Color(0xFF1A2B3C);
  static const textSecondary = Color(0xFF5A6A7A);
  static const textHint = Color(0xFFADB5BD);

  // Semantic
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFE53935);
  static const warning = Color(0xFFFFB300);

  // Map overlays
  static const mapCourse = Color(0xFF4CAF50);   // Green dots – recommended course
  static const mapCafe = Color(0xFFF28C28);     // Orange dots – cafe POI
  static const mapRoute = Color(0xFFF28C28);    // Route polyline
  static const mapOrigin = Color(0xFF4CAF50);   // Current location
  static const mapDestination = Color(0xFFE53935);

  // Daylight bar
  static const sunrise = Color(0xFFFFB300);
  static const sunset = Color(0xFF5C6BC0);
}

// ── Typography ────────────────────────────────────────────────────────────────

class AppTextStyles {
  AppTextStyles._();

  static TextStyle get headlineXL => GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle get headlineLG => GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get headlineMD => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  static TextStyle get titleSM => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyLG => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.6,
      );

  static TextStyle get bodyMD => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.5,
      );

  static TextStyle get labelLG => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.1,
      );

  static TextStyle get labelMD => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  static TextStyle get labelSM => GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );
}

// ── Night Mode Design Tokens ─────────────────────────────────────────────────
// Dark-navy palette for riding after EENT (civil dusk) — readable without
// blinding the rider's night-adapted eyes. Less extreme than Rider Mode.

class NightModeColors {
  NightModeColors._();

  static const background = Color(0xFF0F1923);     // dark navy scaffold
  static const surface = Color(0xFF1A2535);        // card / panel
  static const surfaceVariant = Color(0xFF1E2D40); // slightly elevated surface

  static const primary = Color(0xFFF28C28);    // keep brand orange
  static const secondary = Color(0xFF6BA3BE);  // muted slate blue
  static const tertiary = Color(0xFF00B1F0);   // light blue accent (same as day)

  static const textPrimary = Color(0xFFE0E8F0);
  static const textSecondary = Color(0xFF8EA8BC);
  static const textHint = Color(0xFF4A6070);

  // Map overlays
  static const mapRoute = Color(0xFFF28C28);
  static const mapOrigin = Color(0xFF4CAF50);
  static const mapDestination = Color(0xFFE53935);
  static const mapCourse = Color(0xFF4CAF50);

  static const error = Color(0xFFFF5252);
  static const warning = Color(0xFFFFB300);
  static const success = Color(0xFF4CAF50);

  // Daylight bar
  static const sunrise = Color(0xFFFFB300);
  static const sunset = Color(0xFF90CAF9);
}

// ── Rider Mode Design Tokens ──────────────────────────────────────────────────
// High-contrast palette optimised for direct sunlight on a handlebar mount.
// Pitch-black background eliminates glare; neon green + safety orange provide
// maximum contrast ratios (> 7:1 against black, WCAG AAA).

class RiderModeColors {
  RiderModeColors._();

  static const background = Color(0xFF000000);   // pure black – no glare
  static const surface = Color(0xFF0D0D0D);      // near-black panels
  static const surfaceVariant = Color(0xFF1A1A1A);

  static const primary = Color(0xFF00FF6A);      // neon green – action / route
  static const secondary = Color(0xFFFF6B00);    // safety orange – accent / POI
  static const tertiary = Color(0xFFFFD600);     // amber – warnings / distance

  static const textPrimary = Color(0xFFFFFFFF);  // white on black
  static const textSecondary = Color(0xFFCCCCCC);
  static const textHint = Color(0xFF777777);

  // Map overlays
  static const mapRoute = Color(0xFF00FF6A);
  static const mapOrigin = Color(0xFF00FF6A);
  static const mapDestination = Color(0xFFFF6B00);
  static const mapCourse = Color(0xFF00FF6A);

  static const error = Color(0xFFFF3B30);
  static const warning = Color(0xFFFFD600);
  static const success = Color(0xFF00FF6A);
}

class RiderModeTextStyles {
  RiderModeTextStyles._();

  // All styles are bold and oversized — readable at arm's length in sunlight.
  static const TextStyle headlineXL = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w900,
    color: RiderModeColors.textPrimary,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle headlineLG = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: RiderModeColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle headlineMD = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: RiderModeColors.textPrimary,
    height: 1.4,
  );

  static const TextStyle titleSM = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: RiderModeColors.textPrimary,
  );

  static const TextStyle bodyLG = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: RiderModeColors.textPrimary,
    height: 1.6,
  );

  static const TextStyle bodyMD = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: RiderModeColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle labelLG = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: RiderModeColors.textPrimary,
    letterSpacing: 0.3,
  );

  static const TextStyle labelMD = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: RiderModeColors.textPrimary,
  );

  static const TextStyle labelSM = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: RiderModeColors.textSecondary,
  );
}

// ── ThemeData ─────────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.tertiary,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.onPrimary,
        onSecondary: AppColors.onSecondary,
        onSurface: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleTextStyle: AppTextStyles.headlineMD.copyWith(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          textStyle: AppTextStyles.labelLG,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.secondary,
          textStyle: AppTextStyles.labelLG,
          side: const BorderSide(color: AppColors.secondary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTextStyles.labelLG,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.textHint),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.textHint.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: AppTextStyles.bodyMD.copyWith(color: AppColors.textSecondary),
        hintStyle: AppTextStyles.bodyMD.copyWith(color: AppColors.textHint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        shadowColor: AppColors.secondary.withValues(alpha: 0.08),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.textHint.withValues(alpha: 0.3),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: AppTextStyles.bodyMD.copyWith(color: Colors.white),
      ),
    );
  }

  /// Night Mode — dark navy palette for riding after civil dusk.
  /// Readable in the dark without blinding night-adapted eyes.
  static ThemeData get night {
    const cs = ColorScheme(
      brightness: Brightness.dark,
      primary: NightModeColors.primary,
      onPrimary: NightModeColors.background,
      secondary: NightModeColors.secondary,
      onSecondary: NightModeColors.background,
      tertiary: NightModeColors.tertiary,
      onTertiary: NightModeColors.background,
      surface: NightModeColors.surface,
      onSurface: NightModeColors.textPrimary,
      onSurfaceVariant: NightModeColors.textSecondary,
      error: NightModeColors.error,
      onError: NightModeColors.background,
      outline: NightModeColors.surfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: NightModeColors.background,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: NightModeColors.surface,
        foregroundColor: NightModeColors.textPrimary,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NightModeColors.primary,
          foregroundColor: NightModeColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
        ),
      ),
      cardTheme: const CardThemeData(
        color: NightModeColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: NightModeColors.surfaceVariant,
        thickness: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }

  /// High-Contrast Rider Mode — pitch black + neon green + safety orange.
  /// Designed for direct sunlight on a handlebar mount.
  static ThemeData get rider {
    const cs = ColorScheme(
      brightness: Brightness.dark,
      primary: RiderModeColors.primary,
      onPrimary: RiderModeColors.background,
      secondary: RiderModeColors.secondary,
      onSecondary: RiderModeColors.background,
      tertiary: RiderModeColors.tertiary,
      onTertiary: RiderModeColors.background,
      surface: RiderModeColors.surface,
      onSurface: RiderModeColors.textPrimary,
      error: RiderModeColors.error,
      onError: RiderModeColors.background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: RiderModeColors.background,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: RiderModeColors.surface,
        foregroundColor: RiderModeColors.textPrimary,
        centerTitle: false,
        titleTextStyle: RiderModeTextStyles.headlineMD,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: RiderModeColors.primary,
          foregroundColor: RiderModeColors.background,
          textStyle: RiderModeTextStyles.labelLG,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: RiderModeColors.primary,
          textStyle: RiderModeTextStyles.labelLG,
        ),
      ),
      cardTheme: const CardThemeData(
        color: RiderModeColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: RiderModeColors.textHint.withValues(alpha: 0.4),
        thickness: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        contentTextStyle: RiderModeTextStyles.bodyMD,
      ),
    );
  }
}

// ── Reusable Button Components ────────────────────────────────────────────────

/// Primary filled button
class YuruPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final IconData? icon;

  const YuruPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.width,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
        label: Text(label),
      ),
    );
  }
}

/// Inverted (dark navy filled) button
class YuruInvertedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double? width;

  const YuruInvertedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.secondary,
          foregroundColor: Colors.white,
          textStyle: AppTextStyles.labelLG,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
        ),
        child: Text(label),
      ),
    );
  }
}

/// Outlined (border only) button
class YuruOutlinedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final Widget? leading;

  const YuruOutlinedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.width,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Text(label),
          ],
        ),
      ),
    );
  }
}

/// Floating map control button (circular, white)
class YuruMapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? iconColor;
  final Color? bgColor;

  const YuruMapControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.iconColor,
    this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor ?? Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: size * 0.45,
          color: iconColor ?? AppColors.secondary,
        ),
      ),
    );
  }
}

/// Header icon button (square rounded, used in app header row)
class YuruHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  const YuruHeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withValues(alpha: 0.15) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 20,
          color: active ? AppColors.primary : AppColors.secondary,
        ),
      ),
    );
  }
}
