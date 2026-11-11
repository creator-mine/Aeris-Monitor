import 'package:flutter_test/flutter_test.dart';
import 'package:aeris/models/smart_rule.dart';

void main() {
  group('SmartRule', () {
    test('fromJson parses a threshold rule', () {
      final rule = SmartRule.fromJson(const {
        'id': 'r1',
        'name': 'Temp alarm',
        'enabled': true,
        'device_id': 'esp32s3_001',
        'trigger': 'threshold_above',
        'sensor_type': 'temperature',
        'threshold': 30,
        'action': 'mqtt_command',
        'action_payload': 'relay1_on',
        'cooldown_seconds': 120,
        'created_at': '2026-09-28T10:00:00.000Z',
      });

      expect(rule.id, 'r1');
      expect(rule.trigger, RuleTrigger.thresholdAbove);
      expect(rule.threshold, 30);
      expect(rule.action, RuleAction.mqttCommand);
      expect(rule.actionPayload, 'relay1_on');
      expect(rule.cooldownSeconds, 120);
    });

    test('fromJson tolerates missing optional fields', () {
      final rule = SmartRule.fromJson(const {
        'id': 'r2',
        'device_id': 'dev1',
        'trigger': 'online',
        'created_at': '2026-09-28T10:00:00.000Z',
      });

      expect(rule.trigger, RuleTrigger.online);
      expect(rule.sensorType, '');
      expect(rule.threshold, isNull);
      expect(rule.action, RuleAction.notify);
      expect(rule.cooldownSeconds, 60);
      expect(rule.enabled, true);
    });

    test('toJson serializes server key names', () {
      final rule = SmartRule(
        id: '',
        name: 'x',
        enabled: true,
        deviceId: 'dev1',
        trigger: RuleTrigger.thresholdBelow,
        sensorType: 'humidity',
        threshold: 20,
        action: RuleAction.deviceCommand,
        actionPayload: 'off',
        cooldownSeconds: 5,
        createdAt: DateTime.utc(2026, 9, 28),
      );

      final json = rule.toJson();
      expect(json['device_id'], 'dev1');
      expect(json['trigger'], 'threshold_below');
      expect(json['action'], 'device_command');
      expect(json['action_payload'], 'off');
      expect(json['cooldown_seconds'], 5);
    });

    test('copyWith keeps id and created_at', () {
      final rule = SmartRule(
        id: 'r5',
        name: 'a',
        enabled: true,
        deviceId: 'dev1',
        trigger: RuleTrigger.online,
        createdAt: DateTime.utc(2026, 9, 28),
      );

      final toggled = rule.copyWith(enabled: false);
      expect(toggled.id, 'r5');
      expect(toggled.enabled, false);
      expect(toggled.createdAt, rule.createdAt);
      expect(toggled.trigger, RuleTrigger.online);
    });
  });
}