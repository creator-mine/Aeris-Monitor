import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:aeris/shared/widgets/tr_text.dart';

class SensorTile extends StatelessWidget {
  final String name;
  final double? value;
  final String unit;
  final IconData icon;
  final Color? color;

  /// Optional small line under the value, for example the IAQ calibration
  /// level ("Калибровка 2/3"). Kept short so the tile still fits the grid.
  final String? caption;

  /// Optional suffix rendered on the same line as the value, for the IAQ
  /// scale ("из 500" next to 99).
  final String? valueSuffix;

  /// IAQ is an index (0..500), temperature/humidity look better with one
  /// decimal. The caller decides per metric.
  final int decimals;

  const SensorTile({
    super.key,
    required this.name,
    required this.value,
    required this.unit,
    required this.icon,
    this.color,
    this.caption,
    this.valueSuffix,
    this.decimals = 1,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = color ?? palette.primary;
    final hasValue = value != null;

    return Container(
      decoration: AppTheme.cardDecoration(
        darkMode: Theme.of(context).brightness == Brightness.dark,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              const Spacer(),
              if (unit.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.border),
                  ),
                  child: TrText(
                    unit,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: palette.muted,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: TrText(
                  hasValue ? value!.toStringAsFixed(decimals) : '--',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: hasValue ? palette.text : palette.faint,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (hasValue && valueSuffix != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: TrText(
                    valueSuffix!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.muted,
                        ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          TrText(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.muted,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            TrText(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: palette.faint,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
