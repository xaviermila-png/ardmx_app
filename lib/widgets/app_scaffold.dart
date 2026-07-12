import 'package:flutter/material.dart';

import 'connection_badge.dart';

/// Thin shared Scaffold so every screen shows the same [ConnectionBadge] in
/// its AppBar without repeating the wiring.
///
/// [automaticallyImplyLeading] defaults to true (normal back-arrow-to-parent
/// behavior for screens pushed on top of Main Menu, e.g. Escenes). Main Menu
/// itself — the base of the nav stack — sets it to false and supplies its
/// own back-to-connection-screen [floatingActionButton] instead, since a
/// default back arrow there would have nothing meaningful to pop to.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.automaticallyImplyLeading = true,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  final String title;
  final Widget body;
  final bool automaticallyImplyLeading;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: automaticallyImplyLeading,
        actions: const [ConnectionBadge(), SizedBox(width: 8)],
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }
}
