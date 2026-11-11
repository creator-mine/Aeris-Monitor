/// Log display mode.
///
/// `standard` keeps the raw device messages as-is.
/// `lightweight` renders simplified, localized messages.
enum LogMode {
  standard,
  lightweight;

  String get label => switch (this) {
        LogMode.standard => 'Стандартный',
        LogMode.lightweight => 'Облегчённый',
      };
}