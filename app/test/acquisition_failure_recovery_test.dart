import 'fixtures/simulation_context.dart';
import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/services/reading_scheduler.dart';
import 'package:plant_companion/services/simulated_environment.dart';
import 'fixtures/foundation_fixtures.dart';
import 'reading_scheduler_test.dart' show ControlledTimers;
import 'environment_simulation_test.dart' show values;

class FaultRepository extends SqlitePlantRepository {
  FaultRepository(super.database, {required super.clock});
  bool loseAck = false, failAssignments = false;
  Completer<void>? lookupStarted, releaseLookup;
  @override
  Future<Map<String, Device>> loadAssignedDevices() async {
    if (failAssignments) throw StateError('injected rearm failure');
    final result = await super.loadAssignedDevices();
    if (lookupStarted != null) {
      final started = lookupStarted!;
      lookupStarted = null;
      started.complete();
      await releaseLookup!.future;
    }
    return result;
  }

  @override
  Future<bool> commitReading(
    String id,
    Device d,
    SensorReading r, {
    String origin = 'manual',
    int? autoSlot,
    int? expectedProfileRevision,
  }) async {
    final result = await super.commitReading(
      id,
      d,
      r,
      origin: origin,
      autoSlot: autoSlot,
      expectedProfileRevision: expectedProfileRevision,
    );
    if (loseAck && result) throw StateError('lost commit acknowledgement');
    return result;
  }
}

class BlockFirst extends FakeSensorRepository {
  BlockFirst() : super(delay: Duration.zero);
  final entered = Completer<void>(),
      release = Completer<void>(),
      other = Completer<void>();
  @override
  Future<SensorReading> acquire(
    Device d,
    DateTime at, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) async {
    if (d.id == 'device-1') {
      entered.complete();
      await release.future;
    } else if (!other.isCompleted) {
      other.complete();
    }
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
  late MutableClock clock;
  late FaultRepository repo;
  late FakeSensorRepository gateway;
  late ReadingScheduler scheduler;
  setUp(() async {
    clock = MutableClock(DateTime.utc(2026, 11, 7, 12));
    repo = FaultRepository(AppDatabase(NativeDatabase.memory()), clock: clock);
    await repo.initialize();
    gateway = FakeSensorRepository(delay: Duration.zero);
    scheduler = ReadingScheduler(repo, gateway, clock: clock);
  });
  tearDown(() async {
    scheduler.dispose();
    await repo.close();
  });
  Future<DeviceReadingContext> context([String id = 'plant-1']) async =>
      (await repo.loadAcquisitionContext(id))!;
  Future<String> add(String name) async {
    final id = await repo.save(draft(name, createDevice: true));
    await connectFixtureDevice(repo, id);
    return id;
  }

  test(
    'lost automatic acknowledgement consumes one overdue slot exactly once',
    () async {
      repo.loseAck = true;
      clock.value = clock.now().add(const Duration(minutes: 75));
      await scheduler.processDue();
      await scheduler.processDue();
      final saved = await context();
      expect(saved.device.generationSequence, 1);
      expect(saved.device.lastAutoSlot, 3);
      expect((await repo.loadHistory('plant-1')).length, 2);
      expect(
        (await repo.database.rows(
          "SELECT auto_slot FROM sensor_readings WHERE origin='automatic'",
        )).single['auto_slot'],
        3,
      );
    },
  );
  test(
    'rollback does not consume sequence; retry reproduces exact candidate',
    () async {
      final before = await context();
      final expected = SimulatedEnvironment.sample(
        before.device,
        clock.now(),
        previousReading: before.previousReading,
        simulationMode: SimulationMode.manualConditionDriven,
        plantContext: simulationContext,
      );
      await repo.database.customStatement(
        "CREATE TRIGGER fail_packet BEFORE INSERT ON sensor_readings BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.acquisitionFailed,
      );
      expect(
        (await context()).device.generationSequence,
        before.device.generationSequence,
      );
      expect((await repo.loadHistory('plant-1')).length, 1);
      await repo.database.customStatement('DROP TRIGGER fail_packet');
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updated,
      );
      expect(values((await context()).previousReading!), values(expected));
      expect(
        (await context()).device.generationSequence,
        before.device.generationSequence + 1,
      );
    },
  );
  test(
    'lost commit acknowledgement reconciles exactly one durable packet',
    () async {
      repo.loseAck = true;
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updated,
      );
      expect((await repo.loadHistory('plant-1')).length, 2);
      expect((await context()).device.generationSequence, 1);
      expect(scheduler.pendingDeviceCount, 0);
    },
  );
  test(
    'publication failure reports saved packet and never reacquires',
    () async {
      var publications = 0;
      scheduler.dispose();
      scheduler = ReadingScheduler(
        repo,
        gateway,
        clock: clock,
        onChanged: () async {
          publications++;
          throw StateError('snapshot unavailable');
        },
      );
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updatedPublicationFailed,
      );
      expect(publications, 2);
      expect((await context()).device.generationSequence, 1);
      expect((await repo.loadHistory('plant-1')).length, 2);
    },
  );
  test(
    'rearm read failure retries on timer and preserves committed packet/anchor',
    () async {
      final timers = ControlledTimers(clock), before = await context();
      scheduler.dispose();
      scheduler = ReadingScheduler(
        repo,
        gateway,
        clock: clock,
        createTimer: timers.create,
      );
      await scheduler.resume();
      repo.failAssignments = true;
      expect(
        await scheduler.refreshAssigned(
          'plant-1',
          gateway,
          expectedDevice: before.device,
        ),
        RefreshResult.updatedSchedulerFailed,
      );
      expect((await context()).device.generationSequence, 1);
      expect(
        timers.timers.last.deadline,
        clock.now().add(const Duration(seconds: 30)),
      );
      repo.failAssignments = false;
      final rearmed = timers.nextScheduled = Completer<void>();
      timers.elapse(const Duration(seconds: 30));
      await rearmed.future;
      expect(
        timers.timers.last.deadline,
        before.device.createdAt!.add(const Duration(minutes: 20)),
      );
      expect((await repo.loadHistory('plant-1')).length, 2);
    },
  );
  test('pause during asynchronous rearm cannot resurrect timer', () async {
    final timers = ControlledTimers(clock);
    scheduler.dispose();
    scheduler = ReadingScheduler(
      repo,
      gateway,
      clock: clock,
      createTimer: timers.create,
    );
    await scheduler.resume();
    final started = repo.lookupStarted = Completer<void>();
    repo.releaseLookup = Completer<void>();
    final pending = scheduler.assignmentsChanged();
    await started.future;
    scheduler.pause();
    repo.releaseLookup!.complete();
    await pending;
    expect(timers.activeCount, 0);
    await scheduler.resume();
    expect(timers.activeCount, 1);
  });
  test('slow first device does not block other due devices', () async {
    final second = await add('second'), third = await add('third');
    final g = BlockFirst();
    final otherCommitted = Completer<void>();
    scheduler.dispose();
    scheduler = ReadingScheduler(
      repo,
      g,
      clock: clock,
      onChanged: () async {
        if ((await context(third)).device.lastAutoSlot == 1 &&
            !otherCommitted.isCompleted) {
          otherCommitted.complete();
        }
      },
    );
    clock.value = clock.now().add(const Duration(minutes: 20));
    final due = scheduler.processDue();
    await g.entered.future;
    await g.other.future;
    await otherCommitted.future.timeout(const Duration(seconds: 5));
    expect((await context(second)).device.lastAutoSlot, 1);
    expect((await context()).device.lastAutoSlot, 0);
    g.release.complete();
    await due;
    expect(
      (await repo.loadDevices()).map((d) => d.lastAutoSlot),
      everyElement(1),
    );
    expect(scheduler.pendingDeviceCount, 0);
  });
  test('100 independent devices share no sequence and catch up once', () async {
    for (var i = 1; i < 100; i++) {
      await add('device $i');
    }
    final anchors = {
      for (final d in await repo.loadDevices()) d.id: d.createdAt,
    };
    clock.value = clock.now().add(const Duration(minutes: 75));
    await Future.wait([scheduler.processDue(), scheduler.processDue()]);
    final devices = await repo.loadDevices();
    expect(devices.length, 100);
    expect(devices.map((d) => d.generationSequence), everyElement(1));
    expect(devices.map((d) => d.lastAutoSlot), everyElement(3));
    expect(devices.every((d) => d.createdAt == anchors[d.id]), isTrue);
    final packets = await repo.database.rows(
      'SELECT * FROM sensor_readings WHERE origin=\'automatic\'',
    );
    expect(packets.length, 100);
    expect(
      packets.map((r) => r['soil_moisture']).toSet().length,
      greaterThan(80),
    );
    expect(scheduler.pendingDeviceCount, 0);
  });
  test(
    'source context follows commit order despite backward clock and reassignment',
    () async {
      await scheduler.refresh('plant-1');
      clock.value = clock.now().subtract(const Duration(hours: 1));
      await scheduler.refresh('plant-1');
      final last = (await context()).previousReading!;
      expect(last.recordedAt, clock.now());
      final original = (await context()).device;
      await repo.save(draft('Florence unassigned'), plantId: 'plant-1');
      final nextOwner = await repo.save(
        draft('next owner', deviceId: original.id),
      );
      expect((await context(nextOwner)).previousReading!.id, last.id);
      expect(
        (await context(nextOwner)).device.generationSequence,
        original.generationSequence,
      );
      final expected = SimulatedEnvironment.sample(
        (await context(nextOwner)).device,
        clock.now(),
        previousReading: last,
        simulationMode: SimulationMode.manualConditionDriven,
        plantContext: simulationFor(await context(nextOwner)),
      );
      expect(
        await scheduler.refreshAssigned(nextOwner, gateway),
        RefreshResult.updated,
      );
      expect(
        values((await context(nextOwner)).previousReading!),
        values(expected),
      );
      expect((await repo.loadHistory('plant-1')).length, 3);
    },
  );
  test(
    'source lookup is indexed and no-device lookup never fabricates packet',
    () async {
      final id = await repo.save(draft('no device'));
      expect(await repo.loadAcquisitionContext(id), isNull);
      expect(
        await scheduler.refreshAssigned(id, gateway),
        RefreshResult.noDevice,
      );
      expect(await repo.loadHistory(id), isEmpty);
      final plan = await repo.database.rows(
        'EXPLAIN QUERY PLAN SELECT rowid FROM sensor_readings WHERE source_device_id=? ORDER BY rowid DESC LIMIT 1',
        ['device-1'],
      );
      expect(
        plan.map((r) => r['detail']).join(' '),
        contains('reading_by_device'),
      );
    },
  );
  test(
    'v2 reopen adds source index without reseeding or losing deterministic continuation',
    () async {
      final dir = await Directory.systemTemp.createTemp('plant-e-reopen-');
      final file = File('${dir.path}/test.sqlite');
      var disk = SqlitePlantRepository(
        AppDatabase(NativeDatabase(file)),
        clock: clock,
      );
      try {
        await disk.initialize();
        final run = ReadingScheduler(disk, gateway, clock: clock);
        await run.refresh('plant-1');
        run.dispose();
        final before = (await disk.loadAcquisitionContext('plant-1'))!;
        final expected = SimulatedEnvironment.sample(
          before.device,
          clock.now(),
          previousReading: before.previousReading,
          simulationMode: SimulationMode.manualConditionDriven,
          plantContext: simulationContext,
        );
        final oldPackets = await disk.database.rows(
          'SELECT * FROM sensor_readings',
        );
        await disk.database.customStatement('DROP INDEX reading_by_device');
        await disk.close();
        disk = SqlitePlantRepository(
          AppDatabase(NativeDatabase(file)),
          clock: clock,
        );
        await disk.initialize();
        expect(
          await disk.database.rows('SELECT * FROM sensor_readings'),
          oldPackets,
        );
        expect(
          (await disk.loadAcquisitionContext(
            'plant-1',
          ))!.device.generationSequence,
          1,
        );
        final run2 = ReadingScheduler(disk, gateway, clock: clock);
        await run2.refresh('plant-1');
        run2.dispose();
        expect(
          values(
            (await disk.loadAcquisitionContext('plant-1'))!.previousReading!,
          ),
          values(expected),
        );
      } finally {
        await disk.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
