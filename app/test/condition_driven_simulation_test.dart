import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/config/temperature_display_config.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/condition_driven_simulation.dart';
import 'package:plant_companion/services/plant_condition_calculator.dart';
import 'package:plant_companion/services/plant_simulation.dart';
import 'package:plant_companion/utils/sensor_units.dart';
import 'package:plant_companion/widgets/plant_portrait.dart';
import 'package:plant_companion/widgets/sensor_rail.dart';
import 'package:plant_companion/services/simulated_environment.dart';
import 'fixtures/environment_reference.dart';

Map<SensorMetric, TargetRange> conditionRanges({
  Map<SensorMetric, TargetRange> changes = const {},
}) => {...PlantAvatarId.pothos.hints, ...changes};
PlantSimulationContext conditionContext({
  String id = 'plant-1',
  Map<SensorMetric, TargetRange> changes = const {},
}) {
  final ranges = conditionRanges(changes: changes);
  return PlantSimulationContext(
    plantId: id,
    lightRange: ranges[SensorMetric.light]!,
    idealRanges: ranges,
  );
}

Device conditionDevice(
  int sequence, {
  String id = 'device-1',
  String name = 'Device',
  int ordinal = 1,
}) => Device(
  id: id,
  name: name,
  isConnected: true,
  generationSequence: sequence,
  displayOrdinal: ordinal,
);
final conditionTime = DateTime.utc(2026, 11, 7, 12);
Plant samplePlant(PlantSimulationContext context, ConditionSample s) => Plant(
  id: context.plantId,
  nickname: 'Fixture',
  deviceId: s.reading.sourceDeviceId,
  profile: PlantProfile(
    id: 'fixture',
    plantType: 'Fixture',
    ranges: context.idealRanges!,
  ),
  readings: [s.reading],
);
void verifyCondition(PlantSimulationContext context, ConditionSample s) {
  final p = samplePlant(context, s),
      actual = PlantConditionCalculator.calculate(p);
  expect(actual.isComplete, isTrue);
  expect(
    actual.assessment,
    s.mode == ManualPlantCondition.happy
        ? HealthAssessment.healthy
        : HealthAssessment.knownIssue,
  );
  expect(actual.metric, s.mode.metric);
  expect(
    actual.direction,
    s.mode == ManualPlantCondition.happy ? null : s.mode.status,
  );
  var issues = 0;
  for (final m in SensorMetric.values) {
    final v = s.reading.valueFor(m)!;
    expect(v.isFinite, isTrue);
    expect(
      v,
      inInclusiveRange(
        m == SensorMetric.temperature ? -40 : 0,
        m == SensorMetric.temperature
            ? TemperatureDisplayConfig.maximumCelsius
            : m == SensorMetric.light
            ? context.lightMaximum
            : 100,
      ),
    );
    final status = context.idealRanges![m]!.statusFor(v);
    expect(status, s.mode.metric == m ? s.mode.status : ReadingStatus.inRange);
    if (status != ReadingStatus.inRange) issues++;
  }
  expect(issues, s.mode == ManualPlantCondition.happy ? 0 : 1);
}

void main() {
  test(
    '2000 gradual environmental packets stay bit-exact against the preserved baseline, including old extremes',
    () {
      for (final row in [
        const TargetRange(400, 850),
        const TargetRange(800, 12000),
        const TargetRange(.000001, .000002),
        const TargetRange(0, 200000),
      ]) {
        final c = conditionContext(changes: {SensorMetric.light: row});
        var previous = SensorReading(
          recordedAt: conditionTime,
          sourceDeviceId: 'environment-reference',
          soilMoisture: 100,
          light: 200000,
          temperature: 100,
          humidity: 0,
        );
        for (var n = 0; n < 500; n++) {
          final d = conditionDevice(n, id: 'environment-reference'),
              time = conditionTime.add(Duration(minutes: 20 * n));
          final actual = SimulatedEnvironment.sample(
            d,
            time,
            previousReading: previous,
            plantContext: c,
          );
          final expected = FrozenEnvironmentalReference.sample(
            d,
            time,
            previousReading: previous,
            plantContext: c,
          );
          for (final m in SensorMetric.values) {
            expect(actual.valueFor(m), expected.valueFor(m));
          }
          expect(actual.recordedAt, expected.recordedAt);
          expect(actual.sourceDeviceId, expected.sourceDeviceId);
          previous = actual;
        }
      }
    },
  );
  for (final row in [
    (
      SensorMetric.temperature,
      TargetRange(
        fahrenheitToCelsius(65.000001),
        fahrenheitToCelsius(65.000002),
      ),
    ),
    (SensorMetric.light, const TargetRange(1000.000001, 1000.000002)),
  ]) {
    test(
      'sub-quantum ${row.$1.name} ideals exclude fake Happy before selection',
      () {
        final c = conditionContext(changes: {row.$1: row.$2}),
            plan = ConditionDrivenSimulation(c);
        expect(plan.eligibleModes.length, 2);
        expect(plan.eligibleModes.every((m) => m.metric == row.$1), isTrue);
        for (var n = 0; n < 200; n++) {
          verifyCondition(c, plan.sample(conditionDevice(n), conditionTime));
        }
      },
    );
  }
  test(
    'nine modes retain exact 2:1 weights and all-feasible probabilities',
    () {
      final plan = ConditionDrivenSimulation(conditionContext());
      expect(plan.eligibleModes, ManualPlantCondition.values);
      expect(plan.totalWeight, 10);
      expect(ManualPlantCondition.happy.weight, 2);
      for (final m in plan.eligibleModes) {
        expect(
          m.weight / plan.totalWeight,
          m == ManualPlantCondition.happy ? .2 : .1,
        );
      }
    },
  );
  test(
    '20000 deterministic selections approximate weights, allow repeats and have no imposed short cycle',
    () {
      final c = conditionContext(),
          plan = ConditionDrivenSimulation(c),
          counts = {for (final m in ManualPlantCondition.values) m: 0};
      final modes = <ManualPlantCondition>[];
      for (var n = 0; n < 20000; n++) {
        final s = plan.sample(conditionDevice(n), conditionTime);
        counts[s.mode] = counts[s.mode]! + 1;
        modes.add(s.mode);
        verifyCondition(c, s);
      }
      for (final m in ManualPlantCondition.values) {
        expect(
          counts[m]! / 20000,
          closeTo(m == ManualPlantCondition.happy ? .2 : .1, .012),
        );
      }
      expect(
        List.generate(
          modes.length - 1,
          (i) =>
              modes[i] == ManualPlantCondition.happy &&
              modes[i + 1] == modes[i],
        ).contains(true),
        isTrue,
      );
      for (var period = 1; period <= 30; period++) {
        expect(
          List.generate(
            300 - period,
            (i) => modes[i] != modes[i + period],
          ).contains(true),
          isTrue,
        );
      }
    },
  );
  for (final (label, changes) in <(String, Map<SensorMetric, TargetRange>)>[
    ('Florence', {}),
    ('bright', {SensorMetric.light: const TargetRange(800, 12000)}),
    (
      'different ideals',
      {
        SensorMetric.soilMoisture: const TargetRange(10, 90),
        SensorMetric.humidity: const TargetRange(5, 95),
        SensorMetric.temperature: TargetRange(
          fahrenheitToCelsius(-20),
          fahrenheitToCelsius(110),
        ),
        SensorMetric.light: const TargetRange(20000, 60000),
      },
    ),
  ]) {
    for (final mode in ManualPlantCondition.values) {
      test(
        '$label ${mode.name}: exact real condition, four varied values, domain and original face/bubble',
        () {
          final c = conditionContext(changes: changes),
              plan = ConditionDrivenSimulation(c);
          final values = {for (final m in SensorMetric.values) m: <double>{}};
          var found = 0;
          for (var n = 0; n < 10000 && found < 60; n++) {
            final s = plan.sample(conditionDevice(n), conditionTime);
            if (s.mode != mode) continue;
            found++;
            verifyCondition(c, s);
            for (final m in SensorMetric.values) {
              values[m]!.add(s.reading.valueFor(m)!);
            }
            final home = PlantAppearance(samplePlant(c, s)),
                detail = PlantAppearance(samplePlant(c, s), detail: true);
            final face = mode == ManualPlantCondition.happy
                ? 'faces/happy.png'
                : mode == ManualPlantCondition.lightTooLow
                ? 'faces/sleeping.png'
                : 'faces/sad.png';
            expect(home.face, face);
            expect(detail.face, face);
            expect(
              home.need,
              mode == ManualPlantCondition.happy
                  ? null
                  : mode == ManualPlantCondition.temperatureTooLow
                  ? 'needs/cold_thermometer.png'
                  : sensorAsset(mode.metric!),
            );
            expect(
              detail.need,
              mode == ManualPlantCondition.happy
                  ? 'needs/happy_heart.png'
                  : mode == ManualPlantCondition.temperatureTooLow
                  ? 'needs/cold_thermometer.png'
                  : sensorAsset(mode.metric!),
            );
            if (mode.metric != null) {
              final m = mode.metric!, r = c.idealRanges![m]!;
              double shown(double v) {
                final t = metricNumber(m, v);
                return t.endsWith('k')
                    ? double.parse(t.substring(0, t.length - 1)) * 1000
                    : double.parse(t);
              }

              if (mode.status == ReadingStatus.belowRange) {
                expect(
                  shown(s.reading.valueFor(m)!),
                  lessThan(shown(r.minimum)),
                );
              } else {
                expect(
                  shown(s.reading.valueFor(m)!),
                  greaterThan(shown(r.maximum)),
                );
              }
            }
          }
          expect(found, 60);
          for (final set in values.values) {
            expect(set.length, greaterThan(45));
          }
        },
      );
    }
  }
  for (final (label, changes, excluded)
      in <(String, Map<SensorMetric, TargetRange>, List<ManualPlantCondition>)>[
        (
          'full moisture',
          {SensorMetric.soilMoisture: const TargetRange(0, 100)},
          [
            ManualPlantCondition.moistureTooLow,
            ManualPlantCondition.moistureTooHigh,
          ],
        ),
        (
          'full humidity',
          {SensorMetric.humidity: const TargetRange(0, 100)},
          [
            ManualPlantCondition.humidityTooLow,
            ManualPlantCondition.humidityTooHigh,
          ],
        ),
        (
          'minimum temperature',
          {SensorMetric.temperature: TargetRange(-40, fahrenheitToCelsius(85))},
          [ManualPlantCondition.temperatureTooLow],
        ),
        (
          'maximum temperature',
          {
            SensorMetric.temperature: TargetRange(
              fahrenheitToCelsius(65),
              TemperatureDisplayConfig.maximumCelsius,
            ),
          },
          [ManualPlantCondition.temperatureTooHigh],
        ),
        (
          'zero light',
          {SensorMetric.light: const TargetRange(0, 1000)},
          [ManualPlantCondition.lightTooLow],
        ),
        (
          'physical light ceiling',
          {SensorMetric.light: const TargetRange(180000, 200000)},
          [ManualPlantCondition.lightTooHigh],
        ),
      ]) {
    test('$label excludes impossible mode before proportional selection', () {
      final c = conditionContext(changes: changes),
          plan = ConditionDrivenSimulation(c);
      for (final m in excluded) {
        expect(plan.eligibleModes, isNot(contains(m)));
      }
      expect(plan.totalWeight, 10 - excluded.length);
      if (excluded.length == 2) {
        expect(ManualPlantCondition.happy.weight / plan.totalWeight, .25);
      }
      for (var n = 0; n < 500; n++) {
        verifyCondition(c, plan.sample(conditionDevice(n), conditionTime));
      }
    });
  }
  test(
    'renormalized 7-mode set retains 25 percent happy and 12.5 percent each problem',
    () {
      final c = conditionContext(
            changes: {SensorMetric.soilMoisture: const TargetRange(0, 100)},
          ),
          plan = ConditionDrivenSimulation(c);
      final counts = {for (final m in plan.eligibleModes) m: 0};
      for (var n = 0; n < 12000; n++) {
        final m = plan.sample(conditionDevice(n), conditionTime).mode;
        counts[m] = counts[m]! + 1;
      }
      for (final m in plan.eligibleModes) {
        expect(
          counts[m]! / 12000,
          closeTo(m == ManualPlantCondition.happy ? .25 : .125, .015),
        );
      }
    },
  );
  for (final f in [(102.0, 212.0), (130.0, 180.0), (-58.0, -45.0)]) {
    test(
      'legacy temperature ${f.$1}..${f.$2} preserves profile and feasible complete conditions',
      () {
        final r = TargetRange(
          fahrenheitToCelsius(f.$1),
          fahrenheitToCelsius(f.$2),
        );
        final c = conditionContext(changes: {SensorMetric.temperature: r}),
            plan = ConditionDrivenSimulation(c);
        if (f.$1 > 120) {
          expect(plan.eligibleModes, [ManualPlantCondition.temperatureTooLow]);
        }
        if (f.$2 < -40) {
          expect(plan.eligibleModes, [ManualPlantCondition.temperatureTooHigh]);
        }
        for (var n = 0; n < 500; n++) {
          verifyCondition(c, plan.sample(conditionDevice(n), conditionTime));
        }
        expect(c.idealRanges![SensorMetric.temperature], same(r));
      },
    );
  }
  test(
    'quantization-empty ideal in two metrics has no feasible single-condition packet',
    () {
      final c = conditionContext(
        changes: {
          SensorMetric.soilMoisture: const TargetRange(.001, .002),
          SensorMetric.humidity: const TargetRange(.001, .002),
        },
      );
      expect(
        () => ConditionDrivenSimulation(c),
        throwsA(isA<NoFeasibleManualCondition>()),
      );
    },
  );
  test(
    'single quantization-empty ideal restricts selection to that metric, never fake happy',
    () {
      final c = conditionContext(
            changes: {SensorMetric.soilMoisture: const TargetRange(.001, .002)},
          ),
          plan = ConditionDrivenSimulation(c);
      expect(plan.eligibleModes, [
        ManualPlantCondition.moistureTooLow,
        ManualPlantCondition.moistureTooHigh,
      ]);
      for (var n = 0; n < 500; n++) {
        verifyCondition(c, plan.sample(conditionDevice(n), conditionTime));
      }
    },
  );
  for (final range in [
    const TargetRange(.000001, .000002),
    const TargetRange(0, 1e-320),
    const TargetRange(0, 200000),
  ]) {
    test(
      'tiny/subnormal/broad lux ${range.maximum} terminates and stays finite/capped',
      () {
        final c = conditionContext(changes: {SensorMetric.light: range}),
            plan = ConditionDrivenSimulation(c);
        for (var n = 0; n < 400; n++) {
          verifyCondition(c, plan.sample(conditionDevice(n), conditionTime));
        }
        expect(c.lightMaximum, lessThanOrEqualTo(200000));
      },
    );
  }
  test(
    'canonical Celsius quantization and endpoint conversion do not cross selected boundaries',
    () {
      final c = conditionContext(), plan = ConditionDrivenSimulation(c);
      for (var n = 0; n < 3000; n++) {
        final s = plan.sample(conditionDevice(n), conditionTime),
            v = s.reading.temperature!,
            f = celsiusToFahrenheit(v);
        expect(f, inInclusiveRange(-40, 120));
        if (v != TemperatureDisplayConfig.maximumCelsius) {
          expect(v * 10000, closeTo((v * 10000).roundToDouble(), 1e-6));
        }
        verifyCondition(c, s);
      }
    },
  );
  test(
    'immutable IDs and sequence reproduce independently of labels/time and other devices',
    () {
      final c = conditionContext(), plan = ConditionDrivenSimulation(c);
      final a = plan.sample(conditionDevice(17), conditionTime),
          b = plan.sample(
            conditionDevice(17, name: 'Renumbered', ordinal: 99),
            conditionTime.add(const Duration(days: 1)),
          );
      expect(a.mode, b.mode);
      for (final m in SensorMetric.values) {
        expect(a.reading.valueFor(m), b.reading.valueFor(m));
      }
      final next = plan.sample(conditionDevice(18), conditionTime),
          other = plan.sample(
            conditionDevice(17, id: 'device-other'),
            conditionTime,
          );
      expect(
        SensorMetric.values.any(
          (m) => a.reading.valueFor(m) != next.reading.valueFor(m),
        ),
        isTrue,
      );
      expect(
        SensorMetric.values.any(
          (m) => a.reading.valueFor(m) != other.reading.valueFor(m),
        ),
        isTrue,
      );
    },
  );
  test(
    'temperature roundtrip-only endpoint noise is never forced into a high problem',
    () {
      final c = conditionContext(
            changes: {
              SensorMetric.temperature: TargetRange(
                fahrenheitToCelsius(65),
                TemperatureDisplayConfig.maximumCelsius - 1e-12,
              ),
            },
          ),
          plan = ConditionDrivenSimulation(c);
      expect(
        plan.eligibleModes,
        isNot(contains(ManualPlantCondition.temperatureTooHigh)),
      );
    },
  );
  test('all-domain ideals yield only random Happy complete packets', () {
    final c = conditionContext(
          changes: {
            SensorMetric.soilMoisture: const TargetRange(0, 100),
            SensorMetric.humidity: const TargetRange(0, 100),
            SensorMetric.temperature: const TargetRange(
              -40,
              TemperatureDisplayConfig.maximumCelsius,
            ),
            SensorMetric.light: const TargetRange(0, 200000),
          },
        ),
        plan = ConditionDrivenSimulation(c);
    expect(plan.eligibleModes, [ManualPlantCondition.happy]);
    final values = <double>{};
    for (var n = 0; n < 100; n++) {
      final s = plan.sample(conditionDevice(n), conditionTime);
      verifyCondition(c, s);
      values.add(s.reading.light!);
    }
    expect(values.length, greaterThan(90));
  });
}
