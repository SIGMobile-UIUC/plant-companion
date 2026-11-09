import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'fixtures/foundation_fixtures.dart';

class BlockingRepository extends SqlitePlantRepository {
  BlockingRepository(MutableClock clock)
    : super(AppDatabase(NativeDatabase.memory()), clock: clock);
  Completer<void>? readStarted;
  Completer<void>? releaseRead;
  int plantLoads = 0;
  @override
  Future<List<Plant>> loadPlants() async {
    plantLoads++;
    final snapshot = await super.loadPlants();
    final release = releaseRead;
    if (release != null) {
      releaseRead = null;
      readStarted!.complete();
      await release.future;
    }
    return snapshot;
  }
}

class SaveGateway extends FakeSensorRepository {
  SaveGateway() : super(delay: Duration.zero);
  bool fail = false;
  Completer<void>? started;
  Completer<void>? release;
  int acquisitions = 0;
  @override
  Future<SensorReading> acquire(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) async {
    acquisitions++;
    started?.complete();
    await release?.future;
    if (fail) throw StateError('Injected read failure');
    return super.acquire(
      device,
      recordedAt,
      previousReading: previousReading,
      simulationMode: simulationMode,
      plantContext: plantContext,
    );
  }
}

void main() {
  late PlantStore store;
  late MutableClock clock;
  late BlockingRepository repo;
  late SaveGateway gateway;
  setUp(() async {
    clock = MutableClock(DateTime.utc(2026, 6, 20, 10));
    repo = BlockingRepository(clock);
    gateway = SaveGateway();
    store = PlantStore(persistence: repo, repository: gateway, clock: clock);
    await store.initialized;
  });
  tearDown(() {
    store.dispose();
  });

  test(
    'overlapping reloads coalesce and never publish the obsolete snapshot',
    () async {
      final started = repo.readStarted = Completer<void>();
      final release = repo.releaseRead = Completer<void>();
      final published = <String>[];
      store.addListener(() => published.add(store.plants.single.nickname));
      final before = repo.plantLoads;
      final first = store.reload();
      await started.future;
      await repo.save(
        draft('Edited', deviceId: 'device-1'),
        plantId: 'plant-1',
      );
      final second = store.reload();
      final third = store.reload();
      expect(identical(second, third), isTrue);
      release.complete();
      await Future.wait([first, second, third]);
      expect(published, ['Edited']);
      expect(repo.plantLoads - before, 2);
    },
  );

  test(
    'post-save connection packet preserves creation anchor and edit adds no packet',
    () async {
      clock.value = clock.now().add(const Duration(minutes: 7));
      final created = clock.now();
      final id = await store.saveDraft(draft('New', createDevice: true));
      final plant = store.plantById(id);
      final device = store.deviceFor(plant)!;
      expect(plant.latestReading!.origin, 'connection');
      expect(plant.latestReading!.recordedAt, created);
      expect(device.createdAt, created);
      expect(device.lastAutoSlot, 0);
      expect(device.generationSequence, 1);
      await store.saveDraft(draft('Edited', deviceId: device.id), plantId: id);
      expect(gateway.acquisitions, 1);
      clock.value = created.add(const Duration(minutes: 19, seconds: 59));
      await store.scheduler.processDue();
      expect((await repo.loadHistory(id)).length, 1);
      clock.value = created.add(const Duration(minutes: 20));
      await store.scheduler.processDue();
      expect((await repo.loadHistory(id)).length, 2);
      expect(store.deviceFor(store.plantById(id))!.createdAt, created);
      expect(store.deviceFor(store.plantById(id))!.lastAutoSlot, 1);
    },
  );

  test(
    'failed initial acquisition leaves saved plant visible with no invented sync',
    () async {
      gateway.fail = true;
      final started = gateway.started = Completer<void>();
      final release = gateway.release = Completer<void>();
      final saving = store.saveDraft(draft('Durable', createDevice: true));
      await started.future;
      expect(store.plants.last.nickname, 'Durable');
      expect(store.plants.last.latestReading, isNull);
      expect((await repo.loadDevices()).last.isConnected, isTrue);
      release.complete();
      final id = await saving;
      expect(store.plantById(id).latestReading, isNull);
      expect(await repo.loadHistory(id), isEmpty);
      expect(store.deviceFor(store.plantById(id))!.generationSequence, 0);
      expect(store.lastError, isA<StateError>());
      // A later normal scheduled acquisition can recover this saved assignment.
      gateway.fail = false;
      gateway.started = gateway.release = null;
      clock.value = clock.now().add(const Duration(minutes: 20));
      await store.scheduler.processDue();
      expect(store.plantById(id).latestReading!.recordedAt, clock.now());
    },
  );

  test(
    'reconnecting existing device acquires once and retains its original anchor',
    () async {
      final created = store.deviceFor(store.plants.single)!.createdAt;
      await repo.setConnection('device-1', false);
      clock.value = clock.now().add(const Duration(minutes: 27));
      await store.saveDraft(
        draft('Florence', deviceId: 'device-1', connectDevice: true),
        plantId: 'plant-1',
      );
      expect(gateway.acquisitions, 1);
      expect(store.deviceFor(store.plants.single)!.createdAt, created);
      expect(store.deviceFor(store.plants.single)!.lastAutoSlot, 1);
      expect(store.plants.single.latestReading!.recordedAt, clock.now());
      await store.scheduler.processDue();
      expect((await repo.loadHistory('plant-1')).length, 2);
      clock.value = created!.add(const Duration(minutes: 40));
      await store.scheduler.processDue();
      expect((await repo.loadHistory('plant-1')).length, 3);
    },
  );

  test(
    'disconnection preserves old packet/time until an explicit reconnect refresh succeeds',
    () async {
      final before = store.plants.single.latestReading!;
      await store.persistence.setConnection('device-1', false);
      await store.reload();
      expect(store.deviceFor(store.plants.single)!.isConnected, isFalse);
      await store.refresh('plant-1');
      expect(store.deviceFor(store.plants.single)!.isConnected, isTrue);
      final history = await store.persistence.loadHistory('plant-1');
      expect(history, hasLength(2));
      expect(history.last.id, before.id);
      expect(history.last.recordedAt, before.recordedAt);
    },
  );

  test(
    'history remains saved on unlink; measurement null never becomes zero',
    () async {
      final before = store.plants.single.latestReading!;
      await store.unlinkDevice('plant-1');
      expect(store.plants.single.deviceId, isNull);
      expect(store.plants.single.latestReading, isNull);
      expect((await repo.loadHistory('plant-1')).single.id, before.id);
      expect(
        const TargetRange(0, 100).statusFor(null),
        ReadingStatus.unavailable,
      );
    },
  );

  test(
    'device uniqueness is enforced by persistence and shared state',
    () async {
      await expectLater(
        store.addPlant(
          nickname: 'Other',
          profile: PlantProfile.samples.first,
          device: FakeSensorRepository.demoDevice,
        ),
        throwsStateError,
      );
      await store.unlinkDevice('plant-1');
      await store.addPlant(
        nickname: 'Other',
        profile: PlantProfile.samples.first,
        device: FakeSensorRepository.demoDevice,
      );
      expect(store.plants.last.deviceId, FakeSensorRepository.demoDevice.id);
      expect(store.plants.first.readings, isEmpty);
      expect((await repo.loadHistory('plant-1')).length, 1);
    },
  );

  test('plants saved without device have no measured packet', () async {
    await store.addPlant(
      nickname: 'Other',
      profile: PlantProfile.samples.first,
    );
    expect(store.plants.last.latestReading, isNull);
  });

  test(
    'manual refresh appends history and keeps internal wetness semantics',
    () async {
      await store.refresh('plant-1');
      expect(store.plants.single.readings.length, 1);
      expect((await store.persistence.loadHistory('plant-1')).length, 2);
      expect(SensorMetric.soilMoisture.unit, 'index / 100');
    },
  );
}
