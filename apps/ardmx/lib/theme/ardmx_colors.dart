import 'package:flutter/material.dart';

/// The ARDMX brand palette. Everything the theme (see [ArdmxTheme]) or a
/// screen needs that isn't already exposed through `Theme.of(context)`
/// lives here — a single source of truth instead of colors hardcoded
/// inline across screens.
class ArdmxColors {
  const ArdmxColors._();

  static const primary = Color(0xFF5E35B1);
  static const secondary = Color(0xFF7E57C2);

  /// The 4 fader colors from the logo. Identity, not state — never derived
  /// from the theme, never swapped for [primary]/[secondary], and not
  /// meant to be reused for anything other than an actual DMX
  /// channel/fader (RGB wheel, channel sliders, transition-mode chips).
  static const channelBlue = Color(0xFF4285F4);
  static const channelRed = Color(0xFFEA4335);
  static const channelYellow = Color(0xFFFBBC05);
  static const channelGreen = Color(0xFF34A853);

  static const background = Color(0xFFFAFAFA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFF4F4F4);
  static const outline = Color(0xFFE5E7EB);
  static const textSecondary = Color(0xFF5F6368);
  static const textPrimary = Color(0xFF202124);
}
