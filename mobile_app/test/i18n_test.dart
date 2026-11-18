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

  test('English translates the SD card labels', () {
    expect(L10n.translate('Карта памяти', 'en'), 'Memory card');
    expect(L10n.translate('Работает', 'en'), 'Working');
    expect(L10n.translate('Занято', 'en'), 'Used');
    expect(L10n.translate('Свободно', 'en'), 'Free');
    expect(L10n.translate('Всего', 'en'), 'Total');
    expect(L10n.translate('Нет карты', 'en'), 'No card');
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
