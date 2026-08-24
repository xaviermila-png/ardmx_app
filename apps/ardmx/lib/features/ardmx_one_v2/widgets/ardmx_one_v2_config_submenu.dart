import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routing/app_router.dart';
import '../../../state/providers.dart';

/// Same look as the ARDMX EVO tree's own `ArdmxEvoConfigSubmenu`, pointing
/// at the ARDMX One v2 tree's own routes — kept as its own copy (not a
/// shared parametrized widget beyond the route list) per the project's own
/// decision: separate navigation per product, shared widgets/services
/// underneath.
class ArdmxOneV2ConfigSubmenu extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // "Cicle" (programming transitions/timings between scenes) makes no
    // sense with a single active scene — there's nothing to cycle between.
    // Firmware already refuses to run automatic mode in that case (kicks
    // V11 back to "Escena 1" — see loop() in main.cpp), so this just makes
    // that limit visible up front instead of a screen that opens but does
    // nothing useful.
    final activeScenesCount = ref.watch(
      appStateProvider.select((s) => s.activeScenesCount),
    );
    final cicleDisabled = activeScenesCount == 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          SizedBox(
            width: squareSize,
            height: squareSize,
            child: FilledButton(
              onPressed: (_items[i].$1 == 'Cicle' && cicleDisabled)
                  ? null
                  : () => Navigator.of(context).pushNamed(_items[i].$2),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                // A flat backgroundColor/foregroundColor doesn't dim
                // itself when onPressed is null — needs explicit disabled
                // colors or the button would look identical, just
                // silently unresponsive.
                disabledBackgroundColor: scheme.primaryContainer.withValues(
                  alpha: 0.4,
                ),
                disabledForegroundColor: scheme.onPrimaryContainer.withValues(
                  alpha: 0.38,
                ),
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
