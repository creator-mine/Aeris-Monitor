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
    final palette = AppPalette.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final online = device.isOnline;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onRename,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 168,
        decoration: BoxDecoration(
          color: isSelected ? palette.surfaceAlt : palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? primary : palette.border,
            width: isSelected ? 1.6 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (isSelected ? primary : palette.muted)
                        .withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    DeviceHelper.getDeviceIcon(device.type),
                    color: isSelected ? primary : palette.muted,
                    size: 19,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: online ? palette.success : palette.faint,
                    shape: BoxShape.circle,
                  ),
                ),
                if (onRename != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onRename,
                    child: Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: palette.faint,
                    ),
                  ),
                ],
              ],
            ),
            const Spacer(),
            TrText(
              device.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            TrText(
              online ? 'Онлайн' : 'Офлайн',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: online ? palette.success : palette.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
