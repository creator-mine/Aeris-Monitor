import 'package:flutter/material.dart';
import '../../../models/device.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/helpers/device_helper.dart';
import 'package:aeris/shared/widgets/tr_text.dart';

class DeviceCard extends StatelessWidget {
  final Device device;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onRename;

  const DeviceCard({
    super.key,
    required this.device,
    this.isSelected = false,
    this.onTap,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onRename,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 140,
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor
              : (isDark ? Colors.grey[850] : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : (isDark ? Colors.grey[700]! : Colors.grey.shade200),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  DeviceHelper.getDeviceIcon(device.type),
                  color: isSelected ? Colors.white : AppTheme.primaryColor,
                  size: 24,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: device.isOnline
                            ? AppTheme.successColor
                            : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (onRename != null) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onRename,
                        child: Icon(
                          Icons.edit_outlined,
                          size: 15,
                          color: isSelected ? Colors.white70 : Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const Spacer(),
            TrText(
              device.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).textTheme.bodyLarge?.color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            TrText(
              device.type.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
