import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:aeris/shared/widgets/tr_text.dart';

class SensorTile extends StatelessWidget {
  final String name;
  final double? value;
  final String unit;
  final IconData icon;

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
    this.caption,
    this.valueSuffix,
    this.decimals = 1,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: AppTheme.cardDecoration(darkMode: isDark),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                icon,
                color: AppTheme.primaryColor,
                size: 24,
              ),
              if (unit.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TrText(
                    unit,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          TrText(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              TrText(
                value != null ? value!.toStringAsFixed(decimals) : '--',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: value != null
                          ? Theme.of(context).textTheme.headlineMedium?.color
                          : Colors.grey,
                    ),
              ),
              if (value != null && valueSuffix != null) ...[
                const SizedBox(width: 6),
                Text(
                  valueSuffix!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              ],
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            TrText(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
