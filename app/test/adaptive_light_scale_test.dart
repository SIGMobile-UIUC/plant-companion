import 'dart:math' as math;
import 'fixtures/v4_light_reference.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'package:plant_companion/services/plant_condition_calculator.dart';
import 'package:plant_companion/utils/sensor_scale.dart';
import 'package:plant_companion/widgets/plant_card.dart';
import 'package:plant_companion/widgets/sensor_rail.dart';
import 'fixtures/foundation_fixtures.dart';

const lightRanges = [
  TargetRange(400, 850),
  TargetRange(500, 1000),
  TargetRange(500, 2000),
  TargetRange(20000, 120000),
  TargetRange(500, 200000),
  TargetRange(0, 1000),
  TargetRange(.000001, .000002),
  TargetRange(999.999, 1000),
  // No two-significant-digit rounded maximum fits this feasible interval.
  TargetRange(333.4, 1000),
  TargetRange(199999, 200000),
];

SensorScale light(String id, TargetRange range, [double? reading]) =>
    SensorScale.forMetric(SensorMetric.light, range, reading, plantId: id);

void main() {
  for (final (i, range) in lightRanges.indexed) {
    test(
      'range$i: zero endpoint, feasible constraints or exact wide fallback',
      () {
        final endpoints = <double>{};
        for (var plant = 0; plant < 100; plant++) {
          final id = 'plant-$plant';
          final scale = light(id, range);
          final maximum = scale.maximum;
          endpoints.add(maximum);
          expect(scale.minimum, 0);
          expect(maximum.isFinite, isTrue);
          expect(maximum, greaterThan(0));
          final original = originalV4LightMaximum(id, range);
          expect(
            maximum,
            math.max(original, (range.maximum - range.minimum) / .30),
          );
          expect(
            (range.maximum - range.minimum) / maximum,
            lessThanOrEqualTo(.30 + 1e-12),
          );
          expect(maximum, greaterThanOrEqualTo(original));
          if ((range.maximum - range.minimum) / original <= .30) {
            expect(maximum, original);
          }
          expect(
            scale.fraction(range.midpoint),
            inInclusiveRange(
              scale.fraction(range.minimum),
              scale.fraction(range.maximum),
            ),
          );
          for (final value in [
            0.0,
            range.minimum,
            range.midpoint,
            range.maximum,
            200000.0,
          ]) {
            expect(scale.fraction(value), (value / maximum).clamp(0, 1));
            expect(light(id, range, value).maximum, maximum);
          }
          expect(light(id, range).maximum, maximum);
        }
        if ((range.maximum - range.minimum) / .30 < 4 * range.minimum) {
          expect(endpoints.length, greaterThan(1));
        }
      },
    );
  }

  test(
    'stable ID/range goldens agree across VM and browser; edits are deterministic',
    () {
      const range = TargetRange(500, 1000);
      expect(light('plant-1', range).maximum, 500 / .30);
      expect(light('plant-2', range).maximum, 2000);
      expect(light('plant-3', range).maximum, 1900);
      expect(light('plant-1', const TargetRange(400, 850)).maximum, 1500);
      expect(light('plant-1', range).maximum, 500 / .30);
      expect(() => light('', range), throwsArgumentError);
      expect(
        () => light('p', const TargetRange(-1, 1000)),
        throwsArgumentError,
      );
    },
  );

  test(
    'only display endpoint may exceed input bound; raw values and formats survive',
    () {
      final scale = light('p', const TargetRange(500, 200000));
      expect(scale.maximum, greaterThan(200000));
      expect(PlantFormDraft.sensorBounds(SensorMetric.light), (0.0, 200000.0));
      expect(metricValue(SensorMetric.light, 100250.25), '100k lux');
      expect(
        metricValue(SensorMetric.light, 100250.25, compactLight: false),
        '100250.25 lux',
      );
      expect(
        light(
          'plant-1',
          const TargetRange(500, 1000),
          100250.25,
        ).fraction(100250.25),
        1,
      );
    },
  );

  for (final range in lightRanges.take(5)) {
    testWidgets(
      '${range.minimum}–${range.maximum}: shared rendered geometry, rebuilds and endpoint containment',
      (tester) async {
        final scale = light('v4-a', range);
        for (final width in [190.0, 304.0]) {
          Rect? previousIdeal;
          for (final current in [
            null,
            0.0,
            range.minimum,
            range.midpoint,
            range.maximum,
            200000.0,
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: SensorRail(
                        plantId: 'v4-a',
                        metric: SensorMetric.light,
                        range: range,
                        current: current,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final rail = tester.getRect(find.byType(SensorRail));
            final ideal = tester.getRect(
              find.byKey(const ValueKey('rail-ideal')),
            );
            expect(
              ideal.left - rail.left,
              closeTo(width * range.minimum / scale.maximum, 1e-8),
            );
            expect(
              ideal.width,
              closeTo(
                width * (range.maximum - range.minimum) / scale.maximum,
                1e-8,
              ),
            );
            if (previousIdeal != null) expect(ideal, previousIdeal);
            previousIdeal = ideal;
            for (final (key, boundary) in [
              ('rail-min-separator', range.minimum),
              ('rail-max-separator', range.maximum),
            ]) {
              final separator = tester.getRect(find.byKey(ValueKey(key)));
              final edge = width * boundary / scale.maximum;
              final thickness = (ideal.width / 2).clamp(0.0, 2.0);
              expect(
                separator.left - rail.left,
                closeTo((edge - thickness / 2).clamp(0.0, width), 1e-8),
              );
              expect(
                separator.right - rail.left,
                closeTo((edge + thickness / 2).clamp(0.0, width), 1e-8),
              );
              expect(separator.left, greaterThanOrEqualTo(rail.left));
              expect(separator.right, lessThanOrEqualTo(rail.right));
            }
            if (current == null) {
              expect(find.byKey(const ValueKey('rail-marker')), findsNothing);
              expect(find.byKey(const ValueKey('rail-progress')), findsNothing);
            } else {
              final progress = tester
                  .getSize(find.byKey(const ValueKey('rail-progress')))
                  .width;
              expect(
                progress,
                closeTo(width * (current / scale.maximum).clamp(0, 1), 1e-8),
              );
              final marker = tester.getRect(
                find.byKey(const ValueKey('rail-marker')),
              );
              expect(marker.left, greaterThanOrEqualTo(rail.left));
              expect(marker.right, lessThanOrEqualTo(rail.right));
              if (current == 0) expect(marker.left, rail.left);
              if (current >= scale.maximum) expect(marker.right, rail.right);
            }
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  }

  testWidgets(
    'card passes its stable ID, shows true over-axis number and no-device midpoint',
    (tester) async {
      const range = TargetRange(500, 1000);
      final profile = PlantProfile(
        id: 'custom',
        plantType: 'Custom',
        ranges: {...PlantAvatarId.pothos.hints, SensorMetric.light: range},
      );
      Future<void> card(Plant plant) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 394,
                child: PlantCard(
                  plant: plant,
                  device: null,
                  now: DateTime.utc(2026, 11, 6),
                  onAction: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      final actual = Plant(
        id: 'plant-1',
        nickname: 'Actual',
        profile: profile,
        deviceId: 'd',
        readings: [
          SensorReading(
            recordedAt: DateTime.utc(2026, 11, 6),
            light: 100250.25,
          ),
        ],
      );
      await card(actual);
      expect(find.text('100k lux'), findsOneWidget);
      final rail = find.byWidgetPredicate(
        (w) => w is SensorRail && w.metric == SensorMetric.light,
      );
      expect(tester.widget<SensorRail>(rail).plantId, 'plant-1');
      expect(
        tester
            .getSize(
              find.descendant(
                of: rail,
                matching: find.byKey(const ValueKey('rail-progress')),
              ),
            )
            .width,
        tester.getSize(rail).width,
      );
      expect(actual.latestReading!.light, 100250.25);
      expect(
        PlantConditionCalculator.calculate(actual).direction,
        ReadingStatus.aboveRange,
      );
      final demo = Plant(id: 'plant-1', nickname: 'Demo', profile: profile);
      await card(demo);
      expect(find.text('750 lux'), findsOneWidget);
      expect(tester.widget<SensorRail>(rail).current, 750);
      expect(
        tester
            .getSize(
              find.descendant(
                of: rail,
                matching: find.byKey(const ValueKey('rail-progress')),
              ),
            )
            .width,
        closeTo(tester.getSize(rail).width * 750 / (500 / .30), 1e-8),
      );
      expect(demo.readings, isEmpty);
      expect(ReadingPresentation(demo).timestamp, isNull);
      expect(
        PlantConditionCalculator.calculate(demo).assessment,
        HealthAssessment.unassessed,
      );
    },
  );

  test(
    'SQLite reopen, reading acquisition and metadata edit preserve scale, raw packets and ranges',
    () async {
      final directory = await Directory.systemTemp.createTemp('plant_v4_');
      final clock = MutableClock(DateTime.utc(2026, 11, 6));
      SqlitePlantRepository open() => SqlitePlantRepository(
        AppDatabase(NativeDatabase(File('${directory.path}/plants.sqlite'))),
        clock: clock,
      );
      var repo = open();
      try {
        await repo.initialize();
        const range = TargetRange(500, 1000);
        PlantFormDraft form(
          String name, {
          String? deviceId,
          bool create = false,
          TargetRange bounds = range,
        }) => PlantFormDraft(
          nickname: name,
          speciesName: 'User identity',
          avatar: PlantAvatarId.peaceLily,
          ranges: {
            ...PlantAvatarId.peaceLily.hints,
            SensorMetric.light: bounds,
          },
          deviceId: deviceId,
          createDevice: create,
        );
        final id = await repo.save(form('Stable', create: true));
        await connectFixtureDevice(repo, id);
        final device = (await repo.loadAssignedDevices())[id]!;
        final before = light(id, range).maximum;
        for (var n = 0; n < 2; n++) {
          clock.value = clock.now().add(const Duration(minutes: 20));
          expect(
            await repo.commitReading(
              id,
              (await repo.loadAssignedDevices())[id]!,
              SensorReading(
                recordedAt: clock.now(),
                light: [100250.25, 280.0][n],
                origin: n == 0 ? 'manual' : 'automatic',
              ),
              origin: n == 0 ? 'manual' : 'automatic',
              autoSlot: n == 1 ? 2 : null,
            ),
            isTrue,
          );
        }
        await repo.save(form('Renamed', deviceId: device.id), plantId: id);
        await repo.close();
        repo = open();
        await repo.initialize();
        final plant = (await repo.loadPlants()).singleWhere((p) => p.id == id);
        expect(
          light(
            plant.id,
            plant.profile.rangeFor(SensorMetric.light),
            plant.latestReading!.light,
          ).maximum,
          before,
        );
        expect(plant.avatar, PlantAvatarId.peaceLily);
        expect(plant.nickname, 'Renamed');
        final history = await repo.loadHistory(id);
        expect(history.map((r) => r.light).toSet(), {100250.25, 280.0});
        expect(history.map((r) => r.recordedAt).toSet(), {
          DateTime.utc(2026, 11, 6, 0, 20),
          DateTime.utc(2026, 11, 6, 0, 40),
        });
        const edited = TargetRange(400, 850);
        await repo.save(
          form('Renamed', deviceId: device.id, bounds: edited),
          plantId: id,
        );
        final changed = (await repo.loadPlants()).singleWhere(
          (p) => p.id == id,
        );
        expect(
          light(id, changed.profile.rangeFor(SensorMetric.light)).maximum,
          light(id, edited).maximum,
        );
        expect(light(id, edited).maximum, isNot(before));
        expect(
          (await repo.loadHistory(id)).map((r) => r.id),
          history.map((r) => r.id),
        );
      } finally {
        await repo.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
