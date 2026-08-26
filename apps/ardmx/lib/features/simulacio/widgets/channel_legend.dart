import 'package:flutter/material.dart';

/// One legend entry: a channel's assigned color, its name (or "Canal N" if
/// unnamed), and whether its curve is currently shown on the chart.
class LegendEntry {
  const LegendEntry({
    required this.color,
    required this.label,
    required this.visible,
  });

  final Color color;
  final String label;
  final bool visible;
}

/// 6-column grid below the chart, one entry per channel of the current
/// page (up to 12 — 2 full rows of 6, not 3 rows of 4) — color swatch +
/// name + a checkbox toggling that channel's curve visibility. 6 columns
/// instead of 4 so all 12 fit in 2 rows: with 4, the 3rd row fell outside
/// this widget's fixed height and silently never got painted (a
/// [GridView]'s viewport just doesn't render items past its own extent,
/// unlike a Row/Column which would visibly overflow) — confirmed on real
/// hardware: only 8 of 12 channels ever showed. 2 rows instead of 3 also
/// means this widget itself needs less height, freeing more of the screen
/// for the chart above.
///
/// Visibility is purely local UI state (not persisted/synced to the
/// device) — see [SimulacioScreen]'s own `_visible` list, reset every time
/// the page changes.
class ChannelLegend extends StatelessWidget {
  const ChannelLegend({
    super.key,
    required this.entries,
    required this.onToggle,
  });

  final List<LegendEntry> entries;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        childAspectRatio: 3.4,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return InkWell(
          onTap: () => onToggle(index),
          child: Row(
            children: [
              Transform.scale(
                scale: 0.8,
                child: Checkbox(
                  value: entry.visible,
                  onChanged: (_) => onToggle(index),
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: entry.visible
                      ? entry.color
                      : entry.color.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: entry.visible
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
