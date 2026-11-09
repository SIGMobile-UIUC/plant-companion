import 'fixtures/simulation_context.dart';
import 'package:plant_companion/config/temperature_display_config.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/plant_condition_calculator.dart';
import 'package:plant_companion/services/sensor_gateway.dart';
import 'package:plant_companion/services/simulated_environment.dart';
import 'package:plant_companion/services/simulation_config.dart';
import 'package:plant_companion/theme/app_theme.dart';
import 'package:plant_companion/utils/sensor_scale.dart';
import 'package:plant_companion/widgets/plant_portrait.dart';
import 'package:plant_companion/widgets/reading_card.dart';
import 'package:plant_companion/widgets/sensor_rail.dart';

final manualAt = DateTime.utc(2026, 11, 7, 12);
Device manualDevice(String id, int sequence, {String name = 'ESP32-Sim01'}) =>
    Device(id: id, name: name, isConnected: true, generationSequence: sequence);
SensorReading manualSample(Device d, {SensorReading? previous}) =>
    SimulatedEnvironment.sample(
      d,
      manualAt,
      previousReading: previous,
      simulationMode: SimulationMode.manualConditionDriven,
      plantContext: simulationContext,
    );
List<double?> manualValues(SensorReading r) =>
    SensorMetric.values.map(r.valueFor).toList();

void main() {
  test(
    'condition v4 reference is reproducible and ignores previous values and labels',
    () {
      final d = manualDevice('device-1', 0);
      final r = manualSample(d);
      expect(manualValues(r), [68.21, 27.2698, 40.39, 635.11]);
      final extreme = SensorReading(
        recordedAt: manualAt,
        sourceDeviceId: d.id,
        soilMoisture: 100,
        light: 200000,
        temperature: -50,
        humidity: 0,
      );
      expect(manualValues(manualSample(d, previous: extreme)), manualValues(r));
      expect(
        manualValues(
          SimulatedEnvironment.sample(
            manualDevice(d.id, 0, name: 'ESP32-Sim99'),
            manualAt.add(const Duration(days: 100)),
            previousReading: extreme,
            simulationMode: SimulationMode.manualConditionDriven,
            plantContext: simulationContext,
          ),
        ),
        manualValues(r),
      );
      expect(
        manualValues(manualSample(manualDevice(d.id, 1))),
        isNot(manualValues(r)),
      );
    },
  );
  for (final id in ['device-1', 'device-2', 'device-3']) {
    test('1000 deterministic weighted packets: $id', () {
      final packets = List.generate(
        1000,
        (i) => manualSample(manualDevice(id, i)),
      );
      for (final m in SensorMetric.values) {
        final c = SimulationConfig.metrics[m]!;
        final low = m == SensorMetric.temperature
            ? TemperatureDisplayConfig.minimumCelsius
            : c.minimum;
        final high = m == SensorMetric.light
            ? simulationContext.lightMaximum
            : m == SensorMetric.temperature
            ? TemperatureDisplayConfig.maximumCelsius
            : c.maximum;
        final values = packets.map((r) => r.valueFor(m)!).toList();
        expect(values, everyElement(inInclusiveRange(low, high)));
        final u = values.map((v) => (v - low) / (high - low)).toList();
        expect(values.toSet().length, greaterThan(800));
        expect(u.reduce(math.min), greaterThanOrEqualTo(0));
        expect(u.reduce(math.max), lessThanOrEqualTo(1));
        for (var period = 1; period <= 32; period++) {
          expect(
            List.generate(
              values.length - period,
              (i) => values[i] == values[i + period],
            ).every((x) => x),
            isFalse,
          );
        }
        final jumps = List.generate(
          u.length - 1,
          (i) => (u[i + 1] - u[i]).abs(),
        );
        expect(
          jumps.reduce(math.max) * (high - low),
          greaterThan(c.maximumChange * 3),
        );
        expect(
          List.generate(
            values.length - 1,
            (i) => (values[i + 1] - values[i]).abs(),
          ).where((v) => v > c.maximumChange).length,
          greaterThan(100),
        );
      }
      final counts = <String, int>{};
      for (final r in packets) {
        final issues = [
          for (final m in SensorMetric.values)
            if (simulationContext.idealRanges![m]!.statusFor(r.valueFor(m)) !=
                ReadingStatus.inRange)
              m,
        ];
        expect(issues.length, lessThanOrEqualTo(1));
        final key = issues.isEmpty
            ? 'happy'
            : '${issues.single.name}:${simulationContext.idealRanges![issues.single]!.statusFor(r.valueFor(issues.single)).name}';
        counts[key] = (counts[key] ?? 0) + 1;
      }
      expect(counts.length, 9);
      expect(counts['happy']! / 1000, closeTo(.2, .045));
      for (final e in counts.entries) {
        if (e.key != 'happy') expect(e.value / 1000, closeTo(.1, .045));
      }
      final directions = <String>{};
      for (var i = 1; i < packets.length; i++) {
        directions.add(
          SensorMetric.values
              .map(
                (m) => (packets[i].valueFor(m)! - packets[i - 1].valueFor(m)!)
                    .sign
                    .toInt(),
              )
              .join(','),
        );
      }
      expect(directions.length, greaterThanOrEqualTo(16));
      expect(
        manualValues(packets[0]),
        isNot(manualValues(manualSample(manualDevice('$id-other', 0)))),
      );
    });
  }
  test(
    'environment v1 remains exact and gradual after a full-range packet',
    () {
      const original = Device(
        id: 'device-1',
        name: 'ignored',
        isConnected: true,
      );
      final seed = SensorReading(
        recordedAt: manualAt,
        sourceDeviceId: original.id,
        soilMoisture: 38,
        light: 280,
        temperature: (75 - 32) * 5 / 9,
        humidity: 42,
      );
      final unchanged = SimulatedEnvironment.sample(
        original,
        manualAt,
        previousReading: seed,
        plantContext: simulationContext,
      );
      expect(manualValues(unchanged), [38.89, 23.9395, 43.79, 351.88]);
      final full = manualSample(original);
      final next = SimulatedEnvironment.sample(
        manualDevice(original.id, 1),
        manualAt,
        previousReading: full,
        plantContext: simulationContext,
      );
      for (final m in SensorMetric.values) {
        final c = SimulationConfig.metrics[m]!;
        expect(
          (next.valueFor(m)! - full.valueFor(m)!).abs(),
          lessThanOrEqualTo(c.maximumChange + 1 / c.scale),
        );
      }
    },
  );
  test(
    'actual random packets drive each need direction and healthy state without changing priority',
    () {
      final r = manualSample(manualDevice('device-1', 0));
      final full = {
        for (final m in SensorMetric.values)
          m: TargetRange(
            SimulationConfig.metrics[m]!.minimum,
            SimulationConfig.metrics[m]!.maximum,
          ),
      };
      Plant plant(Map<SensorMetric, TargetRange> ranges) => Plant(
        id: 'test',
        nickname: 'Test',
        deviceId: 'device-1',
        profile: PlantProfile(id: 'test', plantType: 'Test', ranges: ranges),
        readings: [r],
      );
      final healthy = plant(full);
      expect(
        PlantConditionCalculator.calculate(healthy).assessment,
        HealthAssessment.healthy,
      );
      expect(
        PlantAppearance(healthy, detail: true).need,
        'needs/happy_heart.png',
      );
      for (final m in PlantConditionCalculator.priority) {
        final c = SimulationConfig.metrics[m]!, value = r.valueFor(m)!;
        for (final below in [true, false]) {
          final range = below
              ? TargetRange(value + (c.maximum - value) * .25, c.maximum)
              : TargetRange(c.minimum, c.minimum + (value - c.minimum) * .75);
          final p = plant({...full, m: range});
          final condition = PlantConditionCalculator.calculate(p);
          expect(condition.metric, m);
          expect(
            condition.direction,
            below ? ReadingStatus.belowRange : ReadingStatus.aboveRange,
          );
          expect(
            PlantAppearance(p, detail: true).need,
            m == SensorMetric.temperature && below
                ? 'needs/cold_thermometer.png'
                : sensorAsset(m),
          );
          expect(
            PlantAppearance(p).face,
            m == SensorMetric.light && below
                ? 'faces/sleeping.png'
                : 'faces/sad.png',
          );
        }
      }
      final allLow = plant({
        for (final m in SensorMetric.values)
          m: TargetRange(
            r.valueFor(m)! + 1,
            SimulationConfig.metrics[m]!.maximum,
          ),
      });
      expect(
        PlantConditionCalculator.calculate(allLow).metric,
        SensorMetric.soilMoisture,
      );
    },
  );
  testWidgets(
    'historical off-envelope light stays accurate while its marker clamps',
    (tester) async {
      final r = SensorReading(
        recordedAt: manualAt,
        sourceDeviceId: 'device-1',
        light: 38419.7,
      );
      const range = TargetRange(400, 850);
      final scale = SensorScale.forMetric(
        SensorMetric.light,
        range,
        r.light,
        plantId: 'plant-1',
      );
      expect(scale.maximum, 1500);
      expect(r.light, greaterThan(scale.maximum));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 394,
                child: ReadingCard(
                  plantId: 'plant-1',
                  metric: SensorMetric.light,
                  range: range,
                  value: r.light,
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('details-value-light')))
            .data,
        '38419.7 lux',
      );
      final width = tester.getSize(find.byType(SensorRail)).width;
      expect(
        tester
            .widget<Positioned>(find.byKey(const ValueKey('rail-marker')))
            .left,
        closeTo(width - 11, 1e-8),
      );
      expect(metricValue(SensorMetric.light, r.light), '38k lux');
      expect(r.light, 38419.7);
      expect(tester.takeException(), isNull);
    },
  );
}
