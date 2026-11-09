import 'fixtures/simulation_context.dart';
import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/services/reading_scheduler.dart';
import 'package:plant_companion/services/simulated_environment.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'fixtures/foundation_fixtures.dart';
import 'manual_refresh_simulation_test.dart' show manualValues;

class ManualModeGateway extends FakeSensorRepository {
  ManualModeGateway() : super(delay: Duration.zero);
  final modes = <SimulationMode>[];
  bool fail = false;
  Completer<void>? started, release;
  @override
  Future<SensorReading> acquire(
    Device d,
    DateTime at, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) async {
    modes.add(simulationMode);
    if (fail) throw StateError('injected acquisition failure');
    final candidate = await super.acquire(
      d,
      at,
      previousReading: previousReading,
      simulationMode: simulationMode,
      plantContext: plantContext,
    );
    started?.complete();
    if (release != null) await release!.future;
    return candidate;
  }
}

void main() {
  late MutableClock clock;
  late SqlitePlantRepository repo;
  late ManualModeGateway gateway;
  late ReadingScheduler scheduler;
  setUp(() async {
    clock = MutableClock(DateTime.utc(2026, 11, 7, 12));
    repo = memoryRepository(clock);
    await repo.initialize();
    gateway = ManualModeGateway();
    scheduler = ReadingScheduler(repo, gateway, clock: clock);
  });
  tearDown(() async {
    scheduler.dispose();
    await repo.close();
  });
  Future<DeviceReadingContext> context([String id = 'plant-1']) async =>
      (await repo.loadAcquisitionContext(id))!;
  test(
    'manual and reconnect use weighted conditions but keep their genuine origin and anchors',
    () async {
      final original = await context();
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updated,
      );
      expect(gateway.modes.last, SimulationMode.manualConditionDriven);
      expect((await context()).previousReading!.origin, 'manual');
      expect(manualValues((await context()).previousReading!), [
        68.21,
        27.2698,
        40.39,
        635.11,
      ]);
      await repo.setConnection(original.device.id, false);
      final disconnected = await context();
      clock.value = clock.now().add(const Duration(seconds: 1));
      final expected = SimulatedEnvironment.sample(
        disconnected.device,
        clock.now(),
        simulationMode: SimulationMode.manualConditionDriven,
        plantContext: simulationContext,
      );
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updated,
      );
      final after = await context();
      expect(gateway.modes, [
        SimulationMode.manualConditionDriven,
        SimulationMode.manualConditionDriven,
      ]);
      expect(manualValues(after.previousReading!), manualValues(expected));
      expect(after.previousReading!.origin, 'connection');
      expect(after.previousReading!.sourceDeviceId, original.device.id);
      expect(after.device.createdAt, original.device.createdAt);
      expect(after.device.lastAutoSlot, 0);
      expect((await repo.loadHistory('plant-1')).length, 3);
    },
  );
  test(
    'automatic follows gradual v1 from the last real manual packet, not origin-derived strategy',
    () async {
      await scheduler.refreshAssigned('plant-1', gateway);
      final before = await context();
      clock.value = clock.now().add(const Duration(minutes: 20));
      final expected = SimulatedEnvironment.sample(
        before.device,
        clock.now(),
        previousReading: before.previousReading,
        plantContext: simulationContext,
      );
      await scheduler.processDue();
      final after = await context();
      expect(gateway.modes, [
        SimulationMode.manualConditionDriven,
        SimulationMode.environment,
      ]);
      expect(manualValues(after.previousReading!), manualValues(expected));
      expect(after.previousReading!.origin, 'automatic');
      expect(after.device.lastAutoSlot, 1);
      expect(after.device.createdAt, before.device.createdAt);
      // Explicit policy and packet origin remain orthogonal in the gateway path.
      expect(
        await scheduler.refresh(
          'plant-1',
          origin: 'manual',
          simulationMode: SimulationMode.environment,
        ),
        isTrue,
      );
      expect(gateway.modes.last, SimulationMode.environment);
      expect((await context()).previousReading!.origin, 'manual');
    },
  );
  test('post-save initial connection retains environment strategy', () async {
    final store = PlantStore(
      persistence: repo,
      repository: gateway,
      clock: clock,
    );
    try {
      await store.initialized;
      final result = await store.saveForm(
        draft('New device', createDevice: true),
        operationId: 'manual-test-initial',
      );
      final id = result.plantId!;
      final after = await context(id);
      expect(gateway.modes, [SimulationMode.environment]);
      expect(after.previousReading!.origin, 'connection');
      expect(after.device.generationSequence, 1);
      expect(after.previousReading!.soilMoisture, inInclusiveRange(32.5, 67.5));
      expect(after.previousReading!.light, inInclusiveRange(30, 1670));
    } finally {
      store.dispose();
    }
  });
  test(
    'saved ideal edit changes conditional intervals and preserves prior packets',
    () async {
      final before = await context();
      final old = await repo.database.rows('SELECT * FROM sensor_readings');
      final expected = SimulatedEnvironment.sample(
        before.device,
        clock.now(),
        simulationMode: SimulationMode.manualConditionDriven,
        plantContext: simulationContext,
      );
      await repo.save(
        PlantFormDraft(
          nickname: 'Edited',
          speciesName: 'Other species',
          avatar: PlantAvatarId.snakePlant,
          deviceId: before.device.id,
          ranges: const {
            SensorMetric.soilMoisture: TargetRange(0, 100),
            SensorMetric.light: TargetRange(0, 200000),
            SensorMetric.temperature: TargetRange(-40, 48.888888888888886),
            SensorMetric.humidity: TargetRange(0, 100),
          },
        ),
        plantId: 'plant-1',
      );
      expect(await repo.database.rows('SELECT * FROM sensor_readings'), old);
      final saved = await context();
      final revised = SimulatedEnvironment.sample(
        saved.device,
        clock.now(),
        simulationMode: SimulationMode.manualConditionDriven,
        plantContext: simulationFor(saved),
      );
      // All four care intervals were intentionally changed. The new policy
      // coordinates all four values; the full-domain profile has only Happy.
      for (final m in SensorMetric.values) {
        expect(
          saved.idealRanges[m]!.statusFor(revised.valueFor(m)),
          ReadingStatus.inRange,
        );
      }
      expect(revised.soilMoisture, isNot(expected.soilMoisture));
      expect(revised.light, isNot(expected.light));
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updated,
      );
      expect(
        manualValues((await context()).previousReading!),
        manualValues(revised),
      );
    },
  );
  test(
    'failed acquisition preserves timestamp/history/sequence and retry candidate',
    () async {
      final before = await context();
      gateway.fail = true;
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.acquisitionFailed,
      );
      final failed = await context();
      expect(
        failed.device.generationSequence,
        before.device.generationSequence,
      );
      expect(failed.previousReading!.id, before.previousReading!.id);
      expect(
        failed.previousReading!.recordedAt,
        before.previousReading!.recordedAt,
      );
      gateway.fail = false;
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updated,
      );
      expect(
        manualValues((await context()).previousReading!),
        manualValues(
          SimulatedEnvironment.sample(
            before.device,
            clock.now(),
            simulationMode: SimulationMode.manualConditionDriven,
            plantContext: simulationContext,
          ),
        ),
      );
    },
  );
  for (final race in ['delete', 'reassign']) {
    test('conditional candidate is rejected after in-flight $race', () async {
      final started = gateway.started = Completer<void>();
      gateway.release = Completer<void>();
      final pending = scheduler.refreshAssigned('plant-1', gateway);
      await started.future;
      String? owner;
      if (race == 'delete') {
        await repo.deletePlant('plant-1');
      } else {
        await repo.save(draft('Unassigned'), plantId: 'plant-1');
        owner = await repo.save(draft('Next owner', deviceId: 'device-1'));
      }
      gateway.release!.complete();
      expect(await pending, RefreshResult.assignmentChanged);
      expect(gateway.modes.single, SimulationMode.manualConditionDriven);
      expect(scheduler.pendingDeviceCount, 0);
      if (owner != null) {
        expect((await context(owner)).device.generationSequence, 0);
        expect(await repo.loadHistory(owner), isEmpty);
        expect((await repo.loadHistory('plant-1')).length, 1);
      } else {
        expect(await repo.loadPlants(), isEmpty);
        expect(await repo.loadDevices(), isEmpty);
      }
    });
  }
  test(
    'file-backed restart and real device renumbering preserve next manual generation',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'manual-refresh-reopen-',
      );
      final file = File('${dir.path}/plants.sqlite');
      var disk = SqlitePlantRepository(
        AppDatabase(NativeDatabase(file)),
        clock: clock,
      );
      try {
        await disk.initialize();
        final id = await disk.save(draft('Second', createDevice: true));
        await connectFixtureDevice(disk, id);
        var run = ReadingScheduler(disk, gateway, clock: clock);
        await run.refreshAssigned(id, gateway);
        run.dispose();
        final old = (await disk.loadAcquisitionContext(id))!;
        await disk.deletePlant('plant-1');
        final renamed = (await disk.loadAcquisitionContext(id))!;
        expect(old.device.name, 'ESP32-Sim02');
        expect(renamed.device.name, 'ESP32-Sim01');
        expect(renamed.device.id, old.device.id);
        expect(
          renamed.device.generationSequence,
          old.device.generationSequence,
        );
        final packets = await disk.database.rows(
          'SELECT * FROM sensor_readings',
        );
        clock.value = clock.now().add(const Duration(seconds: 1));
        final expected = SimulatedEnvironment.sample(
          old.device,
          clock.now(),
          simulationMode: SimulationMode.manualConditionDriven,
          plantContext: simulationFor(old),
        );
        await disk.close();
        disk = SqlitePlantRepository(
          AppDatabase(NativeDatabase(file)),
          clock: clock,
        );
        await disk.initialize();
        expect(
          await disk.database.rows('SELECT * FROM sensor_readings'),
          packets,
        );
        run = ReadingScheduler(disk, gateway, clock: clock);
        expect(await run.refreshAssigned(id, gateway), RefreshResult.updated);
        run.dispose();
        final after = (await disk.loadAcquisitionContext(id))!;
        expect(manualValues(after.previousReading!), manualValues(expected));
        expect(
          after.device.generationSequence,
          old.device.generationSequence + 1,
        );
        expect(after.device.createdAt, old.device.createdAt);
      } finally {
        await disk.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
