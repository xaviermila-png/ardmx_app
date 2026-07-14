import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';

/// Shown only while the dial is on [MainSelectorMode.configuration] — a
/// third grid row using the same square sizing as the scene buttons above
/// it, so the whole 7(+4)-button layout reads as one consistent grid.
/// Navigating to any of these pushes the corresponding route, whose
/// [ScreenMirrorObserver] side effect writes V[50] for the app.
class ConfigSubmenu extends StatelessWidget {
  const ConfigSubmenu({
    super.key,
    required this.squareSize,
    required this.spacing,
  });

  final double squareSize;
  final double spacing;

  static const _items = [
    ('Escenes', AppRoutes.sceneChannels),
    ('Cicle', AppRoutes.cycleProgramming),
    ('Paràmetres', AppRoutes.parameters),
    ('Crèdits', AppRoutes.credits),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          SizedBox(
            width: squareSize,
            height: squareSize,
            child: ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(_items[i].$2),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                // Lighter pastel lilac than Configuració's own
                // (Colors.deepPurple.shade200) — these are its children, so
                // a weaker tint of the same hue reads as a visual family.
                backgroundColor: Colors.deepPurple.shade100,
                foregroundColor: Colors.deepPurple.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                _items[i].$1,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
