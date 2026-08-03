import 'package:flutter/material.dart';

import 'connection_badge.dart';

/// Thin shared Scaffold so every screen shows the same MD3 [AppBar] — back
/// arrow on the left, title, [ConnectionBadge] (and, for the two device
/// "home" screens, a Sortir action) on the right — without repeating the
/// wiring. Replaces the previous design of loose [FloatingActionButton]s
/// scattered in each screen's body for back/exit.
///
/// [onBack] is required rather than defaulting to a plain `Navigator.pop()`:
/// several screens need to run something first (validate a field, disarm a
/// factory-reset toggle, redirect to Splash instead of popping) — passing it
/// explicitly keeps that logic at the call site instead of hiding a special
/// case inside this shared widget.
///
/// [onExit] is null on every screen except the two device "home" screens
/// (ARDMX One, ARDMX4 EVO Main Menu) — Sortir (disconnect + close the app)
/// is only ever offered there (and on Splash, which doesn't use this widget
/// at all), not on every secondary screen; getting back to a home screen is
/// just a matter of tapping the back arrow a few times.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.onBack,
    this.onExit,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  final String title;
  final Widget body;
  final VoidCallback onBack;
  final VoidCallback? onExit;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
          tooltip: 'Enrere',
        ),
        actions: [
          if (onExit != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: onExit,
              tooltip: 'Sortir',
            ),
          const ConnectionBadge(),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: body),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }
}
