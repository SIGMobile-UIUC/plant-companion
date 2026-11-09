import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/config/temperature_display_config.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/plant_form_input.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/services/reading_scheduler.dart';
import 'package:plant_companion/theme/app_theme.dart';
import 'package:plant_companion/utils/sensor_scale.dart';
import 'package:plant_companion/utils/sensor_units.dart';
import 'package:plant_companion/widgets/plant_card.dart';
import 'package:plant_companion/widgets/sensor_rail.dart';
import 'fixtures/foundation_fixtures.dart';
import 'fixtures/form_actions.dart';
import 'form_input_and_preview_test.dart' show validInputs;
import 'plant_form_widget_test.dart' as forms;
import 'scale_context_test.dart' show ScaleGate;

class ReconnectProfileGate extends FakeSensorRepository {
  ReconnectProfileGate() : super(delay: Duration.zero);
  final entered = Completer<void>(), release = Completer<void>();
  PlantSimulationContext? acquired;
  @override
  Future<Device> connect(Device d, {bool simulateFailure = false}) async {
    entered.complete();
    await release.future;
    return super.connect(d, simulateFailure: simulateFailure);
  }

  @override
  Future<SensorReading> acquire(
    Device d,
    DateTime at, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) {
    acquired = plantContext;
    return super.acquire(
      d,
      at,
      previousReading: previousReading,
      simulationMode: simulationMode,
      plantContext: plantContext,
    );
  }
}

void main() {
  test(
    'partially corrected legacy temperature keeps genuine preview values without enabling Save',
    () {
      final b = validInputs()..[SensorMetric.temperature] = ['105', '212'];
      final input = PlantFormInput(
        nickname: 'Legacy',
        fullName: '',
        species: 'Species',
        bounds: b,
      );
      final preview = input.previewRanges(
        PlantAvatarId.pothos,
        originalTemperature: TargetRange(
          fahrenheitToCelsius(102),
          fahrenheitToCelsius(212),
        ),
        originalTemperatureText: ['102', '212'],
      );
      expect(
        preview[SensorMetric.temperature]!.minimum,
        fahrenheitToCelsius(105),
      );
      expect(preview[SensorMetric.temperature]!.maximum, 100);
      expect(
        input.errors['range-temperature-1'],
        TemperatureDisplayConfig.rangeError,
      );
    },
  );
  test(
    'repository rejects unchanged legacy Save before allocation; load/cancel and explicit Delete stay safe',
    () async {
      final repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 7)));
      try {
        await repo.initialize();
        await repo.database.customStatement(
          "UPDATE plant_ranges SET minimum=?,maximum=? WHERE plant_id='plant-1' AND metric='temperature'",
          [fahrenheitToCelsius(102), fahrenheitToCelsius(212)],
        );
        final p = (await repo.loadPlants()).single;
        final before = {
          for (final table in [
            'plants',
            'devices',
            'plant_ranges',
            'sensor_readings',
          ])
            table: await repo.database.rows('SELECT * FROM $table'),
        };
        await expectLater(
          repo.save(
            PlantFormDraft(
              nickname: 'Changed nickname',
              speciesName: p.speciesName,
              avatar: p.avatar,
              ranges: p.profile.ranges,
              createDevice: true,
            ),
            plantId: p.id,
          ),
          throwsA(isA<PlantValidationError>()),
        );
        for (final table in before.keys) {
          expect(
            await repo.database.rows('SELECT * FROM $table'),
            before[table],
          );
        }
        expect(
          (await repo.loadPlants()).single.profile
              .rangeFor(SensorMetric.temperature)
              .maximum,
          fahrenheitToCelsius(212),
        );
        await repo.deletePlant(p.id);
        expect(await repo.loadPlants(), isEmpty);
      } finally {
        await repo.close();
      }
    },
  );
  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(390, 844),
    const Size(430, 925),
    const Size(480, 960),
    const Size(1024, 900),
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
        'uniform card slots ${size.width}x${size.height} text $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Size? cardSize;
          Map<SensorMetric, Rect>? originalRails;
          final headersByName = <String, Map<String, Rect>>{};
          Rect? originalBadge;
          var actions = 0;
          for (var state = 0; state < 9; state++) {
            final avatar = PlantAvatarId.values[state % 3],
                connected = state % 2 == 0;
            final ranges = {
              ...avatar.hints,
              if (state >= 3) SensorMetric.light: const TargetRange(800, 12000),
              if (state == 7)
                SensorMetric.temperature: TargetRange(
                  fahrenheitToCelsius(102),
                  fahrenheitToCelsius(212),
                ),
            };
            final p = Plant(
              id: 'card',
              nickname: state >= 4
                  ? 'A long nickname requiring two lines of display'
                  : 'Fern',
              speciesName: state >= 5
                  ? 'Very long scientific species name with many words'
                  : 'Species',
              avatar: avatar,
              deviceId: state == 2 ? null : 'device',
              profile: PlantProfile(
                id: 'p',
                plantType: 'Species',
                ranges: ranges,
              ),
              readings: state == 1
                  ? []
                  : [
                      SensorReading(
                        recordedAt: DateTime.utc(2026, 11, 7),
                        soilMoisture: state * 12.0,
                        humidity: state * 11.0,
                        temperature: state * 10.0,
                        light: 13771.1 * state,
                      ),
                    ],
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: buildAppTheme(),
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: PlantCard(
                        plant: p,
                        device: state == 2
                            ? null
                            : Device(
                                id: 'device',
                                name: 'Device',
                                isConnected: connected,
                              ),
                        now: DateTime.utc(2026, 11, 7),
                        edit: state == 6,
                        preview: state == 8,
                        onAction: () => actions++,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final card = tester.getRect(find.byType(PlantCard));
            cardSize ??= card.size;
            expect(card.size, cardSize);
            if (size.width == 430 && scale == 1) {
              expect(card.size, const Size(394, 224));
            }
            final rails = {
              for (final m in cardMetrics)
                m: tester
                    .getRect(
                      find.byWidgetPredicate(
                        (w) => w is SensorRail && w.metric == m,
                      ),
                    )
                    .shift(-card.topLeft),
            };
            originalRails ??= rails;
            expect(rails, originalRails);
            final header = {
              for (final k in ['card-title', 'card-species'])
                k: tester.getRect(find.byKey(ValueKey(k))).shift(-card.topLeft),
              'badge': tester
                  .getRect(find.byType(ConnectionBadge))
                  .shift(-card.topLeft),
            };
            headersByName.putIfAbsent(p.nickname, () => header);
            expect(header, headersByName[p.nickname]);
            originalBadge ??= header['badge'];
            expect(header['badge'], originalBadge);
            for (final m in cardMetrics) {
              final label = tester.getRect(
                    find.byKey(ValueKey('card-label-${m.name}')),
                  ),
                  value = tester.getRect(
                    find.byKey(ValueKey('card-value-${m.name}')),
                  );
              expect(label.right, lessThanOrEqualTo(value.left - 7.9));
              expect(value.right, lessThanOrEqualTo(card.right));
            }
            expect(find.textContaining('partly off chart'), findsNothing);
            expect(tester.takeException(), isNull);
            if (state == 0) {
              await tester.tap(find.byKey(const ValueKey('details-card')));
              expect(actions, 1);
            }
          }
        },
      );
    }
  }
  for (final row in [
    ('-40', '120', true),
    ('65', '85', true),
    ('-41', '85', false),
    ('65', '121', false),
    ('102', '212', false),
    ('120', '120', false),
    ('100', '95', false),
    ('NaN', '85', false),
    ('65', 'Infinity', false),
    ('', '85', false),
    ('65', '', false),
    ('-40.00001', '85', false),
    ('65', '120.00001', false),
  ]) {
    test('strict Fahrenheit input ${row.$1}..${row.$2}', () {
      final b = validInputs()..[SensorMetric.temperature] = [row.$1, row.$2];
      final i = PlantFormInput(
        nickname: 'Plant',
        fullName: '',
        species: 'Species',
        bounds: b,
      );
      expect(i.errors.isEmpty, row.$3);
      if (row.$1 == '-41' || row.$2 == '121') {
        expect(i.errors.values, contains(TemperatureDisplayConfig.rangeError));
      }
      if (row.$1 == '120' || row.$1 == '100') {
        expect(
          i.errors.values,
          contains('Maximum must be greater than minimum.'),
        );
      }
    });
  }
  test(
    'canonical Save boundary accepts endpoint rounding noise but rejects bypassed invalid care',
    () {
      for (final r in [
        const TargetRange(-40, 48.888888888888886),
        const TargetRange(-40, 48.8888888889),
        TargetRange(fahrenheitToCelsius(-41), 20),
        TargetRange(20, fahrenheitToCelsius(121)),
        const TargetRange(100, 100),
      ]) {
        final d = PlantFormDraft(
          nickname: 'Test',
          speciesName: 'Test',
          avatar: PlantAvatarId.pothos,
          ranges: {...PlantAvatarId.pothos.hints, SensorMetric.temperature: r},
        );
        expect(
          d.validate,
          r.minimum >= -40 && r.maximum < 49
              ? returnsNormally
              : throwsA(isA<PlantValidationError>()),
        );
      }
    },
  );
  test(
    'legacy endpoint just outside chart is never rounded into apparently valid form text',
    () {
      final r = TargetRange(
        fahrenheitToCelsius(65),
        fahrenheitToCelsius(120.00001),
      );
      final text = temperatureRangeInputNumbers(r);
      expect(double.parse(text.last), greaterThan(120));
    },
  );
  testWidgets(
    'legacy Edit shows genuine range, blocks nickname-only Save, cancels intact then corrects',
    (tester) async {
      final f = await forms.mountD(tester);
      await tester.runAsync(() async {
        await f.repo.database.customStatement(
          "UPDATE plant_ranges SET minimum=?,maximum=? WHERE plant_id='plant-1' AND metric='temperature'",
          [fahrenheitToCelsius(102), fahrenheitToCelsius(212)],
        );
        await f.store.reload();
      });
      final history = await tester.runAsync(
        () => f.repo.database.rows('SELECT * FROM sensor_readings'),
      );
      await forms.openEditD(tester);
      String field(String k) =>
          tester.widget<TextFormField>(find.byKey(Key(k))).controller!.text;
      expect(field('range-temperature-0'), '102');
      expect(field('range-temperature-1'), '212');
      final preview = tester.widget<PlantCard>(find.byType(PlantCard));
      expect(
        preview.plant.profile.rangeFor(SensorMetric.temperature).maximum,
        fahrenheitToCelsius(212),
      );
      await enterFormText(tester, 'nickname-field', 'Only nickname changed');
      await forms.dTap(tester, find.byKey(const Key('save-changes-button')));
      expect(find.text(TemperatureDisplayConfig.rangeError), findsOneWidget);
      expect(f.store.plantById('plant-1').nickname, 'Florence');
      Navigator.of(tester.element(find.byType(PlantCard))).pop();
      await tester.pumpAndSettle();
      expect(
        f.store
            .plantById('plant-1')
            .profile
            .rangeFor(SensorMetric.temperature)
            .maximum,
        fahrenheitToCelsius(212),
      );
      await forms.dTap(tester, find.byKey(const Key('details-edit-plant-1')));
      await enterFormText(tester, 'range-temperature-0', '-40');
      await enterFormText(tester, 'range-temperature-1', '120');
      await forms.dTap(tester, find.byKey(const Key('save-changes-button')));
      expect(
        f.store
            .plantById('plant-1')
            .profile
            .rangeFor(SensorMetric.temperature)
            .maximum,
        TemperatureDisplayConfig.maximumCelsius,
      );
      expect(
        await tester.runAsync(
          () => f.repo.database.rows('SELECT * FROM sensor_readings'),
        ),
        history,
      );
      await f.close(tester);
    },
  );
  testWidgets(
    'Add shows exact inline out-of-range message then accepts inclusive endpoints',
    (tester) async {
      final f = await forms.mountD(tester, empty: true);
      await forms.openAddD(tester);
      await fillPlantForm(tester);
      await enterFormText(tester, 'range-temperature-0', '-41');
      await forms.dTap(tester, find.byKey(const Key('save-plant-button')));
      expect(find.text(TemperatureDisplayConfig.rangeError), findsOneWidget);
      expect(f.store.plants, isEmpty);
      await enterFormText(tester, 'range-temperature-0', '-40');
      await enterFormText(tester, 'range-temperature-1', '120');
      await forms.dTap(tester, find.byKey(const Key('save-plant-button')));
      expect(
        f.store.plants.single.profile
            .rangeFor(SensorMetric.temperature)
            .minimum,
        -40,
      );
      await f.close(tester);
    },
  );
  test(
    'reconnection uses profile committed during delayed connection, not pre-connection context',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 11, 7)),
          repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 7)));
      await repo.initialize();
      await repo.setConnection('device-1', false);
      final gate = ReconnectProfileGate(),
          scheduler = ReadingScheduler(repo, gate, clock: clock);
      try {
        final pending = scheduler.refreshAssigned('plant-1', gate);
        await gate.entered.future;
        final p = (await repo.loadPlants()).single;
        await repo.save(
          PlantFormDraft(
            nickname: p.nickname,
            speciesName: p.speciesName,
            avatar: p.avatar,
            deviceId: p.deviceId,
            ranges: {
              ...p.profile.ranges,
              SensorMetric.light: const TargetRange(800, 12000),
            },
          ),
          plantId: p.id,
        );
        gate.release.complete();
        expect(await pending, RefreshResult.updated);
        expect(gate.acquired!.lightMaximum, closeTo(11200 / .30, 1e-9));
        final c = (await repo.loadAcquisitionContext(p.id))!;
        expect(c.device.generationSequence, 1);
        expect(c.device.lastAutoSlot, 0);
        expect(c.previousReading!.origin, 'connection');
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );
  test(
    'Delete during delayed simulated read rejects candidate without recreating deleted device',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 11, 7)),
          repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 7)));
      await repo.initialize();
      final gate = ScaleGate(),
          scheduler = ReadingScheduler(repo, gate, clock: clock);
      final entered = gate.started = Completer<void>();
      gate.release = Completer<void>();
      try {
        final pending = scheduler.refreshAssigned('plant-1', gate);
        await entered.future;
        await repo.deletePlant('plant-1');
        gate.release!.complete();
        expect(await pending, RefreshResult.assignmentChanged);
        expect(await repo.loadPlants(), isEmpty);
        expect(await repo.loadDevices(), isEmpty);
        expect(
          await repo.database.rows('SELECT * FROM sensor_readings'),
          isEmpty,
        );
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );
  test(
    '30 percent formula covers broad and compliant ranges without shrinking original scale',
    () {
      for (final pair in [
        ('plant-1', const TargetRange(400, 850)),
        ('wide', const TargetRange(800, 12000)),
        ('broad', const TargetRange(0, 200000)),
        ('narrow', const TargetRange(199999, 200000)),
      ]) {
        final s = SensorScale.forMetric(
          SensorMetric.light,
          pair.$2,
          null,
          plantId: pair.$1,
        );
        expect(s.minimum, 0);
        expect(s.maximum.isFinite, isTrue);
        expect(
          (pair.$2.maximum - pair.$2.minimum) / s.maximum,
          lessThanOrEqualTo(.30 + 1e-14),
        );
        if (pair.$1 == 'plant-1') expect(s.maximum, 1500);
        if (pair.$1 == 'wide') expect(s.maximum, closeTo(11200 / .30, 1e-9));
        if (pair.$1 == 'broad') expect(s.maximum, closeTo(200000 / .30, 1e-9));
        for (final value in [0.0, 200000.0]) {
          expect(
            SensorScale.forMetric(
              SensorMetric.light,
              pair.$2,
              value,
              plantId: pair.$1,
            ).maximum,
            s.maximum,
          );
        }
        expect(
          PlantSimulationContext(
            plantId: pair.$1,
            lightRange: pair.$2,
          ).lightMaximum,
          math.min(200000, s.maximum),
        );
      }
    },
  );
}
