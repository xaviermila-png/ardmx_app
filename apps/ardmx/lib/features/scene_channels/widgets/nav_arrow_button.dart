import 'package:flutter/material.dart';

/// A filled square (rounded-corner) icon button used for the "<-" / "->"
/// navigator controls — a plain [IconButton] on a colored bar doesn't read
/// as tappable, so this gives it a visible white-ish background.
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
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.25),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(10),
      ),
    );
  }
}
