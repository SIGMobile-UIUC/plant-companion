import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/config/plant_name_config.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_input.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/plant_preview.dart';
import 'package:plant_companion/utils/sensor_scale.dart';
import 'package:plant_companion/utils/sensor_units.dart';

Map<SensorMetric, List<String>> validInputs() => {
  for (final m in formMetrics)
    m: m == SensorMetric.temperature
        ? ['65', '85']
        : [
            inputNumber(PlantAvatarId.pothos.hints[m]!.minimum),
            inputNumber(PlantAvatarId.pothos.hints[m]!.maximum),
          ],
};
PlantFormInput input({
  String name = 'Plant',
  String full = '',
  String species = 'Custom',
  Map<SensorMetric, List<String>>? bounds,
}) => PlantFormInput(
  nickname: name,
  fullName: full,
  species: species,
  bounds: bounds ?? validInputs(),
);
PlantPreviewData preview({
  PreviewMood? mood = PreviewMood.healthy,
  PreviewConnection connection = PreviewConnection.connected,
  Plant? actual,
  Map<SensorMetric, TargetRange>? ranges,
  String id = 'draft-stable',
}) => PlantPreviewData(
  id: id,
  nickname: 'Plant',
  species: 'Custom',
  avatar: PlantAvatarId.pothos,
  ranges: ranges ?? PlantAvatarId.pothos.hints,
  connection: connection,
  override: mood,
  actual: actual,
);

void main() {
  for (final avatar in PlantAvatarId.values) {
    test(
      '${avatar.name} hints display Fahrenheit once and leave canonical values untouched',
      () {
        final raw = avatar.hints[SensorMetric.temperature]!;
        final displayed = displayHint(avatar, SensorMetric.temperature);
        expect(displayed.minimum, closeTo(65, 1e-12));
        expect(
          displayed.maximum,
          closeTo(avatar == PlantAvatarId.peaceLily ? 80 : 85, 1e-12),
        );
        expect(temperatureInputNumber(displayed.minimum), '65');
        expect(avatar.hints[SensorMetric.temperature]!.minimum, raw.minimum);
        for (final m in [
          SensorMetric.soilMoisture,
          SensorMetric.light,
          SensorMetric.humidity,
        ]) {
          expect(displayHint(avatar, m).minimum, avatar.hints[m]!.minimum);
          expect(displayHint(avatar, m).maximum, avatar.hints[m]!.maximum);
        }
      },
    );
  }
  test(
    'all eight empty numeric fields and names are required; preview hints never become input',
    () {
      final fields = {
        for (final m in formMetrics) m: ['', ''],
      };
      final data = input(name: '', species: '', bounds: fields);
      expect(data.missing, isTrue);
      expect(data.errors.length, 10);
      expect(data.errors.values.toSet(), {'This field is required.'});
      final ranges = data.previewRanges(PlantAvatarId.snakePlant);
      expect(ranges[SensorMetric.light]!.minimum, 500);
      expect(fields.values.expand((s) => s), everyElement(isEmpty));
    },
  );
  for (final invalid in ['', 'NaN', 'Infinity', '-Infinity', 'abc', '1e999']) {
    test('required/non-finite input rejected: $invalid', () {
      final fields = validInputs()..[SensorMetric.light] = [invalid, '1000'];
      final data = input(bounds: fields);
      expect(
        data.errors[rangeFieldKey(SensorMetric.light, 0)],
        invalid.isEmpty ? 'This field is required.' : 'Enter a finite number.',
      );
      expect(data.missing, invalid.isEmpty);
    });
  }
  for (final metric in formMetrics) {
    test(
      '${metric.name} strict equality/reversal and domain errors remain inline',
      () {
        for (final pair in [
          ['50', '50'],
          ['70', '20'],
        ]) {
          final fields = validInputs()..[metric] = pair;
          expect(
            input(bounds: fields).errors[rangeFieldKey(metric, 1)],
            'Maximum must be greater than minimum.',
          );
        }
        final fields = validInputs()
          ..[metric] = metric == SensorMetric.temperature
              ? ['-59', '213']
              : ['-1', metric == SensorMetric.light ? '200001' : '101'];
        expect(
          input(bounds: fields).errors.keys,
          containsAll([rangeFieldKey(metric, 0), rangeFieldKey(metric, 1)]),
        );
      },
    );
  }
  test(
    'displayed inclusive domain limits convert correctly without silent clamping',
    () {
      final data = input(
        bounds: {
          SensorMetric.soilMoisture: ['0', '100'],
          SensorMetric.light: ['0', '200000'],
          SensorMetric.temperature: ['-40', '120'],
          SensorMetric.humidity: ['0', '100'],
        },
      );
      expect(data.errors, isEmpty);
      expect(data.canonicalRanges()[SensorMetric.temperature]!.minimum, -40);
      expect(
        data.canonicalRanges()[SensorMetric.temperature]!.maximum,
        fahrenheitToCelsius(120),
      );
    },
  );
  test(
    'unchanged rounded Fahrenheit bounds preserve exact canonical Celsius; only changed bound converts',
    () {
      const original = TargetRange(18.1234567890123, 29.9876543210987);
      final displayed = [
        temperatureInputNumber(celsiusToFahrenheit(original.minimum)),
        temperatureInputNumber(celsiusToFahrenheit(original.maximum)),
      ];
      final fields = validInputs()..[SensorMetric.temperature] = [...displayed];
      final untouched = input(bounds: fields).canonicalRanges(
        originalTemperature: original,
        originalTemperatureText: displayed,
      )[SensorMetric.temperature]!;
      expect(untouched.minimum, original.minimum);
      expect(untouched.maximum, original.maximum);
      fields[SensorMetric.temperature]![0] = '66.25';
      final changed = input(bounds: fields).canonicalRanges(
        originalTemperature: original,
        originalTemperatureText: displayed,
      )[SensorMetric.temperature]!;
      expect(changed.minimum, fahrenheitToCelsius(66.25));
      expect(changed.maximum, original.maximum);
    },
  );
  test(
    'Unicode Full Name limits, nickname warning and Details truncation/fallback are independent',
    () {
      final emoji = '👩🏽‍🌾', full = List.filled(25, emoji).join();
      expect(input(name: 'N' * 1000, full: full).errors, isEmpty);
      expect(
        input(full: '$full$emoji').errors['full-name-field'],
        'Use at most 25 characters.',
      );
      expect(
        PlantNameConfig.warnsForNickname(List.filled(10, emoji).join()),
        isFalse,
      );
      expect(
        PlantNameConfig.warnsForNickname(List.filled(11, emoji).join()),
        isTrue,
      );
      expect(
        PlantNameConfig.detailsName('Nick', full),
        '${List.filled(15, emoji).join()}…',
      );
      expect(PlantNameConfig.detailsName('Nick', '   '), 'Nick');
      expect(PlantNameConfig.detailsName('Nick', null), 'Nick');
    },
  );
  for (final mood in PreviewMood.values) {
    test(
      '${mood.name} uses existing assets, isolated values and honest preview text',
      () {
        final data = preview(mood: mood);
        expect(data.mood, mood);
        expect(data.explanation, contains('preview'));
        expect(data.cardPlant.id, 'draft-stable');
        expect(data.cardPlant.latestReading!.id, isNull);
        expect(data.cardPlant.latestReading!.sourceDeviceId, isNull);
        expect(data.cardPlant.createdAt, isNull);
        final reading = data.cardPlant.latestReading!;
        expect(reading.soilMoisture, inInclusiveRange(0, 100));
        expect(reading.humidity, inInclusiveRange(0, 100));
        expect(reading.light, inInclusiveRange(0, 200000));
        expect(reading.temperature, inInclusiveRange(-50, 100));
        if (mood == PreviewMood.healthy) {
          expect(data.largeAppearance.face, 'faces/happy.png');
          expect(data.largeAppearance.need, 'needs/happy_heart.png');
          expect(data.cardAppearance.need, isNull);
        } else if (mood == PreviewMood.sleeping) {
          expect(data.largeAppearance.face, 'faces/sleeping.png');
          expect(data.largeAppearance.need, isNull);
        } else {
          expect(
            data.largeAppearance.need,
            startsWith(
              mood == PreviewMood.temperatureBelow ? 'needs/cold_' : 'sensors/',
            ),
          );
          expect(
            data.largeAppearance.face,
            mood == PreviewMood.lightBelow
                ? 'faces/sleeping.png'
                : 'faces/sad.png',
          );
        }
      },
    );
  }
  test(
    'no-device card preview is independent; restoring device restores selected mood',
    () {
      final no = preview(
        mood: PreviewMood.moistureBelow,
        connection: PreviewConnection.noDevice,
      );
      expect(no.largeAppearance.face, 'faces/sad.png');
      expect(no.cardAppearance.face, 'faces/sleeping.png');
      expect(no.cardAppearance.need, isNull);
      expect(no.cardPlant.deviceId, isNull);
      expect(no.cardDevice, isNull);
      final restored = preview(
        mood: PreviewMood.moistureBelow,
        connection: PreviewConnection.disconnected,
      );
      expect(restored.cardAppearance.face, 'faces/sad.png');
      expect(restored.cardDevice!.isConnected, isFalse);
    },
  );
  test(
    'physical boundary previews never invent negative light/moisture or impossible percentages',
    () {
      final extreme = {
        ...PlantAvatarId.pothos.hints,
        SensorMetric.light: const TargetRange(0, 200000),
        SensorMetric.soilMoisture: const TargetRange(0, 100),
        SensorMetric.humidity: const TargetRange(0, 100),
      };
      for (final mood in PreviewMood.values) {
        final r = preview(mood: mood, ranges: extreme).cardPlant.latestReading!;
        expect(r.light, inInclusiveRange(0, 200000));
        expect(r.soilMoisture, inInclusiveRange(0, 100));
        expect(r.humidity, inInclusiveRange(0, 100));
      }
    },
  );
  test(
    'unassessed Edit does not become Healthy; explicit override survives newer actual readings',
    () {
      final p = Plant(
        id: 'actual',
        nickname: 'A',
        speciesName: 'Custom',
        profile: PlantProfile.samples.first,
        deviceId: 'device-1',
      );
      final initial = preview(mood: null, actual: p);
      expect(initial.mood, isNull);
      expect(initial.largeAppearance.face, isNull);
      expect(initial.cardPlant.latestReading, isNull);
      final issue = p.withReadings([
        SensorReading(recordedAt: DateTime.utc(2026), light: 10),
      ]);
      final current = preview(mood: null, actual: issue);
      expect(current.mood, PreviewMood.lightBelow);
      expect(current.explanation, contains('Some readings are unavailable.'));
      final overridden = preview(mood: PreviewMood.healthy, actual: issue);
      expect(overridden.largeAppearance.face, 'faces/happy.png');
      expect(issue.latestReading!.light, 10);
    },
  );
  test(
    'Add preview stable draft ID and Edit saved ID use the unchanged v4 scale',
    () {
      final a = preview(), b = preview(mood: PreviewMood.lightAbove);
      double maximum(PlantPreviewData data) => SensorScale.forMetric(
        SensorMetric.light,
        data.cardPlant.profile.rangeFor(SensorMetric.light),
        data.cardPlant.latestReading!.light,
        plantId: data.cardPlant.id,
      ).maximum;
      expect(maximum(a), maximum(b));
      final edit = preview(id: 'plant-1');
      expect(
        maximum(edit),
        SensorScale.forMetric(
          SensorMetric.light,
          PlantAvatarId.pothos.hints[SensorMetric.light]!,
          null,
          plantId: 'plant-1',
        ).maximum,
      );
    },
  );
}
