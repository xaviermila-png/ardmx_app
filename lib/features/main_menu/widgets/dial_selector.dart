import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../state/providers.dart';

/// The 7-position main rotary dial (V[11]). Rendered as a set of choice
/// chips rather than a literal radial dial graphic for this first vertical
/// slice — a custom dial widget can replace this later without touching
/// any state/protocol wiring.
class DialSelector extends ConsumerWidget {
  const DialSelector({super.key});

  static const _labels = {
    MainSelectorMode.automatic: 'Automàtic',
    MainSelectorMode.manual: 'Manual',
    MainSelectorMode.scene1: 'Escena 1',
    MainSelectorMode.scene2: 'Escena 2',
    MainSelectorMode.scene3: 'Escena 3',
    MainSelectorMode.scene4: 'Escena 4',
    MainSelectorMode.configuration: 'Configuració',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      appStateProvider.select((s) => s.mainSelector),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final mode in MainSelectorMode.values)
          ChoiceChip(
            label: Text(_labels[mode]!),
            selected: current == mode.vValue,
            onSelected: (_) =>
                ref.read(appStateProvider.notifier).selectMainMode(mode),
          ),
      ],
    );
  }
}
