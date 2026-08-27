import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routing/app_router.dart';
import '../../../state/providers.dart';

/// Same look as the ARDMX4 tree's own `ConfigSubmenu`, but pointing at the
/// ARDMX EVO tree's own routes — kept as its own copy (not a shared
/// parametrized widget beyond the route list) per the project's own
/// decision: separate navigation per product, shared widgets/services
/// underneath.
class ArdmxEvoConfigSubmenu extends ConsumerWidget {
  const ArdmxEvoConfigSubmenu({
    super.key,
    required this.squareSize,
    required this.spacing,
  });

  final double squareSize;
  final double spacing;

  // Row-major over _columns: 1st row is Escenes/Cicle/Events/Paràmetres,
  // Simulació lands alone on the 2nd row (left-aligned — see build()'s
  // `mainAxisAlignment: start`).
  static const _items = [
    ('Escenes', AppRoutes.ardmxEvoSceneChannels),
    ('Cicle', AppRoutes.ardmxEvoCycleProgramming),
    ('Events', AppRoutes.ardmxEvoEvents),
    ('Paràmetres', AppRoutes.ardmxEvoParameters),
    ('Simulació', AppRoutes.ardmxEvoSimulacio),
  ];

  static const _columns = 4;

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

    Widget button(int i) => SizedBox(
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
    );

    // Same square grid as DialSelector's own rows (4 columns, wrapping row-
    // major) — a 5th item ("Events") lands on its own second row, under the
    // 1st column ("Simulació"), left-aligned (not `end` like the single
    // full row used to be: with only 4 items that row exactly filled the
    // width either way, but a shorter wrapped row needs `start` to land
    // under the first column instead of the last).
    final rows = <Widget>[];
    for (var start = 0; start < _items.length; start += _columns) {
      final end = (start + _columns).clamp(0, _items.length);
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (var i = start; i < end; i++) ...[
              if (i > start) SizedBox(width: spacing),
              button(i),
            ],
          ],
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}
