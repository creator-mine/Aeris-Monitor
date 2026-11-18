/// Human-readable byte sizes for the RU/EN interface.
///
/// Uses binary units (1 KB = 1024 B) to match the firmware's `usedBytes()`.
String formatBytes(int bytes, {String language = 'ru'}) {
  final english = language.toLowerCase().startsWith('en');
  final units = english
      ? const ['B', 'KB', 'MB', 'GB', 'TB']
      : const ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];

  if (bytes <= 0) return '0 ${units[0]}';

  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  final digits = unit == 0 ? 0 : (value >= 100 ? 0 : 1);
  final number = value.toStringAsFixed(digits);
  return '${english ? number : number.replaceAll('.', ',')} ${units[unit]}';
}
