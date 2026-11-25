/// Display units for atmospheric pressure.
///
/// The firmware and the SD-card history always use hPa, so this enum is only
/// applied at the UI layer. Keeping the stored value in hPa means switching the
/// unit never rewrites history or the CSV export.
enum PressureUnit {
  hpa('hPa', 1.0, 1),
  kpa('кПа', 0.1, 1),
  mmhg('мм рт. ст.', 0.750061683, 1);

  const PressureUnit(this.label, this._factorFromHpa, this.decimals);

  /// Russian source label; translated through [L10n] where needed. `hPa` is
  /// the same in every language.
  final String label;

  final double _factorFromHpa;

  /// Decimals for tiles and statistics. One decimal keeps 1 hPa resolution
  /// for kPa (0.1 kPa) and ~0.1 mmHg.
  final int decimals;

  /// Axis labels need finer steps for kPa: 1 hPa is only 0.1 kPa, so a
  /// one-decimal axis would print the same number twice.
  int get axisDecimals => this == PressureUnit.kpa ? 2 : 1;

  /// Converts a value stored in hPa to this display unit.
  double fromHpa(double hPa) => hPa * _factorFromHpa;

  static PressureUnit fromName(String? name) {
    return values.firstWhere(
      (unit) => unit.name == name,
      orElse: () => PressureUnit.hpa,
    );
  }
}
