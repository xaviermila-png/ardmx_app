import 'package:flutter/material.dart';

/// A filled square (rounded-corner) icon button used for the "<-" / "->"
/// navigator controls — a plain [IconButton] on a colored bar doesn't read
/// as tappable, so this gives it a visible translucent background. Sits on
/// colored bars ([SceneNavigator]'s `secondary`, `ChannelNumberBar`'s
/// `primary`) — [foregroundColor] defaults to `onPrimary` since that's the
/// more common case, but [SceneNavigator] passes `onSecondary` to match its
/// own bar color (the two bars were deliberately given different brand
/// colors so they don't blend together visually, sitting right on top of
/// each other on the Scene/Channels screen).
class NavArrowButton extends StatelessWidget {
  const NavArrowButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? Theme.of(context).colorScheme.onPrimary;
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: fg.withValues(alpha: 0.25),
        foregroundColor: fg,
        // Explicit disabled colors — passing null to onPressed (e.g. at
        // the first/last scene) needs to visibly read as unavailable,
        // not just silently stop responding to taps.
        disabledBackgroundColor: fg.withValues(alpha: 0.08),
        disabledForegroundColor: fg.withValues(alpha: 0.3),
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
