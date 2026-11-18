import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:aeris/shared/widgets/tr_text.dart';

class SensorTile extends StatelessWidget {
  final String name;
  final double? value;
  final String unit;
  final IconData icon;

  const SensorTile({
    super.key,
    required this.name,
    required this.value,
    required this.unit,
    required this.icon,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 4),
          TrText(
            value != null ? value!.toStringAsFixed(1) : '--',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: value != null
                      ? Theme.of(context).textTheme.headlineMedium?.color
                      : Colors.grey,
                ),
          ),
        ],
      ),
    );
  }
}
