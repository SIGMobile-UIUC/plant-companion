import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/plant_condition_calculator.dart';
import 'package:plant_companion/utils/sensor_scale.dart';
import 'package:plant_companion/utils/sensor_units.dart';

void main() {
  Plant plant(SensorReading? packet, {String? device = 'device-1'}) => Plant(
    id: 'p',
    nickname: 'Any',
    profile: PlantProfile(
      id: 'x',
      plantType: 'Fiction',
      ranges: PlantAvatarId.pothos.hints,
    ),
    deviceId: device,
    readings: packet == null ? [] : [packet],
  );

  test(
    'missing and partial measurements do not establish healthy or a mood',
    () {
      expect(
        PlantConditionCalculator.calculate(plant(null)).assessment,
        HealthAssessment.unassessed,
      );
      final p = plant(
        SensorReading(recordedAt: DateTime.utc(2026), soilMoisture: 40),
      );
      expect(
        PlantConditionCalculator.calculate(p).assessment,
        HealthAssessment.unassessed,
      );
      final partial = PlantConditionCalculator.calculate(
        plant(SensorReading(recordedAt: DateTime.utc(2026), light: 100)),
      );
      expect(partial.metric, SensorMetric.light);
      expect(partial.isComplete, isFalse);
    },
  );

  test(
    'priority handles both above and below, independently of connection freshness',
    () {
      final packet = SensorReading(
        recordedAt: DateTime.utc(2026),
        soilMoisture: 70,
        light: 100,
        temperature: 23,
        humidity: 42,
      );
      final condition = PlantConditionCalculator.calculate(plant(packet));
      expect(condition.metric, SensorMetric.soilMoisture);
      expect(condition.direction, ReadingStatus.aboveRange);
      expect(condition.isComplete, isTrue);
    },
  );

  test(
    'no sensor hides retained history with demonstration values, no measured health',
    () {
      final p = plant(
        SensorReading(recordedAt: DateTime.utc(2026), light: 10),
        device: null,
      );
      final display = ReadingPresentation(p);
      expect(display.values[SensorMetric.light], 625);
      expect(display.isDemonstration, isTrue);
      expect(display.faceAsset, 'assets/plant_companion/faces/sleeping.png');
      expect(display.bubbleAsset, isNull);
      expect(display.timestamp, isNull);
      expect(
        PlantConditionCalculator.calculate(p).assessment,
        HealthAssessment.unassessed,
      );
    },
  );

  test('Fahrenheit conversion and exact demo scale geometry', () {
    expect(celsiusToFahrenheit(fahrenheitToCelsius(75)), closeTo(75, 1e-10));
    final scale = SensorScale.forMetric(
      SensorMetric.temperature,
      PlantAvatarId.pothos.hints[SensorMetric.temperature]!,
      fahrenheitToCelsius(75),

      plantId: 'fixture',
    );
    expect(scale.minimum, -40);
    expect(scale.maximum, 120);
    expect(scale.fraction(75) * 304, closeTo(218.5, 1e-8));
  });

  test(
    'light adapts stably while temperature retains negative/custom bounds',
    () {
      final high = SensorScale.forMetric(
        SensorMetric.light,
        const TargetRange(6000, 9000),
        12000,

        plantId: 'fixture',
      );
      expect(high.maximum, 24000);
      expect(high.fraction(6000) * 190, 47.5);
      expect(high.fraction(12000), .5);
      final cold = SensorScale.forMetric(
        SensorMetric.temperature,
        TargetRange(fahrenheitToCelsius(-40), fahrenheitToCelsius(-10)),
        fahrenheitToCelsius(-25),

        plantId: 'fixture',
      );
      expect(cold.minimum, -40);
      expect(cold.maximum, 120);
      expect(cold.fraction(-25) * 304, closeTo(28.5, 1e-9));
      final missing = SensorScale.forMetric(
        SensorMetric.light,
        const TargetRange(2000, 3000),
        null,

        plantId: 'fixture',
      );
      expect(missing.maximum, 7100);
    },
  );
}
