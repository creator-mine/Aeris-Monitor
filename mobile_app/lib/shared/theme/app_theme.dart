import 'package:flutter/material.dart';

/// Semantic colours used outside the Material colour scheme.
///
/// A ThemeExtension keeps the palette available to every screen and lets the
/// light/dark variants stay in sync with [AppTheme.getTheme].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.faint,
    required this.primary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.temperature,
    required this.humidity,
    required this.pressure,
    required this.illuminance,
    required this.iaq,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color muted;
  final Color faint;
  final Color primary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color temperature;
  final Color humidity;
  final Color pressure;
  final Color illuminance;
  final Color iaq;

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ??
        AppTheme.darkPalette(AppTheme.accentColors.first);
  }

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? text,
    Color? muted,
    Color? faint,
    Color? primary,
    Color? success,
    Color? warning,
    Color? danger,
    Color? temperature,
    Color? humidity,
    Color? pressure,
    Color? illuminance,
    Color? iaq,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      primary: primary ?? this.primary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      pressure: pressure ?? this.pressure,
      illuminance: illuminance ?? this.illuminance,
      iaq: iaq ?? this.iaq,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return AppPalette(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      border: mix(border, other.border),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      faint: mix(faint, other.faint),
      primary: mix(primary, other.primary),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      temperature: mix(temperature, other.temperature),
      humidity: mix(humidity, other.humidity),
      pressure: mix(pressure, other.pressure),
      illuminance: mix(illuminance, other.illuminance),
      iaq: mix(iaq, other.iaq),
    );
  }
}

class AppTheme {
  static const List<Color> accentColors = [
    Color(0xFF55E0C1), // Mint
    Color(0xFF79A9FF), // Blue
    Color(0xFFB39CFF), // Purple
    Color(0xFFFFC36C), // Amber
    Color(0xFFFF8191), // Coral
    Color(0xFF5EE08A), // Green
  ];

  static const List<String> accentColorNames = [
    'Мята',
    'Синий',
    'Фиолетовый',
    'Янтарный',
    'Коралловый',
    'Зелёный',
  ];

  /// Updated by [getTheme] so legacy widgets that still read the static
  /// colour follow the accent picker as well.
  static Color _primaryColor = const Color(0xFF55E0C1);
  static Color get primaryColor => _primaryColor;

  static const Color secondaryColor = Color(0xFF79A9FF);
  static const Color accentColor = Color(0xFFFFC36C);
  static const Color errorColor = Color(0xFFFF8191);
  static const Color successColor = Color(0xFF55E0C1);
  static const Color warningColor = Color(0xFFFFC36C);
  static const Color infoColor = Color(0xFF79A9FF);

  static const Color darkBackground = Color(0xFF0B1220);
  static const Color darkSurface = Color(0xFF111D2F);
  static const Color darkSurfaceAlt = Color(0xFF16243A);
  static const Color darkBorder = Color(0xFF26374F);

  static const Color lightBackground = Color(0xFFF4F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEDF2F9);
  static const Color lightBorder = Color(0xFFD8E2F0);

  static AppPalette darkPalette(Color accent) => AppPalette(
        background: darkBackground,
        surface: darkSurface,
        surfaceAlt: darkSurfaceAlt,
        border: darkBorder,
        text: const Color(0xFFF3F6FB),
        muted: const Color(0xFFA7B5C8),
        faint: const Color(0xFF6F8199),
        primary: accent,
        success: const Color(0xFF55E0C1),
        warning: const Color(0xFFFFC36C),
        danger: const Color(0xFFFF8191),
        temperature: const Color(0xFFFF9B7A),
        humidity: const Color(0xFF79A9FF),
        pressure: const Color(0xFFB39CFF),
        illuminance: const Color(0xFFFFC36C),
        iaq: const Color(0xFF55E0C1),
      );

  static AppPalette lightPalette(Color accent) => AppPalette(
        background: lightBackground,
        surface: lightSurface,
        surfaceAlt: lightSurfaceAlt,
        border: lightBorder,
        text: const Color(0xFF111C2C),
        muted: const Color(0xFF5D6C82),
        faint: const Color(0xFF8B99AC),
        primary: accent,
        success: const Color(0xFF0F9D7A),
        warning: const Color(0xFFB97700),
        danger: const Color(0xFFD1435B),
        temperature: const Color(0xFFD9643E),
        humidity: const Color(0xFF2E6FD6),
        pressure: const Color(0xFF7653C7),
        illuminance: const Color(0xFFB97700),
        iaq: const Color(0xFF0F9D7A),
      );

  /// Dark text on bright mint/amber accents, white on deep blue/purple.
  static Color onAccent(Color accent) {
    return accent.computeLuminance() > 0.45
        ? const Color(0xFF07111C)
        : Colors.white;
  }

  static ThemeData getTheme(int colorIndex, bool darkMode) {
    final accent = accentColors[colorIndex.clamp(0, accentColors.length - 1)];
    _primaryColor = accent;
    final brightness = darkMode ? Brightness.dark : Brightness.light;
    final palette = darkMode ? darkPalette(accent) : lightPalette(accent);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Nunito',
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: onAccent(accent),
      secondary: palette.humidity,
      tertiary: palette.pressure,
      error: palette.danger,
      surface: palette.surface,
      onSurface: palette.text,
      outline: palette.border,
      outlineVariant: palette.border.withValues(alpha: 0.6),
    );

    final text = base.textTheme
        .copyWith(
          displayLarge: base.textTheme.displayLarge?.copyWith(
            fontSize: 52,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.8,
          ),
          displayMedium: base.textTheme.displayMedium?.copyWith(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
          displaySmall: base.textTheme.displaySmall?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        )
        .apply(bodyColor: palette.text, displayColor: palette.text);

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Nunito',
      primaryColor: accent,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      dividerColor: palette.border,
      textTheme: text,
      extensions: [palette],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.text,
        iconTheme: IconThemeData(color: palette.muted, size: 22),
        titleTextStyle: text.headlineSmall?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: palette.text,
        ),
        toolbarHeight: 64,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? palette.text : palette.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? accent : palette.muted,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.surface,
        indicatorColor: accent.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: palette.muted),
        selectedLabelTextStyle: TextStyle(
          color: palette.text,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: palette.muted,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        useIndicator: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        hintStyle: TextStyle(color: palette.faint, fontSize: 14),
        labelStyle: TextStyle(color: palette.muted, fontSize: 14),
        floatingLabelStyle: TextStyle(color: accent, fontSize: 13),
        prefixIconColor: palette.muted,
        suffixIconColor: palette.muted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent(accent),
          disabledBackgroundColor: palette.surfaceAlt,
          disabledForegroundColor: palette.faint,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: buttonShape,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent(accent),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: buttonShape,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          side: BorderSide(color: palette.border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: buttonShape,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: accent,
        secondarySelectedColor: accent,
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        labelStyle: TextStyle(
          color: palette.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: onAccent(accent),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: palette.muted, size: 22),
      listTileTheme: ListTileThemeData(
        iconColor: palette.muted,
        textColor: palette.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.surfaceAlt,
        contentTextStyle: TextStyle(color: palette.text, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
        ),
        textStyle: TextStyle(color: palette.text, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.all(
          palette.muted.withValues(alpha: 0.35),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onAccent(accent)
              : palette.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : palette.surfaceAlt,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : palette.border,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: palette.surfaceAlt,
      ),
    );
  }

  static BoxDecoration cardDecoration({bool darkMode = false}) => BoxDecoration(
        color: darkMode ? darkSurface : lightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: darkMode ? darkBorder : lightBorder,
        ),
        boxShadow: darkMode
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF1B2A41).withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      );

  static BoxDecoration get gradientDecoration => BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withValues(alpha: 0.22),
            secondaryColor.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
      );
}
