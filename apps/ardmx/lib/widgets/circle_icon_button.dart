import 'package:flutter/material.dart';

/// A circular-background icon button used for playback controls.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    this.iconSize,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: iconSize),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        // Flat colors don't dim themselves when onPressed is null (the
        // page-nav arrows at the first/last group) — needs explicit
        // disabled colors or a disabled button would look identical to an
        // enabled one, just unresponsive.
        disabledBackgroundColor: backgroundColor.withValues(alpha: 0.3),
        disabledForegroundColor: foregroundColor.withValues(alpha: 0.38),
      ),
    );
  }
}
