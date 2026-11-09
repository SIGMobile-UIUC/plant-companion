import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/services/reading_scheduler.dart';
import 'package:plant_companion/services/sensor_gateway.dart';
import 'fixtures/foundation_fixtures.dart';

class DelayedGateway implements SensorGateway {
  final started = Completer<void>();
  final packet = Completer<SensorReading>();
  @override
  Future<SensorReading> acquire(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) {
    started.complete();
    return packet.future;
  }
}

class FailingFirstDevice extends FakeSensorRepository {
  FailingFirstDevice() : super(delay: Duration.zero);
  @override
  Future<SensorReading> acquire(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) {
    if (device.id == 'device-1') {
      throw StateError('Injected acquisition failure');
    }
    return super.acquire(
      device,
      recordedAt,
      previousReading: previousReading,
      simulationMode: simulationMode,
      plantContext: plantContext,
    );
  }
}

class ControlledTimer implements Timer {
  ControlledTimer(this.deadline, this.callback);
  final DateTime deadline;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    callback();
  }
}

class ControlledTimers {
  ControlledTimers(this.clock);
  final MutableClock clock;
  final timers = <ControlledTimer>[];
  Completer<void>? nextScheduled;
  Timer create(Duration delay, void Function() callback) {
    final timer = ControlledTimer(clock.now().add(delay), callback);
    timers.add(timer);
    nextScheduled?.complete();
    nextScheduled = null;
    return timer;
  }

  void elapse(Duration duration) {
    clock.value = clock.now().add(duration);
    for (final timer in timers.toList()) {
      if (!timer.deadline.isAfter(clock.now())) timer.fire();
    }
  }

  int get activeCount => timers.where((timer) => timer.isActive).length;
}

class QueuedGateway implements SensorGateway {
  final started = List.generate(2, (_) => Completer<void>());
  final packets = List.generate(2, (_) => Completer<SensorReading>());
  int calls = 0;
  @override
  Future<SensorReading> acquire(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) {
    final index = calls++;
    started[index].complete();
    return packets[index].future;
  }
}

void main() {
  test(
    'real timer callback acquires at C+20 and pause/resume coalesces missed slots',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 6, 20, 10));
      final repo = memoryRepository(clock);
      await repo.initialize();
      final timers = ControlledTimers(clock);
      final scheduler = ReadingScheduler(
        repo,
        FakeSensorRepository(delay: Duration.zero),
        clock: clock,
        createTimer: timers.create,
      );
      try {
        await scheduler.resume();
        expect(timers.activeCount, 1);
        timers.elapse(const Duration(minutes: 13));
        await scheduler.refresh('plant-1');
        timers.elapse(const Duration(minutes: 6, seconds: 59));
        expect((await repo.loadHistory('plant-1')).length, 2);
        final rearmed = timers.nextScheduled = Completer<void>();
        timers.elapse(const Duration(seconds: 1));
        await rearmed.future;
        expect((await repo.loadDevices()).single.lastAutoSlot, 1);
        expect((await repo.loadHistory('plant-1')).length, 3);
        expect(
          (await repo.loadHistory('plant-1')).first.recordedAt,
          clock.now(),
        );
        expect(timers.activeCount, 1);
        scheduler.pause();
        timers.elapse(const Duration(minutes: 40));
        expect((await repo.loadHistory('plant-1')).length, 3);
        await scheduler.resume();
        expect((await repo.loadDevices()).single.lastAutoSlot, 3);
        expect((await repo.loadHistory('plant-1')).length, 4);
        scheduler.dispose();
        expect(timers.activeCount, 0);
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );

  test(
    'queue survives a failed predecessor and releases the final tail',
    () async {
      final clock = MutableClock(DateTime.utc(2026));
      final repo = memoryRepository(clock);
      await repo.initialize();
      final gateway = QueuedGateway();
      final scheduler = ReadingScheduler(repo, gateway, clock: clock);
      try {
        final first = scheduler.refresh('plant-1');
        final failure = expectLater(first, throwsStateError);
        await gateway.started[0].future;
        final second = scheduler.refresh('plant-1');
        // Wait for the second request's assignment lookup and enqueue.
        await repo.loadAssignedDevices();
        expect(gateway.calls, 1);
        expect(scheduler.pendingDeviceCount, 1);
        gateway.packets[0].completeError(StateError('Injected failure'));
        await failure;
        await gateway.started[1].future;
        expect(scheduler.pendingDeviceCount, 1);
        gateway.packets[1].complete(
          SensorReading(recordedAt: clock.now(), light: 600),
        );
        expect(await second, isTrue);
        expect(scheduler.pendingDeviceCount, 0);
        expect((await repo.loadHistory('plant-1')).length, 2);
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );
  test('a failing device cannot starve another device schedule', () async {
    final clock = MutableClock(DateTime.utc(2026));
    final repo = memoryRepository(clock);
    await repo.initialize();
    final independent = await repo.save(
      draft('Independent', createDevice: true),
    );
    await connectFixtureDevice(repo, independent);
    final scheduler = ReadingScheduler(
      repo,
      FailingFirstDevice(),
      clock: clock,
    );
    try {
      clock.value = clock.value.add(const Duration(minutes: 20));
      await scheduler.processDue();
      final devices = await repo.loadDevices();
      expect(devices.first.lastAutoSlot, 0);
      expect(devices.last.lastAutoSlot, 1);
      expect((await repo.loadPlants()).last.readings.length, 1);
    } finally {
      scheduler.dispose();
      await repo.close();
    }
  });
  test(
    'manual refresh cannot move C+20; late resume adds only one current packet',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 6, 20, 10));
      final repo = memoryRepository(clock);
      await repo.initialize();
      final scheduler = ReadingScheduler(
        repo,
        FakeSensorRepository(delay: Duration.zero),
        clock: clock,
      );
      try {
        clock.value = DateTime.utc(2026, 6, 20, 10, 13);
        expect(await scheduler.refresh('plant-1'), isTrue);
        expect((await repo.loadDevices()).single.lastAutoSlot, 0);
        clock.value = DateTime.utc(2026, 6, 20, 10, 19, 59);
        await scheduler.processDue();
        expect((await repo.loadHistory('plant-1')).length, 2);
        clock.value = DateTime.utc(2026, 6, 20, 10, 20);
        await scheduler.processDue();
        expect((await repo.loadDevices()).single.lastAutoSlot, 1);
        clock.value = DateTime.utc(2026, 6, 20, 11, 40);
        await scheduler.processDue();
        expect((await repo.loadDevices()).single.lastAutoSlot, 5);
        expect((await repo.loadHistory('plant-1')).length, 4);
        expect(
          (await repo.loadPlants()).single.latestReading!.recordedAt,
          clock.now(),
        );
        await scheduler.processDue();
        expect((await repo.loadHistory('plant-1')).length, 4);
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );

  test(
    'device schedules independent; disconnected packets survive wall-clock aging',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 6, 20, 10));
      final repo = memoryRepository(clock);
      await repo.initialize();
      clock.value = clock.value.add(const Duration(minutes: 7));
      final id = await repo.save(draft('Second', createDevice: true));
      await connectFixtureDevice(repo, id);
      final scheduler = ReadingScheduler(
        repo,
        FakeSensorRepository(delay: Duration.zero),
        clock: clock,
      );
      try {
        clock.value = DateTime.utc(2026, 6, 20, 10, 20);
        await scheduler.processDue();
        final devices = await repo.loadDevices();
        expect(devices[0].lastAutoSlot, 1);
        expect(devices[1].lastAutoSlot, 0);
        expect((await repo.loadPlants()).last.id, id);
        await repo.setConnection(devices[0].id, false);
        final before =
            (await repo.loadPlants()).first.latestReading!.recordedAt;
        clock.value = DateTime.utc(2026, 11, 4);
        await scheduler.processDue();
        expect(
          (await repo.loadPlants()).first.latestReading!.recordedAt,
          before,
        );
        expect((await repo.loadPlants()).last.readings.length, 1);
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );

  test(
    'late packet cannot land after deletion, including when a label is reused',
    () async {
      final clock = MutableClock(DateTime.utc(2026));
      final repo = memoryRepository(clock);
      await repo.initialize();
      final gateway = DelayedGateway();
      final scheduler = ReadingScheduler(repo, gateway, clock: clock);
      try {
        final refresh = scheduler.refresh('plant-1');
        await gateway.started.future;
        await repo.deletePlant('plant-1');
        await repo.save(draft('Replacement', createDevice: true));
        gateway.packet.complete(
          SensorReading(recordedAt: clock.now(), light: 42),
        );
        expect(await refresh, isFalse);
        expect(scheduler.pendingDeviceCount, 0);
        expect((await repo.loadPlants()).single.readings, isEmpty);
        expect((await repo.loadDevices()).single.name, 'ESP32-Sim01');
        expect((await repo.loadDevices()).single.id, isNot('device-1'));
      } finally {
        scheduler.dispose();
        await repo.close();
      }
    },
  );

  test(
    'all-null and obsolete revision packets do not advance time or schedule',
    () async {
      final clock = MutableClock(DateTime.utc(2026));
      final repo = memoryRepository(clock);
      await repo.initialize();
      try {
        final captured = (await repo.loadDevices()).single;
        expect(
          await repo.commitReading(
            'plant-1',
            captured,
            SensorReading(
              recordedAt: clock.now().add(const Duration(minutes: 20)),
            ),
            origin: 'automatic',
            autoSlot: 1,
          ),
          isFalse,
        );
        await repo.setConnection(captured.id, false);
        await repo.setConnection(captured.id, true);
        expect(
          await repo.commitReading(
            'plant-1',
            captured,
            SensorReading(recordedAt: clock.now(), light: 100),
          ),
          isFalse,
        );
        expect((await repo.loadDevices()).single.lastAutoSlot, 0);
        expect((await repo.loadPlants()).single.readings.length, 1);
      } finally {
        await repo.close();
      }
    },
  );
}
