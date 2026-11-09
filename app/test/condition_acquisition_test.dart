import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/condition_driven_simulation.dart';
import 'package:plant_companion/services/reading_scheduler.dart';
import 'fixtures/foundation_fixtures.dart';
import 'fixtures/form_actions.dart';
import 'condition_driven_simulation_test.dart'
    show verifyCondition, conditionDevice;
import 'plant_form_widget_test.dart' as ui;
import 'scale_context_test.dart' show ScaleGate;

void main() {
  test(
    'all committed ideal ranges arrive in one immutable acquisition snapshot',
    () async {
      final repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 7)));
      try {
        await repo.initialize();
        final p = (await repo.loadPlants()).single,
            c = (await repo.loadAcquisitionContext(p.id))!;
        for (final m in SensorMetric.values) {
          expect(c.idealRanges[m]!.minimum, p.profile.rangeFor(m).minimum);
          expect(c.idealRanges[m]!.maximum, p.profile.rangeFor(m).maximum);
        }
        expect(
          () =>
              c.idealRanges[SensorMetric.humidity] = const TargetRange(0, 100),
          throwsUnsupportedError,
        );
        expect(
          c.withDevice(c.device).idealRanges.keys.toSet(),
          SensorMetric.values.toSet(),
        );
      } finally {
        await repo.close();
      }
    },
  );
  test(
    'moisture Edit during delayed conditional acquisition rejects stale profile with no sequence/slot/history change',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 11, 7)),
          repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 7)));
      await repo.initialize();
      final gate = ScaleGate(),
          scheduler = ReadingScheduler(repo, gate, clock: clock);
      try {
        final old = (await repo.loadAcquisitionContext('plant-1'))!,
            rows = await repo.database.rows('SELECT * FROM sensor_readings');
        final entered = gate.started = Completer<void>();
        gate.release = Completer<void>();
        final pending = scheduler.refreshAssigned('plant-1', gate);
        await entered.future;
        final p = (await repo.loadPlants()).single;
        await repo.save(
          PlantFormDraft(
            nickname: p.nickname,
            speciesName: p.speciesName,
            avatar: p.avatar,
            deviceId: p.deviceId,
            ranges: {
              ...p.profile.ranges,
              SensorMetric.soilMoisture: const TargetRange(10, 20),
            },
          ),
          plantId: p.id,
        );
        gate.release!.complete();
        expect(await pending, RefreshResult.acquisitionFailed);
        expect(await repo.database.rows('SELECT * FROM sensor_readings'), rows);
        final after = (await repo.loadAcquisitionContext(p.id))!;
        expect(after.device.generationSequence, old.device.generationSequence);
        expect(after.device.lastAutoSlot, old.device.lastAutoSlot);
        gate.release = null;
        expect(
          await scheduler.refreshAssigned(p.id, gate),
          RefreshResult.updated,
        );
        final context = gate.contexts.last;
        expect(context.idealRanges![SensorMetric.soilMoisture]!.maximum, 20);
        final expected = ConditionDrivenSimulation(
          context,
        ).sample(after.device, clock.now());
        verifyCondition(context, expected);
        final stored = (await repo.loadAcquisitionContext(
          p.id,
        ))!.previousReading!;
        for (final m in SensorMetric.values) {
          expect(stored.valueFor(m), expected.reading.valueFor(m));
        }
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );
  test(
    'incompatible representable ideals fail cleanly without consuming durable sequence or historic packet',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 11, 7)),
          repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 7)));
      await repo.initialize();
      final gate = ScaleGate(),
          scheduler = ReadingScheduler(repo, gate, clock: clock);
      try {
        final p = (await repo.loadPlants()).single;
        await repo.save(
          PlantFormDraft(
            nickname: p.nickname,
            speciesName: p.speciesName,
            avatar: p.avatar,
            deviceId: p.deviceId,
            ranges: {
              ...p.profile.ranges,
              SensorMetric.soilMoisture: const TargetRange(.001, .002),
              SensorMetric.humidity: const TargetRange(.001, .002),
            },
          ),
          plantId: p.id,
        );
        final old = (await repo.loadAcquisitionContext(p.id))!,
            rows = await repo.database.rows('SELECT * FROM sensor_readings');
        expect(
          await scheduler.refreshAssigned(p.id, gate),
          RefreshResult.simulationUnavailable,
        );
        expect(await repo.database.rows('SELECT * FROM sensor_readings'), rows);
        final after = (await repo.loadAcquisitionContext(p.id))!;
        expect(after.device.generationSequence, old.device.generationSequence);
        expect(after.device.createdAt, old.device.createdAt);
        expect(after.device.lastAutoSlot, old.device.lastAutoSlot);
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );
  test(
    'concurrent manual requests serialize next deterministic conditional generations exactly once',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 11, 7)),
          repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 7)));
      await repo.initialize();
      final gate = ScaleGate(),
          scheduler = ReadingScheduler(repo, gate, clock: clock);
      try {
        final c = (await repo.loadAcquisitionContext('plant-1'))!;
        final results = await Future.wait([
          scheduler.refreshAssigned('plant-1', gate),
          scheduler.refreshAssigned('plant-1', gate),
        ]);
        expect(results, [RefreshResult.updated, RefreshResult.updated]);
        final after = (await repo.loadAcquisitionContext('plant-1'))!;
        expect(
          after.device.generationSequence,
          c.device.generationSequence + 2,
        );
        final history = await repo.loadHistory('plant-1');
        expect(history.length, 3);
        for (var i = 0; i < 2; i++) {
          final context = gate.contexts[i];
          final expected = ConditionDrivenSimulation(context).sample(
            conditionDevice(c.device.generationSequence + i, id: c.device.id),
            clock.now(),
          );
          for (final m in SensorMetric.values) {
            expect(history[1 - i].valueFor(m), expected.reading.valueFor(m));
          }
        }
        expect(after.device.lastAutoSlot, c.device.lastAutoSlot);
        expect(after.device.createdAt, c.device.createdAt);
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );
  testWidgets(
    'Details exposes actionable correction error then normal existing Edit/Refresh recovers',
    (tester) async {
      final f = await ui.mountD(tester);
      await tester.runAsync(() async {
        final p = f.store.plants.single;
        await f.repo.save(
          PlantFormDraft(
            nickname: p.nickname,
            speciesName: p.speciesName,
            avatar: p.avatar,
            deviceId: p.deviceId,
            ranges: {
              ...p.profile.ranges,
              SensorMetric.soilMoisture: const TargetRange(.001, .002),
              SensorMetric.humidity: const TargetRange(.001, .002),
            },
          ),
          plantId: p.id,
        );
        await f.store.reload();
      });
      final old = f.store.plants.single.latestReading!.id;
      await ui.dTap(tester, find.byKey(const Key('details-plant-1')));
      await ui.dTap(tester, find.byKey(const Key('refresh-button')));
      expect(find.text(NoFeasibleManualCondition.message), findsOneWidget);
      expect(f.store.plants.single.latestReading!.id, old);
      await ui.dTap(tester, find.byKey(const Key('details-edit-plant-1')));
      await fillCareRanges(tester);
      await ui.dTap(tester, find.byKey(const Key('save-changes-button')));
      await ui.dTap(tester, find.byKey(const Key('refresh-button')));
      expect(find.text(NoFeasibleManualCondition.message), findsNothing);
      expect(f.store.plants.single.latestReading!.id, isNot(old));
      await f.close(tester);
    },
  );
}
