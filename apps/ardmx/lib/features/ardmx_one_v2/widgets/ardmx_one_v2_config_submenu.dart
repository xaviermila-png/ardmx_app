import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';

/// Same look as the ARDMX EVO tree's own `ArdmxEvoConfigSubmenu`, pointing
/// at the ARDMX One v2 tree's own routes — kept as its own copy (not a
/// shared parametrized widget beyond the route list) per the project's own
/// decision: separate navigation per product, shared widgets/services
/// underneath.
class ArdmxOneV2ConfigSubmenu extends StatelessWidget {
  const ArdmxOneV2ConfigSubmenu({
    super.key,
    required this.squareSize,
    required this.spacing,
  });

  final double squareSize;
  final double spacing;

  static const _items = [
    ('Escenes', AppRoutes.ardmxOneV2SceneChannels),
    ('Cicle', AppRoutes.ardmxOneV2CycleProgramming),
    ('Paràmetres', AppRoutes.ardmxOneV2Parameters),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          SizedBox(
            width: squareSize,
            height: squareSize,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pushNamed(_items[i].$2),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
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
