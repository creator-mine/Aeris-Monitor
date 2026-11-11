import 'package:equatable/equatable.dart';

/// Smart-home automation rule. Evaluation happens client-side on incoming
/// sensor data; the server only persists the rule definitions.
class SmartRule extends Equatable {
  final String id;
  final String name;
  final bool enabled;
  final String deviceId;
  final RuleTrigger trigger;
  final String sensorType;
  final double? threshold;
  final RuleAction action;
  final String actionPayload;
  final int cooldownSeconds;
  final DateTime createdAt;

  const SmartRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.deviceId,
    required this.trigger,
    this.sensorType = '',
    this.threshold,
    this.action = RuleAction.notify,
    this.actionPayload = '',
    this.cooldownSeconds = 60,
    required this.createdAt,
  });

  factory SmartRule.fromJson(Map<String, dynamic> json) {
    return SmartRule(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      deviceId: json['device_id'] as String,
      trigger: ruleTriggerFromWire(json['trigger'] as String?),
      sensorType: json['sensor_type'] as String? ?? '',
      threshold: json['threshold'] != null
          ? (json['threshold'] as num).toDouble()
          : null,
      action: ruleActionFromWire(json['action'] as String?),
      actionPayload: json['action_payload'] as String? ?? '',
      cooldownSeconds: json['cooldown_seconds'] as int? ?? 60,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'enabled': enabled,
      'device_id': deviceId,
      'trigger': ruleTriggerWire(trigger),
      'sensor_type': sensorType,
      'threshold': threshold,
      'action': ruleActionWire(action),
      'action_payload': actionPayload,
      'cooldown_seconds': cooldownSeconds,
      'created_at': createdAt.toIso8601String(),
    };
  }

  SmartRule copyWith({
    String? name,
    bool? enabled,
    String? deviceId,
    RuleTrigger? trigger,
    String? sensorType,
    double? threshold,
    RuleAction? action,
    String? actionPayload,
    int? cooldownSeconds,
  }) {
    return SmartRule(
      id: id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      deviceId: deviceId ?? this.deviceId,
      trigger: trigger ?? this.trigger,
      sensorType: sensorType ?? this.sensorType,
      threshold: threshold ?? this.threshold,
      action: action ?? this.action,
      actionPayload: actionPayload ?? this.actionPayload,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        enabled,
        deviceId,
        trigger,
        sensorType,
        threshold,
        action,
        actionPayload,
        cooldownSeconds,
        createdAt,
      ];
}

enum RuleTrigger {
  thresholdAbove,
  thresholdBelow,
  online,
  offline,
  noData,
}

enum RuleAction {
  notify,
  mqttCommand,
  deviceCommand,
}

/// Wire format used by the signaling server (snake_case), shared with
/// the app model and the rule engine payload builder.
String ruleTriggerWire(RuleTrigger trigger) => switch (trigger) {
      RuleTrigger.thresholdAbove => 'threshold_above',
      RuleTrigger.thresholdBelow => 'threshold_below',
      RuleTrigger.online => 'online',
      RuleTrigger.offline => 'offline',
      RuleTrigger.noData => 'no_data',
    };

RuleTrigger ruleTriggerFromWire(String? value) => switch (value) {
      'threshold_above' => RuleTrigger.thresholdAbove,
      'threshold_below' => RuleTrigger.thresholdBelow,
      'online' => RuleTrigger.online,
      'offline' => RuleTrigger.offline,
      'no_data' => RuleTrigger.noData,
      _ => RuleTrigger.thresholdAbove,
    };

String ruleActionWire(RuleAction action) => switch (action) {
      RuleAction.notify => 'notify',
      RuleAction.mqttCommand => 'mqtt_command',
      RuleAction.deviceCommand => 'device_command',
    };

RuleAction ruleActionFromWire(String? value) => switch (value) {
      'notify' => RuleAction.notify,
      'mqtt_command' => RuleAction.mqttCommand,
      'device_command' => RuleAction.deviceCommand,
      _ => RuleAction.notify,
    };