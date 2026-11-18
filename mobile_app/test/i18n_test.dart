import 'package:aeris/core/i18n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Russian keeps the source strings', () {
    expect(L10n.translate('Устройства', 'ru'), 'Устройства');
  });

  test('English translates static UI labels', () {
    expect(L10n.translate('Устройства', 'en'), 'Devices');
    expect(L10n.translate('Минимум', 'en'), 'Minimum');
    expect(L10n.translate('Освещённость', 'en'), 'Illuminance');
  });

  test('English translates interpolated messages', () {
    expect(
      L10n.translate('1/2 онлайн', 'en'),
      '1/2 online',
    );
    expect(
      L10n.translate(
        'Устройство «Main Controller C6» офлайн. Включите его или выберите онлайн-устройство в списке.',
        'en',
      ),
      'Device “Main Controller C6” is offline. Power it on or choose an online device from the list.',
    );
  });
}
