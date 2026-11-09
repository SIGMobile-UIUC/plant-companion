import 'dart:math' as math;
import '../models/device.dart';
import '../models/plant.dart';
import '../models/plant_avatar_id.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';
import '../widgets/plant_portrait.dart';
import 'plant_condition_calculator.dart';

enum PreviewMood {
  healthy,
  moistureBelow,
  moistureAbove,
  lightBelow,
  lightAbove,
  temperatureBelow,
  temperatureAbove,
  humidityBelow,
  humidityAbove,
  sleeping,
}

enum PreviewConnection { connected, disconnected, noDevice }

extension PreviewMoodText on PreviewMood {
  String get label => switch (this) {
    PreviewMood.healthy => 'Healthy',
    PreviewMood.moistureBelow => 'Moisture below range',
    PreviewMood.moistureAbove => 'Moisture above range',
    PreviewMood.lightBelow => 'Light below range',
    PreviewMood.lightAbove => 'Light above range',
    PreviewMood.temperatureBelow => 'Temperature below range',
    PreviewMood.temperatureAbove => 'Temperature above range',
    PreviewMood.humidityBelow => 'Humidity below range',
    PreviewMood.humidityAbove => 'Humidity above range',
    PreviewMood.sleeping => 'Sleeping',
  };
  SensorMetric? get metric => switch (this) {
    PreviewMood.moistureBelow ||
    PreviewMood.moistureAbove => SensorMetric.soilMoisture,
    PreviewMood.lightBelow || PreviewMood.lightAbove => SensorMetric.light,
    PreviewMood.temperatureBelow ||
    PreviewMood.temperatureAbove => SensorMetric.temperature,
    PreviewMood.humidityBelow ||
    PreviewMood.humidityAbove => SensorMetric.humidity,
    _ => null,
  };
  bool get below => [
    PreviewMood.moistureBelow,
    PreviewMood.lightBelow,
    PreviewMood.temperatureBelow,
    PreviewMood.humidityBelow,
  ].contains(this);
}

PreviewMood? _conditionMood(MeasuredCondition c) {
  if (c.assessment == HealthAssessment.healthy) return PreviewMood.healthy;
  if (c.assessment != HealthAssessment.knownIssue) return null;
  final below = c.direction == ReadingStatus.belowRange;
  return switch (c.metric!) {
    SensorMetric.soilMoisture =>
      below ? PreviewMood.moistureBelow : PreviewMood.moistureAbove,
    SensorMetric.light =>
      below ? PreviewMood.lightBelow : PreviewMood.lightAbove,
    SensorMetric.temperature =>
      below ? PreviewMood.temperatureBelow : PreviewMood.temperatureAbove,
    SensorMetric.humidity =>
      below ? PreviewMood.humidityBelow : PreviewMood.humidityAbove,
  };
}

/// Pure preview data. No clock, permanent ID allocation, store or database writes.
class PlantPreviewData {
  PlantPreviewData({
    required String id,
    required String nickname,
    required String species,
    required PlantAvatarId avatar,
    required Map<SensorMetric, TargetRange> ranges,
    required PreviewConnection connection,
    PreviewMood? override,
    Plant? actual,
  }) {
    final name = nickname.trim().isEmpty ? 'This plant' : nickname.trim();
    final profile = PlantProfile(
      id: 'preview',
      plantType: species,
      ranges: ranges,
    );
    final explicit = override != null;
    SensorReading? reading;
    if (explicit) {
      final values = {
        for (final m in SensorMetric.values) m: ranges[m]!.midpoint,
      };
      final metric = override.metric;
      if (metric != null) {
        final range = ranges[metric]!, span = range.maximum - range.minimum;
        final lower = metric == SensorMetric.temperature ? -50.0 : 0.0;
        final upper = switch (metric) {
          SensorMetric.light => 200000.0,
          SensorMetric.temperature => 100.0,
          _ => 100.0,
        };
        final value = override.below
            ? range.minimum - math.max(1, span * .25)
            : range.maximum + math.max(1, span * .25);
        values[metric] = value.clamp(lower, upper);
      }
      reading = SensorReading(
        recordedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        soilMoisture: values[SensorMetric.soilMoisture],
        light: values[SensorMetric.light],
        temperature: values[SensorMetric.temperature],
        humidity: values[SensorMetric.humidity],
      );
    } else {
      reading = actual?.latestReading;
    }
    final assessed = Plant(
      id: id,
      nickname: name,
      speciesName: species,
      avatar: avatar,
      profile: profile,
      deviceId: explicit ? 'preview-device' : actual?.deviceId,
      readings: [?reading],
    );
    final condition = PlantConditionCalculator.calculate(assessed);
    mood = override ?? _conditionMood(condition);
    explanation = explicit
        ? switch (override) {
            PreviewMood.healthy =>
              '$name: preview with all readings within their ideal ranges.',
            PreviewMood.sleeping => '$name: sleeping expression preview.',
            _ =>
              '$name: preview of ${override.metric!.label.toLowerCase()} ${override.below ? 'below' : 'above'} the ideal range.',
          }
        : condition.assessment == HealthAssessment.unassessed
        ? reading == null
              ? '$name: no measured readings are available.'
              : '$name: some readings are unavailable; health cannot be assessed.'
        : condition.assessment == HealthAssessment.healthy
        ? '$name: all readings are within their ideal ranges.'
        : '$name: ${condition.metric!.label.toLowerCase()} is ${condition.direction == ReadingStatus.belowRange ? 'below' : 'above'} the ideal range.${condition.isComplete ? '' : ' Some readings are unavailable.'}';
    if (explicit) {
      final metric = override.metric;
      largeAppearance = PlantAppearance.preview(
        face: override == PreviewMood.healthy
            ? 'faces/happy.png'
            : override == PreviewMood.sleeping ||
                  (metric == SensorMetric.light && override.below)
            ? 'faces/sleeping.png'
            : 'faces/sad.png',
        need: override == PreviewMood.healthy
            ? 'needs/happy_heart.png'
            : metric == null
            ? null
            : conditionNeedAsset(metric, below: override.below),
        excess: metric != null && excessNeed(metric, below: override.below),
        description: explanation,
      );
    } else if (condition.assessment == HealthAssessment.unassessed) {
      largeAppearance = PlantAppearance.preview(description: explanation);
    } else {
      largeAppearance = PlantAppearance(assessed, detail: true);
    }
    cardPlant = Plant(
      id: id,
      nickname: name,
      speciesName: species,
      avatar: avatar,
      profile: profile,
      deviceId: connection == PreviewConnection.noDevice
          ? null
          : 'preview-device',
      readings: [?reading],
    );
    cardDevice = connection == PreviewConnection.noDevice
        ? null
        : Device(
            id: 'preview-device',
            name: 'Preview',
            isConnected: connection == PreviewConnection.connected,
          );
    cardAppearance = connection == PreviewConnection.noDevice
        ? PlantAppearance(cardPlant)
        : PlantAppearance.preview(
            face: largeAppearance.face,
            need: largeAppearance.need == 'needs/happy_heart.png'
                ? null
                : largeAppearance.need,
            excess: largeAppearance.excess,
            description: 'Preview. $explanation',
          );
  }
  late final PreviewMood? mood;
  late final String explanation;
  late final Plant cardPlant;
  late final Device? cardDevice;
  late final PlantAppearance largeAppearance, cardAppearance;
}
