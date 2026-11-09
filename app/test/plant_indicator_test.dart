import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/plant_condition_calculator.dart';
import 'package:plant_companion/services/plant_preview.dart';
import 'package:plant_companion/utils/sensor_units.dart';
import 'package:plant_companion/widgets/plant_portrait.dart';

const cases = [
  ('Happy', PreviewMood.healthy, null, 0.0, 'happy', null, false),
  (
    'Low Water',
    PreviewMood.moistureBelow,
    SensorMetric.soilMoisture,
    12.0,
    'sad',
    'sensors/soil_moisture.png',
    false,
  ),
  (
    'High Water',
    PreviewMood.moistureAbove,
    SensorMetric.soilMoisture,
    92.0,
    'sad',
    'sensors/soil_moisture.png',
    true,
  ),
  (
    'Low Light',
    PreviewMood.lightBelow,
    SensorMetric.light,
    110.0,
    'sleeping',
    'sensors/light.png',
    false,
  ),
  (
    'High Light',
    PreviewMood.lightAbove,
    SensorMetric.light,
    1350.0,
    'sad',
    'sensors/light.png',
    true,
  ),
  (
    'Cold',
    PreviewMood.temperatureBelow,
    SensorMetric.temperature,
    24.0,
    'sad',
    'needs/cold_thermometer.png',
    false,
  ),
  (
    'Hot',
    PreviewMood.temperatureAbove,
    SensorMetric.temperature,
    108.0,
    'sad',
    'sensors/temperature.png',
    false,
  ),
  (
    'Low Humidity',
    PreviewMood.humidityBelow,
    SensorMetric.humidity,
    15.0,
    'sad',
    'sensors/humidity.png',
    false,
  ),
  (
    'High Humidity',
    PreviewMood.humidityAbove,
    SensorMetric.humidity,
    88.0,
    'sad',
    'sensors/humidity.png',
    true,
  ),
];

Plant statePlant(
  Map<SensorMetric, double?> values, {
  bool assigned = true,
  PlantAvatarId avatar = PlantAvatarId.pothos,
}) => Plant(
  id: 'f-fixture',
  nickname: 'Florence',
  profile: PlantProfile(
    id: 'fixture',
    plantType: 'Epipremnum aureum',
    ranges: PlantAvatarId.pothos.hints,
  ),
  avatar: avatar,
  deviceId: assigned ? 'fixture-device' : null,
  readings: [
    SensorReading(
      recordedAt: DateTime.utc(2026, 11, 9),
      sourceDeviceId: 'fixture-device',
      soilMoisture: values[SensorMetric.soilMoisture],
      light: values[SensorMetric.light],
      temperature: values[SensorMetric.temperature],
      humidity: values[SensorMetric.humidity],
    ),
  ],
);
Map<SensorMetric, double?> healthyValues() => {
  SensorMetric.soilMoisture: 45,
  SensorMetric.light: 630,
  SensorMetric.temperature: fahrenheitToCelsius(75),
  SensorMetric.humidity: 55,
};

void main() {
  for (final c in cases) {
    test(
      '${c.$1}: real calculator, Home/Details, preview and always-red row mapping',
      () {
        final values = healthyValues();
        if (c.$3 != null) {
          values[c.$3!] = c.$3 == SensorMetric.temperature
              ? fahrenheitToCelsius(c.$4)
              : c.$4;
        }
        final plant = statePlant(values),
            condition = PlantConditionCalculator.calculate(plant),
            home = PlantAppearance(plant),
            details = PlantAppearance(plant, detail: true);
        expect(home.face, 'faces/${c.$5}.png');
        expect(home.need, c.$6);
        expect(home.excess, c.$7);
        expect(details.need, c.$3 == null ? 'needs/happy_heart.png' : c.$6);
        expect(details.excess, c.$7);
        expect(
          sensorAsset(SensorMetric.temperature),
          'sensors/temperature.png',
        );
        expect(condition.metric, c.$3);
        expect(condition.isComplete, true);
        expect(
          condition.assessment,
          c.$3 == null ? HealthAssessment.healthy : HealthAssessment.knownIssue,
        );
        if (c.$3 != null) {
          expect(home.description, contains(c.$2.below ? 'below' : 'above'));
        }
        final preview = PlantPreviewData(
          id: 'draft',
          nickname: 'Preview',
          species: 'Species',
          avatar: PlantAvatarId.pothos,
          ranges: plant.profile.ranges,
          connection: PreviewConnection.connected,
          override: c.$2,
        );
        expect(preview.cardAppearance.need, c.$6);
        expect(preview.largeAppearance.need, details.need);
        expect(preview.cardAppearance.excess, c.$7);
        expect(preview.largeAppearance.excess, c.$7);
      },
    );
    for (final avatar in PlantAvatarId.values) {
      testWidgets(
        '${c.$1} / ${avatar.name}: original layers and scaled slash geometry',
        (tester) async {
          final values = healthyValues();
          if (c.$3 != null) {
            values[c.$3!] = c.$3 == SensorMetric.temperature
                ? fahrenheitToCelsius(c.$4)
                : c.$4;
          }
          for (final detail in [false, true]) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: PlantPortrait(
                      avatar: avatar,
                      appearance: PlantAppearance(
                        statePlant(values, avatar: avatar),
                        detail: detail,
                      ),
                      width: detail ? 180 : 104,
                      detail: detail,
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(
              find.byKey(const ValueKey('need-slash')),
              c.$7 ? findsOneWidget : findsNothing,
            );
            for (final image in tester.widgetList<Image>(find.byType(Image))) {
              expect(image.filterQuality, FilterQuality.none);
              expect(image.fit, BoxFit.contain);
            }
            if (c.$7) {
              final slash = tester.getRect(
                    find.byKey(const ValueKey('need-slash')),
                  ),
                  icon = tester.getRect(
                    find.byKey(const ValueKey('need-icon')),
                  ),
                  factor = detail ? 180 / 152 : 104 / 152;
              expect(slash.width, closeTo(31 * factor, 1e-6));
              expect(slash.left, closeTo(icon.left - 1.5 * factor, 1e-6));
              expect(slash.top, closeTo(icon.top - 1.5 * factor, 1e-6));
            }
          }
        },
      );
    }
  }
  test(
    'incomplete and multiple issues preserve known-metric priority and truthful availability',
    () {
      final values = healthyValues()..[SensorMetric.soilMoisture] = null;
      expect(PlantAppearance(statePlant(values)).face, isNull);
      values[SensorMetric.light] = 1400;
      values[SensorMetric.temperature] = fahrenheitToCelsius(110);
      values[SensorMetric.humidity] = 90;
      var p = statePlant(values);
      expect(PlantConditionCalculator.calculate(p).metric, SensorMetric.light);
      expect(PlantAppearance(p).excess, true);
      expect(PlantAppearance(p).description, contains('unavailable'));
      values[SensorMetric.soilMoisture] = 90;
      p = statePlant(values);
      expect(
        PlantConditionCalculator.calculate(p).metric,
        SensorMetric.soilMoisture,
      );
      expect(PlantAppearance(p).need, 'sensors/soil_moisture.png');
      values[SensorMetric.soilMoisture] = 45;
      values[SensorMetric.light] = 630;
      p = statePlant(values);
      expect(
        PlantConditionCalculator.calculate(p).metric,
        SensorMetric.temperature,
      );
      expect(PlantAppearance(p).excess, false);
      values[SensorMetric.temperature] = fahrenheitToCelsius(75);
      expect(
        PlantConditionCalculator.calculate(statePlant(values)).metric,
        SensorMetric.humidity,
      );
      final noDevice = PlantAppearance(statePlant(values, assigned: false));
      expect(noDevice.face, 'faces/sleeping.png');
      expect(noDevice.need, isNull);
      expect(noDevice.excess, false);
    },
  );
  test(
    'approved originals and every generated platform PNG resolve with declared dimensions',
    () {
      for (final row in [
        ('needs/cold_thermometer.png', 245, 456, 3759),
        ('needs/excess_slash.png', 86, 85, 422),
      ]) {
        final bytes = File(
              'assets/plant_companion/${row.$1}',
            ).readAsBytesSync(),
            data = bytes.buffer.asByteData();
        expect(bytes.length, row.$4);
        expect(data.getUint32(16), row.$2);
        expect(data.getUint32(20), row.$3);
        expect(bytes[25], row.$1.contains('excess') ? 3 : 6);
        if (bytes[25] == 3) {
          expect(latin1.decode(bytes).contains('tRNS'), true);
        }
      }
      final manifest =
          jsonDecode(
                File(
                  '../artwork/platform_icons.json',
                ).readAsStringSync().replaceFirst('\uFEFF', ''),
              )
              as Map<String, dynamic>;
      expect(manifest['background'], '#163F2E');
      expect((manifest['outputs'] as List).length, 36);
      for (final image in manifest['outputs'] as List) {
        final bytes = File('../${image['path']}').readAsBytesSync(),
            data = bytes.buffer.asByteData();
        expect(data.getUint32(16), image['size']);
        expect(data.getUint32(20), image['size']);
        if ((image['path'] as String).startsWith('app/ios/')) {
          expect(bytes[25], 2, reason: 'iOS PNG must be RGB without alpha');
        }
      }
    },
  );
}
