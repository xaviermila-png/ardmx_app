import 'package:flutter/material.dart';

/// A filled square (rounded-corner) icon button used for the "<-" / "->"
/// navigator controls — a plain [IconButton] on a colored bar doesn't read
/// as tappable, so this gives it a visible translucent background. Sits on
/// bars that are always `colorScheme.primary` (see [SceneNavigator]/
/// `ChannelNumberBar`), so `onPrimary` is the correct foreground here.
class NavArrowButton extends StatelessWidget {
  const NavArrowButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: onPrimary.withValues(alpha: 0.25),
        foregroundColor: onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(10),
        // Visually this is ~44dp (24dp icon + 10dp padding); explicit
        // minimumSize brings the actual tappable area up to the 48dp WCAG
        // 2.5.5/2.5.8 minimum without changing how it looks.
        minimumSize: const Size(48, 48),
      ),
    );
  }
}
