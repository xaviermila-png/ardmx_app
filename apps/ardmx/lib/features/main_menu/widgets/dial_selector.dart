import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../state/providers.dart';

/// The 7-position main rotary dial (V[11]), laid out as a square-ish grid:
/// row 1 is the 4 scene buttons (squares), row 2 is
/// Automàtic/Manual/Configuració (3 rectangles spanning the same total
/// width, and the same height, as row 1). The active button always gets
/// the theme's `primaryContainer`/`onPrimaryContainer` (previously a
/// different ad-hoc color per category — orange for scenes, green for
/// Automàtic/Manual — now unified on-brand). Configuració also reveals a
/// third row of submenu buttons: Escenes/Cicle/Paràmetres/Crèdits.
class DialSelector extends ConsumerWidget {
  const DialSelector({super.key, required this.submenuBuilder});

  /// Builds the third row's submenu (Escenes/Cicle/Paràmetres), given the
  /// same square size/spacing used for the rest of the grid. This app only
  /// has the ARDMX EVO tree using this widget, pointing at its own routes
  /// ([ArdmxEvoConfigSubmenu]) — required (no default) since there's no
  /// shared "ARDMX4" submenu in this app to fall back to.
  final Widget Function(double squareSize, double spacing) submenuBuilder;

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

  Widget _modeButton({
    required WidgetRef ref,
    required MainSelectorMode mode,
    required int? current,
    required double width,
    required double height,
  }) {
    return _ModeButton(
      label: _labels[mode]!,
      width: width,
      height: height,
      selected: current == mode.vValue,
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
              child: submenuBuilder(squareSize, _spacing),
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
    required this.onTap,
  });

  final String label;
  final double width;
  final double height;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Merges into FilledButton's own auto-generated "button" semantics
    // (same node — Semantics here doesn't force a new container) so a
    // screen reader gets "label, selected/not selected, button" instead of
    // relying on the visual-only color/border cue for which mode is active.
    return Semantics(
      selected: selected,
      child: SizedBox(
        width: width,
        height: height,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            backgroundColor: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            foregroundColor: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
            elevation: selected ? 4 : 1,
            // The selected state isn't color/elevation alone: a visible
            // border and bold text carry the same information non-visually
            // distinguishable-color-blind-safe way too.
            side: selected
                ? BorderSide(color: scheme.primary, width: 2)
                : BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          // FittedBox instead of maxLines+ellipsis: this button has a
          // fixed width/height from the parent SizedBox, so at a large
          // system text scale (150-200%) the label needs to shrink to fit
          // rather than get clipped mid-word.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
