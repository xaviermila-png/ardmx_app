import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ardmx_colors.dart';

/// Centralized MD3 theme — every screen pulls its colors/typography from
/// `Theme.of(context)` (or the [ArdmxColors] constants directly for the
/// handful of brand-identity colors that aren't part of a [ColorScheme]
/// role) instead of hardcoding Material's generic palette (`Colors.green`,
/// `Colors.orange`...) inline.
class ArdmxTheme {
  const ArdmxTheme._();

  static ColorScheme get _lightScheme =>
      ColorScheme.fromSeed(
        seedColor: ArdmxColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: ArdmxColors.primary,
        secondary: ArdmxColors.secondary,
        surface: ArdmxColors.surface,
        surfaceContainerHighest: ArdmxColors.surfaceVariant,
        onSurface: ArdmxColors.textPrimary,
        onSurfaceVariant: ArdmxColors.textSecondary,
        outline: ArdmxColors.outline,
      );

  static ColorScheme get _darkScheme => ColorScheme.fromSeed(
    seedColor: ArdmxColors.primary,
    brightness: Brightness.dark,
  ).copyWith(primary: ArdmxColors.secondary, secondary: ArdmxColors.primary);

  static ThemeData get light => _build(_lightScheme, ArdmxColors.background);

  static ThemeData get dark =>
      _build(_darkScheme, _darkScheme.surface);

  static ThemeData _build(ColorScheme scheme, Color scaffoldBackground) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scaffoldBackground,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        titleTextStyle: GoogleFonts.poppins(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      // TextField's default OutlineInputBorder pulls its color from
      // colorScheme.outline when no border is set explicitly — but that
      // role is ArdmxColors.outline (#E5E7EB), deliberately very light for
      // subtle dividers/card edges, which left every plain-bordered
      // TextField in the app nearly invisible. Give inputs their own,
      // clearly visible border colors instead of reusing that role.
      inputDecorationTheme: InputDecorationTheme(
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.onSurfaceVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }
}
