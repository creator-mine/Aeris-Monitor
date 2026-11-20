import 'package:flutter/material.dart';

/// One option of a [SegmentedToggle].
class SegmentedToggleOption<T> {
  const SegmentedToggleOption({required this.value, required this.label});

  final T value;
  final Widget label;
}

/// Compact segmented control with an animated raised pill for the active
/// option. Used for the Wi-Fi "Авто / Ручной" mode and reusable for other
/// small two-state choices.
class SegmentedToggle<T> extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.value,
    required this.options,
    this.onChanged,
    this.enabled = true,
  });

  final T value;
  final List<SegmentedToggleOption<T>> options;
  final ValueChanged<T>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final interactive = enabled && onChanged != null;

    final trackColor = dark
        ? const Color(0xFF242424)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.75);
    final trackBorder = dark
        ? Colors.white.withValues(alpha: 0.06)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6);
    final selectedColor =
        dark ? const Color(0xFF3A3A3A) : theme.colorScheme.surface;
    final selectedBorder = dark
        ? Colors.white.withValues(alpha: 0.18)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.9);
    final selectedText = dark ? Colors.white : theme.colorScheme.onSurface;
    final unselectedText =
        dark ? Colors.white60 : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: trackBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            _Segment(
              selected: option.value == value,
              label: option.label,
              selectedColor: selectedColor,
              selectedBorder: selectedBorder,
              selectedText: selectedText,
              unselectedText: unselectedText,
              enabled: interactive,
              onTap: interactive && option.value != value
                  ? () => onChanged!(option.value)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.selected,
    required this.label,
    required this.selectedColor,
    required this.selectedBorder,
    required this.selectedText,
    required this.unselectedText,
    required this.enabled,
    required this.onTap,
  });

  final bool selected;
  final Widget label;
  final Color selectedColor;
  final Color selectedBorder;
  final Color selectedText;
  final Color unselectedText;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? selectedColor : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? selectedBorder : Colors.transparent,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                style: baseStyle.copyWith(
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? selectedText : unselectedText,
                ),
                child: label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
