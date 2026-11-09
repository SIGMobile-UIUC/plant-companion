import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant_device_draft.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'fixtures/foundation_fixtures.dart';

class DraftGateway extends FakeSensorRepository {
  DraftGateway() : super(delay: Duration.zero);
  List<Device> inventoryResult = [];
  final scans = <Completer<List<Device>>>[];
  final connections = <String, Completer<Device>>{},
      started = <String, Completer<void>>{};
  int connectionCalls = 0, acquisitions = 0;
  bool fail = false;
  @override
  Future<List<Device>> discoverDevices() async =>
      scans.isEmpty ? inventoryResult : scans.removeAt(0).future;
  @override
  Future<Device> connect(Device device, {bool simulateFailure = false}) async {
    connectionCalls++;
    final signal = started[device.id];
    if (signal != null && !signal.isCompleted) signal.complete();
    if (fail) throw StateError('Injected connection failure');
    return connections[device.id]?.future ??
        Future.value(device.withConnection(true));
  }

  @override
  Future<SensorReading> acquire(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) {
    acquisitions++;
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
  late DraftGateway gateway;
  PlantDeviceDraft? state;
  setUp(() async {
    final clock = MutableClock(DateTime.utc(2026, 11, 6, 12)),
        repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 6, 12)));
    gateway = DraftGateway();
    store = PlantStore(persistence: repo, repository: gateway, clock: clock);
    await store.initialized;
    gateway.inventoryResult = store.devices;
    state = PlantDeviceDraft(store);
  });
  tearDown(() {
    state?.dispose();
    store.dispose();
  });

  test(
    'zero/multiple discovery is safe; other-owned device never becomes selectable',
    () async {
      gateway.inventoryResult = [];
      await state!.scan();
      expect(state!.inventory, isEmpty);
      expect(state!.selectedDeviceId, isNull);
      gateway.inventoryResult = store.devices;
      await state!.scan();
      final occupied = state!.inventory.single;
      expect(state!.ownerName(occupied.id), 'Florence');
      await state!.connectExisting(occupied);
      expect(state!.selectedDeviceId, isNull);
      expect(gateway.connectionCalls, 0);
      final one = state!.createCandidate(), two = state!.createCandidate();
      expect(one.token, isNot(two.token));
      expect(state!.candidates.length, 2);
      expect(
        (one.candidate.createdAt, one.candidate.displayOrdinal),
        (null, 0),
      );
      expect((await store.persistence.loadDevices()).length, 1);
      expect((await store.persistence.loadPlants()).length, 1);
    },
  );
  test(
    'own assigned device remains selectable; Unassign only changes the draft',
    () async {
      state!.dispose();
      state = PlantDeviceDraft(store, plantId: 'plant-1', deviceId: 'device-1');
      expect(state!.eligible('device-1'), isTrue);
      state!.unassign();
      expect(state!.selectedDeviceId, isNull);
      expect(store.plants.single.deviceId, 'device-1');
      expect(
        (await store.persistence.loadAssignedDevices())['plant-1']!.isConnected,
        isTrue,
      );
      await state!.connectExisting(store.devices.single);
      expect(state!.preparedKey, 'device-1');
      expect(
        (await store.persistence.loadDevices()).single.revision,
        store.devices.single.revision,
      );
      expect(gateway.acquisitions, 0);
    },
  );
  test(
    'newer discovery wins; older async result cannot overwrite inventory or discard candidates',
    () async {
      final first = Completer<List<Device>>(),
          second = Completer<List<Device>>();
      gateway.scans.addAll([first, second]);
      final a = state!.scan(), b = state!.scan();
      state!.createCandidate();
      state!.createCandidate();
      second.complete([]);
      await b;
      expect(state!.searching, isFalse);
      expect(state!.inventory, isEmpty);
      first.complete([
        const Device(id: 'obsolete', name: 'Obsolete', isConnected: false),
      ]);
      await a;
      expect(state!.inventory, isEmpty);
      expect(state!.candidates.length, 2);
      expect((await store.persistence.loadDevices()).length, 1);
    },
  );
  test(
    'selection change invalidates late connection results without changing persisted connection',
    () async {
      final a = state!.createCandidate(), b = state!.createCandidate();
      final first = gateway.connections[a.candidate.id] = Completer<Device>(),
          second = gateway.connections[b.candidate.id] = Completer<Device>();
      final startedA = gateway.started[a.candidate.id] = Completer<void>(),
          startedB = gateway.started[b.candidate.id] = Completer<void>();
      final pendingA = state!.connectCandidate(a);
      await startedA.future;
      final pendingB = state!.connectCandidate(b);
      await startedB.future;
      first.complete(a.candidate.withConnection(true));
      await pendingA;
      expect(state!.preparedKey, isNull);
      expect(state!.selectedCandidateToken, b.token);
      second.complete(b.candidate.withConnection(true));
      await pendingB;
      expect(state!.preparedKey, b.candidate.id);
      expect((await store.persistence.loadDevices()).length, 1);
      expect((await store.persistence.loadHistory('plant-1')).length, 1);
      expect(store.scheduler.pendingDeviceCount, 0);
    },
  );
  test(
    'dispose and Unassign invalidate pending discovery/connection without post-dispose publication',
    () async {
      final scan = Completer<List<Device>>();
      gateway.scans.add(scan);
      final future = state!.scan();
      state!.dispose();
      state = null;
      scan.complete([]);
      await future;
      state = PlantDeviceDraft(store);
      final candidate = state!.createCandidate();
      final gate = gateway.connections[candidate.candidate.id] =
              Completer<Device>(),
          started = gateway.started[candidate.candidate.id] = Completer<void>();
      final connecting = state!.connectCandidate(candidate);
      await started.future;
      state!.unassign();
      gate.complete(candidate.candidate.withConnection(true));
      await connecting;
      expect(state!.preparedKey, isNull);
      expect(state!.createsDevice, isFalse);
      expect(state!.selectionKey, isNull);
      expect((await store.persistence.loadDevices()).length, 1);
      expect(store.scheduler.pendingDeviceCount, 0);
    },
  );
  test(
    'failed preparation can save a disconnected candidate; retry/preparation never reserves IDs',
    () async {
      final candidate = state!.createCandidate();
      gateway.fail = true;
      await state!.connectCandidate(candidate);
      expect(state!.selectedCandidateToken, candidate.token);
      expect(state!.preparedKey, isNull);
      expect(state!.error, isNotNull);
      expect((await store.persistence.loadDevices()).length, 1);
      final result = await store.saveForm(
        draft('Disconnected', createDevice: state!.createsDevice),
        operationId: 'disconnected',
      );
      expect(result.committed, isTrue);
      final p = store.plantById(result.plantId!);
      expect(store.deviceFor(p)!.isConnected, isFalse);
      expect(p.latestReading, isNull);
      expect(store.deviceFor(p)!.id, 'device-2');
      expect(gateway.acquisitions, 0);
    },
  );
  test(
    'an assignment taken during candidate preparation invalidates its proof and cannot be stolen',
    () async {
      await store.unlinkDevice('plant-1');
      state!.dispose();
      state = PlantDeviceDraft(store);
      final device = store.devices.single,
          gate = gateway.connections[device.id] = Completer<Device>(),
          started = gateway.started[device.id] = Completer<void>();
      final preparing = state!.connectExisting(device);
      await started.future;
      final other = await store.persistence.save(
        draft('Other', deviceId: device.id),
      );
      await store.reload();
      gate.complete(device.withConnection(true));
      await preparing;
      expect(state!.preparedKey, isNull);
      expect(state!.error, contains('assigned to another plant'));
      final rejected = await store.saveForm(
        draft('Cannot steal', deviceId: device.id),
        operationId: 'cannot-steal',
      );
      expect(rejected.committed, isFalse);
      expect(
        (await store.persistence.loadAssignedDevices())[other]!.id,
        device.id,
      );
      expect(
        (await store.persistence.loadAssignedDevices())[other]!.isConnected,
        isFalse,
      );
    },
  );
  test(
    'draft preparation and real Refresh share existing per-device serialization and cleanup',
    () async {
      state!.dispose();
      state = PlantDeviceDraft(store, plantId: 'plant-1', deviceId: 'device-1');
      final device = store.devices.single,
          gate = gateway.connections[device.id] = Completer<Device>(),
          started = gateway.started[device.id] = Completer<void>();
      final preparing = state!.connectExisting(device);
      await started.future;
      final refresh = store.refresh('plant-1');
      await Future<void>.delayed(Duration.zero);
      expect(gateway.acquisitions, 0);
      gate.complete(device.withConnection(true));
      await preparing;
      await refresh;
      expect(gateway.acquisitions, 1);
      expect((await store.persistence.loadHistory('plant-1')).length, 2);
      expect(store.scheduler.pendingDeviceCount, 0);
    },
  );
}
