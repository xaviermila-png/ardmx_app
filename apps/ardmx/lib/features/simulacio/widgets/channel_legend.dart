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

/// 4-column grid below the chart, one entry per channel of the current
/// page (up to 12) — color swatch + name + a checkbox toggling that
/// channel's curve visibility. Visibility is purely local UI state (not
/// persisted/synced to the device) — see [SimulacioScreen]'s own
/// `_visible` list, reset every time the page changes.
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
        crossAxisCount: 4,
        childAspectRatio: 4.2,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return InkWell(
          onTap: () => onToggle(index),
          child: Row(
            children: [
              Checkbox(
                value: entry.visible,
                onChanged: (_) => onToggle(index),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 4),
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
                    fontSize: 11,
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
