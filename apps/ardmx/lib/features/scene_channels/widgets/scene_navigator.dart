import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import 'nav_arrow_button.dart';

/// "<- Escena N ->" bar. The arrows write V[35] (scene-change order,
/// -1/0/+1); V[9] (active scene) is what the Arduino reports back and is
/// what's actually displayed.
class SceneNavigator extends ConsumerWidget {
  const SceneNavigator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeScene = ref.watch(
      appStateProvider.select((s) => s.activeScene),
    );

    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          NavArrowButton(
            icon: Icons.arrow_back,
            onPressed: () =>
                ref.read(appStateProvider.notifier).changeScene(-1),
          ),
          Expanded(
            child: Text(
              'Escena ${activeScene ?? '—'}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          NavArrowButton(
            icon: Icons.arrow_forward,
            onPressed: () => ref.read(appStateProvider.notifier).changeScene(1),
          ),
        ],
      ),
    );
  }
}
