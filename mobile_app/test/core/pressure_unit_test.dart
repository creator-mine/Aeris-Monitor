import 'package:aeris/core/config/pressure_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PressureUnit', () {
    test('hPa is the identity unit', () {
      expect(PressureUnit.hpa.fromHpa(999.4), 999.4);
      expect(PressureUnit.hpa.decimals, 1);
      expect(PressureUnit.hpa.axisDecimals, 1);
    });

    test('converts hPa to kPa', () {
      expect(PressureUnit.kpa.fromHpa(999.4), closeTo(99.94, 1e-9));
      expect(PressureUnit.kpa.fromHpa(1013.25), closeTo(101.325, 1e-9));
      // 1 hPa equals 0.1 kPa; the axis needs two decimals.
      expect(PressureUnit.kpa.axisDecimals, 2);
      expect(PressureUnit.kpa.decimals, 1);
    });

    test('converts hPa to mmHg', () {
      expect(PressureUnit.mmhg.fromHpa(999.4), closeTo(749.61, 0.01));
      expect(PressureUnit.mmhg.fromHpa(1013.25), closeTo(760.0, 0.1));
    });

    test('falls back to hPa for unknown stored values', () {
      expect(PressureUnit.fromName(null), PressureUnit.hpa);
      expect(PressureUnit.fromName('kpa'), PressureUnit.kpa);
      expect(PressureUnit.fromName('mmhg'), PressureUnit.mmhg);
      expect(PressureUnit.fromName('bar'), PressureUnit.hpa);
    });
  });
}
