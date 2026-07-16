import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../state/providers.dart';
import 'config_submenu.dart';

/// The 7-position main rotary dial (V[11]), laid out as a square-ish grid:
/// row 1 is the 4 scene buttons (squares), row 2 is
/// Automàtic/Manual/Configuració (3 rectangles spanning the same total
/// width, and the same height, as row 1). Each active button gets a color
/// by category: scenes = pastel orange, Automàtic/Manual = pastel green,
/// Configuració = pastel lilac (which also reveals a third row of submenu
/// buttons: Escenes/Cicle/Paràmetres/Crèdits).
class DialSelector extends ConsumerWidget {
  const DialSelector({super.key});

  static const _spacing = 8.0;

  static const _sceneModes = [
    MainSelectorMode.scene1,
    MainSelectorMode.scene2,
    MainSelectorMode.scene3,
    MainSelectorMode.scene4,
  ];

  static const _otherModes = [
    MainSelectorMode.automatic,
    MainSelectorMode.manual,
    MainSelectorMode.configuration,
  ];

  static const _labels = {
    MainSelectorMode.automatic: 'Automàtic',
    MainSelectorMode.manual: 'Manual',
    MainSelectorMode.scene1: 'Escena 1',
    MainSelectorMode.scene2: 'Escena 2',
    MainSelectorMode.scene3: 'Escena 3',
    MainSelectorMode.scene4: 'Escena 4',
    MainSelectorMode.configuration: 'Configuració',
  };

  /// Looks up the button label for a raw V[11] value, e.g. for a title
  /// elsewhere on screen that reproduces the currently selected button.
  static String? labelFor(int? vValue) {
    for (final mode in MainSelectorMode.values) {
      if (mode.vValue == vValue) return _labels[mode];
    }
    return null;
  }

  static (Color, Color) _selectedColors(MainSelectorMode mode) {
    switch (mode) {
      case MainSelectorMode.configuration:
        return (Colors.deepPurple.shade200, Colors.deepPurple.shade900);
      case MainSelectorMode.automatic:
      case MainSelectorMode.manual:
        return (Colors.green.shade200, Colors.green.shade900);
      default:
        return (Colors.orange.shade200, Colors.orange.shade900);
    }
  }

  Widget _modeButton({
    required WidgetRef ref,
    required MainSelectorMode mode,
    required int? current,
    required double width,
    required double height,
  }) {
    final (bg, fg) = _selectedColors(mode);
    return _ModeButton(
      label: _labels[mode]!,
      width: width,
      height: height,
      selected: current == mode.vValue,
      selectedBackground: bg,
      selectedForeground: fg,
      onTap: () => ref.read(appStateProvider.notifier).selectMainMode(mode),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appStateProvider.select((s) => s.mainSelector));
    final isConfiguration = current == MainSelectorMode.configuration.vValue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final squareSize = (constraints.maxWidth - 3 * _spacing) / 4;
        final rectWidth = (constraints.maxWidth - 2 * _spacing) / 3;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < _sceneModes.length; i++) ...[
                  if (i > 0) const SizedBox(width: _spacing),
                  _modeButton(
                    ref: ref,
                    mode: _sceneModes[i],
                    current: current,
                    width: squareSize,
                    height: squareSize,
                  ),
                ],
              ],
            ),
            const SizedBox(height: _spacing),
            Row(
              children: [
                for (var i = 0; i < _otherModes.length; i++) ...[
                  if (i > 0) const SizedBox(width: _spacing),
                  _modeButton(
                    ref: ref,
                    mode: _otherModes[i],
                    current: current,
                    width: rectWidth,
                    height: squareSize,
                  ),
                ],
              ],
            ),
            const SizedBox(height: _spacing),
            // Space for the third row is always reserved (not just when
            // visible) so showing/hiding it never shifts the rows above —
            // only its content fades in/out.
            Visibility(
              visible: isConfiguration,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: ConfigSubmenu(squareSize: squareSize, spacing: _spacing),
            ),
          ],
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.width,
    required this.height,
    required this.selected,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.onTap,
  });

  final String label;
  final double width;
  final double height;
  final bool selected;
  final Color selectedBackground;
  final Color selectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          backgroundColor: selected ? selectedBackground : null,
          foregroundColor: selected ? selectedForeground : null,
          elevation: selected ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
