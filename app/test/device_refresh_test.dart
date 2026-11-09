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
import 'package:plant_companion/state/plant_store.dart';
import 'fixtures/foundation_fixtures.dart';
import 'reading_scheduler_test.dart' show ControlledTimers;

class ControlledRefreshGateway extends FakeSensorRepository {
  ControlledRefreshGateway() : super(delay: Duration.zero);
  bool failConnection = false, failAcquisition = false, emptyPacket = false;
  bool wrongDevice = false;
  int connections = 0, acquisitions = 0, active = 0, maxActive = 0;
  Completer<void>? connecting, acquiring;
  Completer<Device>? connection;
  Completer<SensorReading>? packet;
  void enter() {
    active++;
    if (active > maxActive) maxActive = active;
  }

  @override
  Future<Device> connect(Device device, {bool simulateFailure = false}) async {
    connections++;
    enter();
    connecting?.complete();
    try {
      if (failConnection) throw StateError('injected connection failure');
      if (connection != null) return await connection!.future;
      return wrongDevice
          ? const Device(id: 'wrong', name: 'wrong', isConnected: true)
          : device.withConnection(true);
    } finally {
      active--;
    }
  }

  @override
  Future<SensorReading> acquire(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) async {
    acquisitions++;
    enter();
    acquiring?.complete();
    try {
      if (failAcquisition) throw StateError('injected acquisition failure');
      if (packet != null) return await packet!.future;
      if (emptyPacket) return SensorReading(recordedAt: recordedAt);
      return await super.acquire(
        device,
        recordedAt,
        previousReading: previousReading,
        simulationMode: simulationMode,
        plantContext: plantContext,
      );
    } finally {
      active--;
    }
  }
}

void main() {
  late MutableClock clock;
  late SqlitePlantRepository repo;
  late ControlledRefreshGateway gateway;
  late ReadingScheduler scheduler;
  setUp(() async {
    clock = MutableClock(DateTime.utc(2026, 6, 20, 10));
    repo = memoryRepository(clock);
    await repo.initialize();
    gateway = ControlledRefreshGateway();
    scheduler = ReadingScheduler(repo, gateway, clock: clock);
  });
  tearDown(() async {
    scheduler.dispose();
    await repo.close();
  });
  Future<Device> device() async => (await repo.loadDevices()).single;
  Future<void> disconnect() => repo.setConnection('device-1', false);

  test(
    'connected manual refresh persists a real packet without consuming automatic slot',
    () async {
      final before = await device();
      final original = (await repo.loadHistory('plant-1')).single;
      clock.value = clock.now().add(const Duration(minutes: 61));
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updated,
      );
      final after = await device();
      expect((gateway.connections, gateway.acquisitions), (0, 1));
      expect(
        (after.id, after.createdAt, after.lastAutoSlot),
        (before.id, before.createdAt, 0),
      );
      final history = await repo.loadHistory('plant-1');
      expect(history.length, 2);
      expect(history.last.id, original.id);
      expect(history.first.origin, 'manual');
      expect(history.first.recordedAt, clock.now());
      await scheduler.processDue();
      await scheduler.processDue();
      expect((await device()).lastAutoSlot, 3);
      expect((await repo.loadHistory('plant-1')).length, 3);
    },
  );

  test(
    'reconnect persists connection, acknowledges overdue slots only with connection packet, keeps anchor',
    () async {
      await disconnect();
      final before = await device();
      clock.value = clock.now().add(const Duration(minutes: 61));
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updated,
      );
      final after = await device();
      expect((gateway.connections, gateway.acquisitions), (1, 1));
      expect(after.isConnected, isTrue);
      expect(after.revision, before.revision + 1);
      expect(
        (after.id, after.createdAt, after.lastAutoSlot),
        (before.id, before.createdAt, 3),
      );
      final history = await repo.loadHistory('plant-1');
      expect(history.length, 2);
      expect(history.first.origin, 'connection');
      expect(history.first.recordedAt, clock.now());
      expect(history.last.recordedAt, before.createdAt);
      await scheduler.processDue();
      expect((await repo.loadHistory('plant-1')).length, 2);
      clock.value = before.createdAt!.add(const Duration(minutes: 80));
      await scheduler.processDue();
      expect((await device()).lastAutoSlot, 4);
      expect((await repo.loadHistory('plant-1')).first.origin, 'automatic');
    },
  );

  test(
    'failed connection preserves disconnected state, old readings/time and schedule',
    () async {
      await disconnect();
      final before = await device();
      final history = await repo.loadHistory('plant-1');
      gateway.failConnection = true;
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.connectionFailed,
      );
      final after = await device();
      expect(
        (after.isConnected, after.revision, after.lastAutoSlot),
        (false, before.revision, before.lastAutoSlot),
      );
      expect(gateway.acquisitions, 0);
      expect((await repo.loadHistory('plant-1')).single.id, history.single.id);
      expect(
        (await repo.loadHistory('plant-1')).single.recordedAt,
        history.single.recordedAt,
      );
    },
  );

  for (final empty in [false, true]) {
    test(
      'connected after reconnect but ${empty ? 'empty' : 'failed'} acquisition preserves genuine sync/history',
      () async {
        await disconnect();
        gateway.failAcquisition = !empty;
        gateway.emptyPacket = empty;
        final original = (await repo.loadHistory('plant-1')).single;
        clock.value = clock.now().add(const Duration(hours: 2));
        expect(
          await scheduler.refreshAssigned('plant-1', gateway),
          RefreshResult.acquisitionFailed,
        );
        final after = await device();
        expect(after.isConnected, isTrue);
        expect(after.lastAutoSlot, 0);
        final history = await repo.loadHistory('plant-1');
        expect(history.length, 1);
        expect(
          (history.single.id, history.single.recordedAt),
          (original.id, original.recordedAt),
        );
      },
    );
  }

  test(
    'wrong gateway identity is rejected before any connected-state write',
    () async {
      await disconnect();
      final before = await device();
      gateway.wrongDevice = true;
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.connectionFailed,
      );
      expect((await device()).revision, before.revision);
      expect((await device()).isConnected, isFalse);
      expect(gateway.acquisitions, 0);
    },
  );

  test(
    'unassigned and missing plants never connect, create devices or acquire readings',
    () async {
      final original = (await repo.loadHistory('plant-1')).single;
      await repo.save(draft('Unassigned'), plantId: 'plant-1');
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.noDevice,
      );
      expect(
        await scheduler.refreshAssigned('missing', gateway),
        RefreshResult.noDevice,
      );
      expect((gateway.connections, gateway.acquisitions), (0, 0));
      expect((await repo.loadDevices()).length, 1);
      expect((await repo.loadHistory('plant-1')).single.id, original.id);
    },
  );

  for (final race in ['delete', 'unassign', 'reassign', 'revision']) {
    for (final phase in ['connect', 'acquire']) {
      test(
        '$race during pending $phase discards stale result and never writes to another owner',
        () async {
          await disconnect();
          final captured = await device();
          final start = Completer<void>();
          if (phase == 'connect') {
            gateway.connecting = start;
            gateway.connection = Completer<Device>();
          } else {
            gateway.acquiring = start;
            gateway.packet = Completer<SensorReading>();
          }
          final pending = scheduler.refreshAssigned('plant-1', gateway);
          await start.future;
          String? other;
          if (race == 'delete') {
            await repo.deletePlant('plant-1');
          } else if (race == 'revision') {
            await repo.setConnection(captured.id, false);
            if (phase == 'acquire') await repo.setConnection(captured.id, true);
          } else {
            await repo.save(draft('Released'), plantId: 'plant-1');
            if (race == 'reassign') {
              other = await repo.save(
                draft('New owner', deviceId: captured.id),
              );
            }
          }
          if (phase == 'connect') {
            gateway.connection!.complete(captured.withConnection(true));
          } else {
            gateway.packet!.complete(
              SensorReading(recordedAt: clock.now(), light: 777),
            );
          }
          expect(await pending, RefreshResult.assignmentChanged);
          if (race == 'delete') {
            expect(await repo.loadPlants(), isEmpty);
            expect(await repo.loadDevices(), isEmpty);
          } else {
            expect((await repo.loadHistory('plant-1')).length, 1);
            if (other != null) expect(await repo.loadHistory(other), isEmpty);
            if (phase == 'connect') {
              expect((await device()).isConnected, isFalse);
            }
          }
          await Future<void>.delayed(Duration.zero);
          expect(scheduler.pendingDeviceCount, 0);
        },
      );
    }
  }

  test(
    'concurrent due processing shares queue and does not duplicate overdue connection acknowledgement',
    () async {
      await disconnect();
      clock.value = clock.now().add(const Duration(minutes: 61));
      gateway.acquiring = Completer<void>();
      gateway.packet = Completer<SensorReading>();
      final pending = scheduler.refreshAssigned('plant-1', gateway);
      await gateway.acquiring!.future;
      final due = scheduler.processDue();
      gateway.packet!.complete(
        SensorReading(recordedAt: clock.now(), light: 600),
      );
      expect(await pending, RefreshResult.updated);
      await due;
      expect(gateway.acquisitions, 1);
      expect(gateway.maxActive, 1);
      expect((await repo.loadHistory('plant-1')).length, 2);
      expect((await device()).lastAutoSlot, 3);
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.pendingDeviceCount, 0);
    },
  );

  test(
    'store rejects duplicate refresh while reconnecting and publishes connected state before failed read',
    () async {
      await disconnect();
      gateway.connecting = Completer<void>();
      gateway.connection = Completer<Device>();
      gateway.failAcquisition = true;
      final store = PlantStore(
        persistence: repo,
        repository: gateway,
        clock: clock,
      );
      await store.initialized;
      try {
        final pending = store.refresh('plant-1');
        await gateway.connecting!.future;
        expect(store.isRefreshing('plant-1'), isTrue);
        expect(await store.refresh('plant-1'), RefreshResult.busy);
        gateway.connection!.complete((await device()).withConnection(true));
        expect(await pending, RefreshResult.acquisitionFailed);
        expect(gateway.connections, 1);
        expect(store.deviceFor(store.plants.single)!.isConnected, isTrue);
        expect(store.isRefreshing('plant-1'), isFalse);
        expect(
          store.plants.single.latestReading!.recordedAt,
          DateTime.utc(2026, 6, 20, 10),
        );
      } finally {
        store.dispose();
      }
    },
  );

  test(
    'real timer callback after reconnect stays at original C+20 boundary',
    () async {
      await disconnect();
      final timers = ControlledTimers(clock);
      scheduler.dispose();
      scheduler = ReadingScheduler(
        repo,
        gateway,
        clock: clock,
        createTimer: timers.create,
      );
      await scheduler.resume();
      expect(timers.activeCount, 0);
      clock.value = clock.now().add(const Duration(minutes: 13));
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.updated,
      );
      expect(timers.timers.last.deadline, DateTime.utc(2026, 6, 20, 10, 20));
      final rearmed = timers.nextScheduled = Completer<void>();
      timers.elapse(const Duration(minutes: 7));
      await rearmed.future;
      expect((await device()).lastAutoSlot, 1);
      expect((await repo.loadHistory('plant-1')).length, 3);
      expect(timers.timers.last.deadline, DateTime.utc(2026, 6, 20, 10, 40));
    },
  );

  test(
    'failed overdue connection acquisition retries via real timer without acknowledging a fabricated packet',
    () async {
      await disconnect();
      final timers = ControlledTimers(clock);
      scheduler.dispose();
      scheduler = ReadingScheduler(
        repo,
        gateway,
        clock: clock,
        createTimer: timers.create,
      );
      await scheduler.resume();
      clock.value = clock.now().add(const Duration(minutes: 61));
      gateway.failAcquisition = true;
      expect(
        await scheduler.refreshAssigned('plant-1', gateway),
        RefreshResult.acquisitionFailed,
      );
      expect((await device()).lastAutoSlot, 0);
      expect((await repo.loadHistory('plant-1')).length, 1);
      expect(
        timers.timers.last.deadline,
        clock.now().add(const Duration(seconds: 30)),
      );
      gateway.failAcquisition = false;
      final rearmed = timers.nextScheduled = Completer<void>();
      timers.elapse(const Duration(seconds: 30));
      await rearmed.future;
      expect((await device()).lastAutoSlot, 3);
      expect((await repo.loadHistory('plant-1')).length, 2);
      expect(timers.timers.last.deadline, DateTime.utc(2026, 6, 20, 11, 20));
    },
  );

  test(
    'renumbering another deleted device does not change immutable reconnect identity or anchor',
    () async {
      final id = await repo.save(draft('Second', createDevice: true));
      final target = (await repo.loadAssignedDevices())[id]!;
      await repo.setConnection(target.id, false);
      gateway.connecting = Completer<void>();
      gateway.connection = Completer<Device>();
      final pending = scheduler.refreshAssigned(id, gateway);
      await gateway.connecting!.future;
      await repo.deletePlant('plant-1');
      gateway.connection!.complete(target.withConnection(true));
      expect(await pending, RefreshResult.updated);
      final remaining = await device();
      expect(
        (remaining.id, remaining.createdAt, remaining.name),
        (target.id, target.createdAt, 'ESP32-Sim01'),
      );
    },
  );

  test(
    'guarded reconnect rejects wrong owner and stale connection revisions',
    () async {
      await disconnect();
      final before = await device();
      expect(await repo.reconnectAssigned('wrong-owner', before), isNull);
      final connected = await repo.reconnectAssigned('plant-1', before);
      expect(connected!.isConnected, isTrue);
      expect(await repo.reconnectAssigned('plant-1', before), isNull);
      expect((await device()).revision, connected.revision);
      expect((await repo.loadHistory('plant-1')).length, 1);
    },
  );

  test(
    'file-backed restart preserves reconnect state, original anchor/slots and retained history',
    () async {
      final directory = await Directory.systemTemp.createTemp('phase_c_');
      SqlitePlantRepository open() => SqlitePlantRepository(
        AppDatabase(NativeDatabase(File('${directory.path}/plants.sqlite'))),
        clock: clock,
      );
      var durable = open();
      try {
        await durable.initialize();
        await durable.setConnection('device-1', false);
        clock.value = clock.now().add(const Duration(minutes: 61));
        final commands = ReadingScheduler(durable, gateway, clock: clock);
        expect(
          await commands.refreshAssigned('plant-1', gateway),
          RefreshResult.updated,
        );
        commands.dispose();
        final before = (await durable.loadDevices()).single;
        final history = await durable.loadHistory('plant-1');
        await durable.close();
        durable = open();
        await durable.initialize();
        final after = (await durable.loadDevices()).single;
        expect(
          (
            after.id,
            after.createdAt,
            after.lastAutoSlot,
            after.isConnected,
            after.revision,
          ),
          (
            before.id,
            before.createdAt,
            before.lastAutoSlot,
            true,
            before.revision,
          ),
        );
        expect(
          (await durable.loadHistory(
            'plant-1',
          )).map((r) => (r.id, r.recordedAt, r.light)),
          history.map((r) => (r.id, r.recordedAt, r.light)),
        );
      } finally {
        await durable.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
