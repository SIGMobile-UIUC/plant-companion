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
import 'package:plant_companion/state/plant_store.dart';
import 'package:plant_companion/utils/sensor_scale.dart';
import 'package:plant_companion/utils/sensor_units.dart';
import 'package:plant_companion/widgets/plant_card.dart';
import 'package:plant_companion/widgets/sensor_rail.dart';
import 'fixtures/foundation_fixtures.dart';
import 'app_flow_test.dart' as legacy;

const ranges = [
  TargetRange(400, 850),
  TargetRange(500, 2000),
  TargetRange(20000, 120000),
  TargetRange(500, 200000),
];

void main() {
  const maxima = [1600.0, 1500 / .30, 100000 / .30, 199500 / .30];
  for (final lux in [
    0.0,
    2000.0,
    10000.0,
    20000.0,
    50000.0,
    100000.0,
    150000.0,
    200000.0,
  ]) {
    test(
      '$lux lux uses the shared adaptive transform for every ideal range',
      () {
        for (final (i, range) in ranges.indexed) {
          final scale = SensorScale.forMetric(
            SensorMetric.light,
            range,
            lux,
            plantId: 'fixture',
          );
          expect(scale.minimum, 0);
          expect(scale.maximum, maxima[i]);
          expect(scale.fraction(lux), (lux / maxima[i]).clamp(0, 1));
          expect(scale.fraction(range.minimum), range.minimum / maxima[i]);
          expect(scale.fraction(range.maximum), range.maximum / maxima[i]);
        }
      },
    );
  }

  test(
    'missing/outside readings never change the light domain; other scales are unchanged',
    () {
      for (final current in [null, -100.0, 250000.0]) {
        final scale = SensorScale.forMetric(
          SensorMetric.light,
          ranges.first,
          current,

          plantId: 'fixture',
        );
        expect(scale.minimum, 0);
        expect(scale.maximum, maxima.first);
        if (current != null) {
          expect(scale.fraction(current), current < 0 ? 0 : 1);
        }
      }
      for (final metric in [SensorMetric.soilMoisture, SensorMetric.humidity]) {
        final scale = SensorScale.forMetric(
          metric,
          const TargetRange(20, 70),
          125,

          plantId: 'fixture',
        );
        expect((scale.minimum, scale.maximum), (0.0, 100.0));
        expect(scale.fraction(42), .42);
      }
      final normal = SensorScale.forMetric(
        SensorMetric.temperature,
        PlantAvatarId.pothos.hints[SensorMetric.temperature]!,
        fahrenheitToCelsius(75),

        plantId: 'fixture',
      );
      expect((normal.minimum, normal.maximum), (-40.0, 120.0));
      expect(normal.fraction(75) * 190, closeTo(136.5625, 1e-8));
      final cold = SensorScale.forMetric(
        SensorMetric.temperature,
        TargetRange(fahrenheitToCelsius(-40), fahrenheitToCelsius(-10)),
        fahrenheitToCelsius(-25),

        plantId: 'fixture',
      );
      expect((cold.minimum, cold.maximum), (-40.0, 120.0));
      expect(cold.fraction(-25) * 304, closeTo(28.5, 1e-8));
      expect(metricValue(SensorMetric.soilMoisture, 42), '42%');
      expect(metricValue(SensorMetric.humidity, 55.5), '55.5%');
      expect(
        metricValue(SensorMetric.temperature, fahrenheitToCelsius(75)),
        '75°F',
      );
    },
  );

  test(
    'card lux formatting follows exact threshold/rounding without changing values',
    () {
      final cases = {
        0.0: '0 lux',
        400.0: '400 lux',
        850.0: '850 lux',
        1250.0: '1250 lux',
        2000.0: '2000 lux',
        9999.0: '9999 lux',
        9999.9: '9999.9 lux',
        10000.0: '10k lux',
        20000.0: '20k lux',
        32500.0: '33k lux',
        100250.0: '100k lux',
        150700.0: '151k lux',
        200000.0: '200k lux',
      };
      for (final e in cases.entries) {
        expect(metricValue(SensorMetric.light, e.key), e.value);
      }
      expect(metricRange(SensorMetric.light, ranges[0]), '400 – 850 lux');
      expect(metricRange(SensorMetric.light, ranges[1]), '500 – 2000 lux');
      expect(metricRange(SensorMetric.light, ranges[2]), '20k – 120k lux');
      expect(metricRange(SensorMetric.light, ranges[3]), '500 – 200k lux');
      expect(
        metricValue(SensorMetric.light, 100250, compactLight: false),
        '100250 lux',
      );
      expect(
        metricValue(SensorMetric.light, 100250.25, compactLight: false),
        '100250.25 lux',
      );
      final range = const TargetRange(20500, 120499);
      expect(metricRange(SensorMetric.light, range), '21k – 120k lux');
      expect(range.minimum, 20500);
      expect(range.maximum, 120499);
      expect(range.statusFor(120499.1), ReadingStatus.aboveRange);
    },
  );

  for (var i = 0; i < ranges.length; i++) {
    for (final current in [0.0, 2000.0, 20000.0, 100000.0, 200000.0]) {
      testWidgets(
        'range$i/current$current: truthful ideal positions and contained marker/separators',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 190,
                    child: SensorRail(
                      plantId: 'fixture',
                      metric: SensorMetric.light,
                      range: ranges[i],
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
            closeTo(190 * ranges[i].minimum / maxima[i], 1e-8),
          );
          expect(
            ideal.width,
            closeTo(
              190 * (ranges[i].maximum - ranges[i].minimum) / maxima[i],
              1e-8,
            ),
          );
          expect(
            tester.getSize(find.byKey(const ValueKey('rail-progress'))).width,
            closeTo(190 * (current / maxima[i]).clamp(0, 1), 1e-8),
          );
          final marker = tester.getRect(
            find.byKey(const ValueKey('rail-marker')),
          );
          expect(marker.left, greaterThanOrEqualTo(rail.left));
          expect(marker.right, lessThanOrEqualTo(rail.right));
          if (current == 0) expect(marker.left, rail.left);
          if (current == maxima[i] / 2) {
            expect(marker.center.dx, rail.center.dx);
          }
          if (current >= maxima[i]) expect(marker.right, rail.right);
          final minimum = tester.getRect(
            find.byKey(const ValueKey('rail-min-separator')),
          );
          final maximum = tester.getRect(
            find.byKey(const ValueKey('rail-max-separator')),
          );
          for (final rect in [minimum, maximum]) {
            expect(rect.left, greaterThanOrEqualTo(rail.left));
            expect(rect.right, lessThanOrEqualTo(rail.right));
            expect(rect.width, greaterThanOrEqualTo(0));
          }
          if (i < 2) {
            expect(
              minimum.center.dx - rail.left,
              closeTo(190 * ranges[i].minimum / maxima[i], 1e-8),
            );
            expect(
              maximum.center.dx - rail.left,
              closeTo(190 * ranges[i].maximum / maxima[i], 1e-8),
            );
            expect(minimum.right, lessThanOrEqualTo(maximum.left));
          }
          final image = tester.widget<Image>(
            find.descendant(
              of: find.byKey(const ValueKey('rail-marker')),
              matching: find.byType(Image),
            ),
          );
          expect(image.filterQuality, FilterQuality.none);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test(
    'care ranges still accept200000 and reject invalid input without hardware restrictions',
    () {
      final valid = PlantFormDraft(
        nickname: 'Test',
        speciesName: 'Custom',
        avatar: PlantAvatarId.pothos,
        ranges: {
          ...PlantAvatarId.pothos.hints,
          SensorMetric.light: ranges.last,
        },
      );
      expect(valid.validate, returnsNormally);
      for (final invalid in [
        const TargetRange(-1, 2000),
        const TargetRange(500, 200001),
        const TargetRange(200000, 200000),
      ]) {
        expect(
          () => PlantFormDraft(
            nickname: 'Test',
            speciesName: 'Custom',
            avatar: PlantAvatarId.pothos,
            ranges: {...valid.ranges, SensorMetric.light: invalid},
          ).validate(),
          throwsArgumentError,
        );
      }
    },
  );

  testWidgets(
    'avatar controls create all three original avatars; custom identities remain valid',
    (tester) async {
      final store = await legacy.mountApp(tester, seedDemo: false);
      for (final label in ['Pothos', 'Snake Plant', 'Peace Lily']) {
        await legacy.openAddPlant(tester);
        await tester.enterText(find.byKey(const Key('nickname-field')), label);
        await legacy.chooseProfile(tester, label);
        await legacy.tapVisible(
          tester,
          find.byKey(const Key('save-plant-button')),
        );
      }
      expect(store.plants.map((p) => p.avatar), PlantAvatarId.values);
      expect(store.plants.map((p) => p.speciesName), [
        'Epipremnum aureum',
        'Dracaena trifasciata',
        'Spathiphyllum',
      ]);
      expect(PlantProfile.samples.map((p) => p.plantType), [
        'Pothos',
        'Snake Plant',
        'Peace Lily',
        'Custom',
      ]);
      expect(PlantProfile.legacyMonstera.id, 'monstera');
      for (final p in store.plants) {
        await legacy.tapVisible(
          tester,
          find.byKey(ValueKey('details-${p.id}')),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('details-nickname'))).data,
          p.nickname,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(find.byType(PlantCard), findsWidgets);
    },
  );

  test(
    'file reopen preserves all legacy avatars,old Monstera,custom identity and raw lux/history',
    () async {
      final temp = await Directory.systemTemp.createTemp('plant_v3_');
      final file = File('${temp.path}/plants.sqlite');
      final clock = MutableClock(DateTime.utc(2026, 11, 5));
      var db = AppDatabase(NativeDatabase(file));
      var repo = SqlitePlantRepository(db, clock: clock);
      final store = PlantStore(persistence: repo, clock: clock);
      try {
        await store.initialized;
        for (final profile in PlantProfile.samples.where(
          (p) => p.id != 'custom',
        )) {
          await store.addPlant(nickname: profile.plantType, profile: profile);
        }
        await store.addPlant(
          nickname: 'Old Monstera',
          profile: PlantProfile.legacyMonstera,
        );
        final old = store.plants.last;
        final custom = await repo.save(
          PlantFormDraft(
            nickname: 'Custom entry',
            speciesName: 'User identity ß',
            avatar: PlantAvatarId.peaceLily,
            ranges: {
              ...PlantAvatarId.peaceLily.hints,
              SensorMetric.light: const TargetRange(20500, 120499),
            },
            createDevice: true,
          ),
        );
        final device = await connectFixtureDevice(repo, custom);
        final at = clock.now();
        await repo.commitReading(
          custom,
          device,
          SensorReading(recordedAt: at, light: 100250.25),
        );
        store.dispose();
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        repo = SqlitePlantRepository(db, clock: clock);
        await repo.initialize();
        final plants = await repo.loadPlants();
        for (final (name, avatar) in [
          ('Pothos', PlantAvatarId.pothos),
          ('Snake Plant', PlantAvatarId.snakePlant),
          ('Peace Lily', PlantAvatarId.peaceLily),
        ]) {
          expect(plants.singleWhere((p) => p.nickname == name).avatar, avatar);
        }
        final retained = plants.singleWhere((p) => p.id == old.id);
        expect(
          (
            retained.nickname,
            retained.speciesName,
            retained.avatar,
            retained.createdAt,
          ),
          (old.nickname, old.speciesName, old.avatar, old.createdAt),
        );
        final saved = plants.singleWhere((p) => p.id == custom);
        expect(saved.speciesName, 'User identity ß');
        expect(saved.avatar, PlantAvatarId.peaceLily);
        expect(saved.profile.rangeFor(SensorMetric.light).minimum, 20500);
        expect(saved.profile.rangeFor(SensorMetric.light).maximum, 120499);
        expect(saved.latestReading!.light, 100250.25);
        expect(saved.latestReading!.recordedAt, at);
        expect((await repo.loadHistory(custom)).single.light, 100250.25);
      } finally {
        await repo.close();
        await temp.delete(recursive: true);
      }
    },
  );

  testWidgets('card semantics retain unabridged light values and range text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final plant = Plant(
      id: 'p',
      nickname: 'Raw',
      profile: PlantProfile(
        id: 'p',
        plantType: 'Custom',
        ranges: {
          ...PlantAvatarId.pothos.hints,
          SensorMetric.light: const TargetRange(20500, 120499),
        },
      ),
      deviceId: 'd',
      readings: [
        SensorReading(recordedAt: DateTime.utc(2026), light: 100250.25),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 394,
            child: PlantCard(
              plant: plant,
              device: null,
              now: DateTime.utc(2026),
              onAction: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('100k lux'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Light, 100250\.25 lux.*20500.*120499')),
      findsOneWidget,
    );
    expect(plant.latestReading!.light, 100250.25);
    semantics.dispose();
  });

  test('rounded light text never changes actual health classification', () {
    final plant = Plant(
      id: 'p',
      nickname: 'Raw',
      profile: PlantProfile(
        id: 'p',
        plantType: 'Custom',
        ranges: {
          ...PlantAvatarId.pothos.hints,
          SensorMetric.light: const TargetRange(20000, 120000),
        },
      ),
      deviceId: 'd',
      readings: [
        SensorReading(
          recordedAt: DateTime.utc(2026),
          soilMoisture: 45,
          temperature: fahrenheitToCelsius(75),
          humidity: 55,
          light: 120000.1,
        ),
      ],
    );
    expect(
      metricValue(SensorMetric.light, plant.latestReading!.light),
      '120k lux',
    );
    expect(
      PlantConditionCalculator.calculate(plant).assessment,
      HealthAssessment.knownIssue,
    );
    expect(
      PlantConditionCalculator.calculate(plant).direction,
      ReadingStatus.aboveRange,
    );
  });
}
