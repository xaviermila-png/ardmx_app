import 'package:flutter/material.dart';

/// A tappable numeric/text value that opens an edit dialog — styled as a
/// clearly-a-field control (outlined, pencil icon) rather than a solid
/// [FilledButton], so it doesn't read as a real action button (e.g.
/// "Connectar", "Canviar nom") at a glance. Used for every tap-to-edit value
/// across the app (channel counts, cycle transition times, ...) so they all
/// share one consistent "this is an editable field" visual language.
class EditableValueChip extends StatelessWidget {
  const EditableValueChip({
    super.key,
    required this.value,
    required this.onTap,
    this.width,
    this.height,
    this.valueFontSize = 22,
    this.iconSize = 16,
    this.dense = false,
  });

  final String value;
  final VoidCallback onTap;
  final double? width;

  /// Fixes the button's footprint instead of letting it shrink-wrap the
  /// text — needed wherever several of these sit in a column (e.g. one per
  /// cycle transition row): a content-sized width/height made the button
  /// (and anything laid out relative to it in the same row, like the on/lit
  /// dot) visibly shift between rows as the value's digit count changed.
  final double? height;
  final double valueFontSize;
  final double iconSize;

  /// Shrinks padding and drops Material's default ~48px minimum tap target,
  /// for tight contexts like one row per cycle transition (8 of these
  /// stacked vertically) where the standard button sizing was tall enough
  /// to push the list into scrolling.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: scheme.primary, width: 1.5),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 4 : 10,
            vertical: dense ? 2 : 6,
          ),
          minimumSize: dense ? Size.zero : null,
          tapTargetSize: dense
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              SizedBox(width: iconSize / 4),
              Icon(Icons.edit, size: iconSize, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
