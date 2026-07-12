import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';

/// Shown only while the dial is on [MainSelectorMode.configuration].
/// Navigating to any of these pushes the corresponding route, whose
/// [ScreenMirrorObserver] side effect writes V[50] for the app.
class ConfigSubmenu extends StatelessWidget {
  const ConfigSubmenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.sceneChannels),
          child: const Text('Escenes'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.cycleProgramming),
          child: const Text('Cicle'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.parameters),
          child: const Text('Paràmetres'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.credits),
          child: const Text('Crèdits'),
        ),
      ],
    );
  }
}
