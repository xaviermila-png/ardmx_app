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

  // Explicit rows (not a generic "wrap every N columns", unlike the EVO's
  // own submenu): 3 items on row 1 (right-aligned within the same 4-column
  // width as DialSelector's scene squares above, deliberately leaving the
  // 1st column empty rather than spreading them out), "Paràmetres" alone
  // on row 2, also right-aligned.
  static const _rows = [
    [
      ('Simulació', AppRoutes.ardmxOneV2Simulacio),
      ('Escenes', AppRoutes.ardmxOneV2SceneChannels),
      ('Cicle', AppRoutes.ardmxOneV2CycleProgramming),
    ],
    [('Paràmetres', AppRoutes.ardmxOneV2Parameters)],
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

    Widget button((String, String) item) => SizedBox(
      width: squareSize,
      height: squareSize,
      child: FilledButton(
        onPressed: (item.$1 == 'Cicle' && cicleDisabled)
            ? null
            : () => Navigator.of(context).pushNamed(item.$2),
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
          item.$1,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < _rows.length; r++) ...[
          if (r > 0) SizedBox(height: spacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var i = 0; i < _rows[r].length; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                button(_rows[r][i]),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
