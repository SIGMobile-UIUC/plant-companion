import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_commit.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'fixtures/foundation_fixtures.dart';
import 'device_refresh_test.dart' show ControlledRefreshGateway;

class MutationFaultRepository extends SqlitePlantRepository {
  MutationFaultRepository(MutableClock clock)
    : super(AppDatabase(NativeDatabase.memory()), clock: clock);
  int failingLoads = 0,
      failingAssignments = 0,
      receiptLookupFailures = 0,
      deletionLookupFailures = 0;
  int loadsAfterSave = 0, loadsAfterDelete = 0;
  bool loseSaveAck = false,
      loseDeleteAck = false,
      failSchedulerAfterSave = false,
      failSchedulerAfterDelete = false;
  Completer<void>? savingStarted, releaseSave;
  Future<void> Function(PlantSaveReceipt)? afterSave;
  @override
  Future<List<Plant>> loadPlants() {
    if (failingLoads > 0) {
      failingLoads--;
      throw StateError('Injected post-commit reload failure');
    }
    return super.loadPlants();
  }

  @override
  Future<Map<String, Device>> loadAssignedDevices() {
    if (failingAssignments > 0) {
      failingAssignments--;
      throw StateError('Injected scheduler failure');
    }
    return super.loadAssignedDevices();
  }

  @override
  Future<PlantSaveReceipt> saveWithReceipt(
    PlantFormDraft draft, {
    String? plantId,
    required String operationId,
  }) async {
    final release = releaseSave;
    releaseSave = null;
    if (release != null) {
      savingStarted!.complete();
      await release.future;
    }
    final receipt = await super.saveWithReceipt(
      draft,
      plantId: plantId,
      operationId: operationId,
    );
    final hook = afterSave;
    afterSave = null;
    if (hook != null) await hook(receipt);
    failingLoads = loadsAfterSave;
    loadsAfterSave = 0;
    if (failSchedulerAfterSave) {
      failSchedulerAfterSave = false;
      failingAssignments = 1;
    }
    if (loseSaveAck) {
      loseSaveAck = false;
      throw StateError('Injected lost committed Save acknowledgement');
    }
    return receipt;
  }

  @override
  Future<PlantSaveReceipt?> findSaveReceipt(String id) {
    if (receiptLookupFailures > 0) {
      receiptLookupFailures--;
      throw StateError('Receipt temporarily unavailable');
    }
    return super.findSaveReceipt(id);
  }

  @override
  Future<void> deletePlant(
    String id, {
    PlantEditToken? expected,
    String? operationId,
  }) async {
    await super.deletePlant(id, expected: expected, operationId: operationId);
    failingLoads = loadsAfterDelete;
    loadsAfterDelete = 0;
    if (failSchedulerAfterDelete) {
      failSchedulerAfterDelete = false;
      failingAssignments = 1;
    }
    if (loseDeleteAck) {
      loseDeleteAck = false;
      throw StateError('Injected lost committed Delete acknowledgement');
    }
  }

  @override
  Future<bool> deletionCommitted(String id) {
    if (deletionLookupFailures > 0) {
      deletionLookupFailures--;
      throw StateError('Delete receipt temporarily unavailable');
    }
    return super.deletionCommitted(id);
  }
}

void main() {
  late MutableClock clock;
  late MutationFaultRepository repo;
  late ControlledRefreshGateway gateway;
  late PlantStore store;
  setUp(() async {
    clock = MutableClock(DateTime.utc(2026, 11, 6, 12));
    repo = MutationFaultRepository(clock);
    gateway = ControlledRefreshGateway();
    store = PlantStore(persistence: repo, repository: gateway, clock: clock);
    await store.initialized;
  });
  tearDown(() => store.dispose());
  PlantEditToken token() {
    final p = store.plants.first;
    return PlantEditToken(
      profileRevision: p.profileRevision,
      deviceId: p.deviceId,
      deviceRevision: store.deviceFor(p)?.revision,
    );
  }

  test(
    'post-save successful gateway connection and packet keep the original creation anchor',
    () async {
      final result = await store.saveForm(
        draft('New', createDevice: true),
        operationId: 'new',
      );
      expect(result.committed, isTrue);
      expect((gateway.connections, gateway.acquisitions), (1, 1));
      final p = store.plantById(result.plantId!), d = store.deviceFor(p)!;
      expect(result.receipt!.assignedDevice!.isConnected, isFalse);
      expect(d.isConnected, isTrue);
      expect(
        (d.createdAt, d.lastAutoSlot, d.generationSequence),
        (clock.now(), 0, 1),
      );
      expect(p.latestReading!.sourceDeviceId, d.id);
      expect(p.latestReading!.origin, 'connection');
      clock.value = clock.now().add(const Duration(minutes: 20));
      await store.scheduler.processDue();
      expect((await repo.loadHistory(p.id)).length, 2);
      expect(store.deviceFor(store.plantById(p.id))!.lastAutoSlot, 1);
    },
  );
  for (final failConnection in [true, false]) {
    test(
      'saved plant survives ${failConnection ? 'connection' : 'acquisition'} failure with truthful state/time',
      () async {
        gateway.failConnection = failConnection;
        gateway.failAcquisition = !failConnection;
        final result = await store.saveForm(
          draft('Durable', createDevice: true),
          operationId: 'failed-sensor',
        );
        expect(result.status, PlantCommitStatus.committedWithWarning);
        expect(
          result.issue,
          failConnection
              ? PlantPostCommitIssue.connection
              : PlantPostCommitIssue.acquisition,
        );
        final p = store.plantById(result.plantId!);
        expect(store.deviceFor(p)!.isConnected, !failConnection);
        expect(p.latestReading, isNull);
        expect(await repo.loadHistory(p.id), isEmpty);
        expect(store.deviceFor(p)!.lastAutoSlot, 0);
        expect(store.deviceFor(p)!.generationSequence, 0);
        expect((
          gateway.connections,
          gateway.acquisitions,
        ), failConnection ? (1, 0) : (1, 1));
      },
    );
  }
  test(
    'ordinary connected Edit changes profile only; Full Name and packet survive unrelated updates',
    () async {
      final before = store.plants.first.latestReading!,
          anchor = store.deviceFor(store.plants.first)!.createdAt;
      final form = PlantFormDraft(
        nickname: 'Bart',
        speciesName: 'Custom',
        avatar: store.plants.first.avatar,
        ranges: store.plants.first.profile.ranges,
        deviceId: 'device-1',
        fullName: 'Bartholomew',
        editToken: token(),
      );
      expect(
        (await store.saveForm(
          form,
          plantId: 'plant-1',
          operationId: 'rename',
        )).committed,
        isTrue,
      );
      expect((gateway.connections, gateway.acquisitions), (0, 0));
      expect(store.plants.first.latestReading!.id, before.id);
      await store.unlinkDevice('plant-1');
      expect(store.plants.first.fullName, 'Bartholomew');
      expect(store.plants.first.latestReading, isNull);
      expect((await repo.loadHistory('plant-1')).single.id, before.id);
      expect((await repo.loadDevices()).single.createdAt, anchor);
    },
  );
  test(
    'abandoned connected draft candidate has no durable side effects or reserved identities',
    () async {
      const candidate = Device(
        id: 'draft-local-1',
        name: 'New device 1',
        isConnected: false,
      );
      final connected = await store.scheduler.prepareConnection(
        candidate,
        gateway,
      );
      expect(connected.isConnected, isTrue);
      expect((await repo.loadDevices()).length, 1);
      expect((await repo.loadPlants()).length, 1);
      expect((await repo.loadHistory('plant-1')).length, 1);
      expect(store.scheduler.pendingDeviceCount, 0);
      final id = await store.saveDraft(draft('Real', createDevice: true));
      expect(id, 'plant-2');
      expect(store.deviceFor(store.plantById(id))!.id, 'device-2');
    },
  );
  test(
    'double Save shares an operation; durable replay after completion never duplicates Add',
    () async {
      gateway.connection = Completer<Device>();
      gateway.connecting = Completer<void>();
      final first = store.saveForm(
        draft('Once', createDevice: true),
        operationId: 'double',
      );
      final second = store.saveForm(
        draft('Once', createDevice: true),
        operationId: 'double',
      );
      expect(identical(first, second), isTrue);
      await gateway.connecting!.future;
      final d = (await repo.loadDevices()).last;
      gateway.connection!.complete(d.withConnection(true));
      final result = await first;
      expect(result.committed, isTrue);
      expect((await repo.loadPlants()).length, 2);
      final replay = await store.saveForm(
        draft('Once', createDevice: true),
        operationId: 'double',
      );
      expect(replay.plantId, result.plantId);
      expect((await repo.loadPlants()).length, 2);
      expect(gateway.acquisitions, 1);
    },
  );
  test(
    'ambiguous committed Add reconciles with its stable identity before any retry',
    () async {
      repo.loseSaveAck = true;
      repo.receiptLookupFailures = 1;
      final pending = await store.saveForm(
        draft('Uncertain', createDevice: true),
        operationId: 'uncertain',
      );
      expect(pending.status, PlantCommitStatus.uncertain);
      expect((await repo.loadPlants()).length, 2);
      expect(gateway.connections, 0);
      final resolved = await store.saveForm(
        draft('Uncertain', createDevice: true),
        operationId: 'uncertain',
      );
      expect(resolved.committed, isTrue);
      expect((await repo.loadPlants()).length, 2);
      expect((await repo.loadDevices()).length, 2);
      expect(resolved.plantId, 'plant-2');
      expect(gateway.acquisitions, 1);
    },
  );

  test(
    'a committed operation identity cannot silently report different inputs as saved',
    () async {
      final saved = await store.saveForm(
        draft('Original'),
        operationId: 'identity',
      );
      expect(saved.committed, isTrue);
      final changed = await store.saveForm(
        draft('Different'),
        operationId: 'identity',
      );
      expect(changed.status, PlantCommitStatus.conflict);
      expect((await repo.loadPlants()).last.nickname, 'Original');
      expect((await repo.loadPlants()).length, 2);
    },
  );
  test(
    'lost Save acknowledgement reconciles immediately when its receipt is readable',
    () async {
      repo.loseSaveAck = true;
      final result = await store.saveForm(
        draft('Committed'),
        operationId: 'lost-ack',
      );
      expect(result.committed, isTrue);
      expect(store.plants.last.nickname, 'Committed');
      expect((await repo.loadPlants()).length, 2);
    },
  );
  for (final permanent in [false, true]) {
    test(
      'committed Save reload failure is secondary; persistent=$permanent',
      () async {
        repo.loadsAfterSave = permanent ? 2 : 1;
        final result = await store.saveForm(
          draft('Saved'),
          operationId: 'reload',
        );
        expect(result.committed, isTrue);
        expect(result.issue, permanent ? PlantPostCommitIssue.reload : null);
        expect((await repo.loadPlants()).last.nickname, 'Saved');
        final replay = await store.saveForm(
          draft('Saved'),
          operationId: 'reload',
        );
        expect(replay.plantId, result.plantId);
        expect(store.plants.length, 2);
      },
    );
  }
  test(
    'committed Save scheduler failure is secondary and does not roll back durable profile',
    () async {
      await store.scheduler.resume();
      repo.failSchedulerAfterSave = true;
      final result = await store.saveForm(
        draft('Saved'),
        operationId: 'timer-save',
      );
      expect(result.committed, isTrue);
      expect(result.issue, PlantPostCommitIssue.scheduler);
      expect((await repo.loadPlants()).last.nickname, 'Saved');
    },
  );
  test(
    'follow-up actions use actual transaction transition, not an older assignment snapshot',
    () async {
      final holder = await repo.save(draft('Holder', createDevice: true));
      final b = (await repo.loadAssignedDevices())[holder]!;
      await repo.save(draft('Holder'), plantId: holder);
      repo.savingStarted = Completer<void>();
      final release = repo.releaseSave = Completer<void>();
      final saving = store.saveForm(
        draft('Florence', deviceId: 'device-1'),
        plantId: 'plant-1',
        operationId: 'transition',
      );
      await repo.savingStarted!.future;
      await repo.save(draft('External', deviceId: b.id), plantId: 'plant-1');
      release.complete();
      final result = await saving;
      expect(result.committed, isTrue);
      expect(result.receipt!.previousDevice!.id, b.id);
      expect(result.receipt!.assignedDevice!.id, 'device-1');
      expect((gateway.connections, gateway.acquisitions), (1, 1));
      expect(store.plants.first.latestReading!.sourceDeviceId, 'device-1');
    },
  );
  test(
    'captured Edit token rejects concurrent Save assignment changes without overwriting',
    () async {
      final old = store.plants.first, captured = token();
      repo.savingStarted = Completer<void>();
      final release = repo.releaseSave = Completer<void>();
      final saving = store.saveForm(
        PlantFormDraft(
          nickname: 'Stale',
          speciesName: old.speciesName,
          avatar: old.avatar,
          ranges: old.profile.ranges,
          deviceId: old.deviceId,
          editToken: captured,
        ),
        plantId: old.id,
        operationId: 'conflict',
      );
      await repo.savingStarted!.future;
      await repo.save(draft('External'), plantId: old.id);
      release.complete();
      expect((await saving).status, PlantCommitStatus.conflict);
      expect((await repo.loadPlants()).first.nickname, 'External');
      expect((gateway.connections, gateway.acquisitions), (0, 0));
    },
  );
  test(
    'assignment changed after commit cannot acquire against the newer assignment',
    () async {
      repo.afterSave = (receipt) =>
          repo.save(draft('External'), plantId: receipt.plantId).then((_) {});
      final result = await store.saveForm(
        draft('New', createDevice: true),
        operationId: 'changed-after-commit',
      );
      expect(result.committed, isTrue);
      expect(result.issue, PlantPostCommitIssue.assignmentChanged);
      expect((gateway.connections, gateway.acquisitions), (0, 0));
      expect((await repo.loadPlants()).last.deviceId, isNull);
      expect(await repo.loadHistory(result.plantId!), isEmpty);
    },
  );
  for (final failAt in ['reload', 'scheduler']) {
    test(
      'committed Delete with $failAt failure removes stale routes state and cannot resurrect',
      () async {
        final old = store.plants.first, captured = token();
        await store.scheduler.resume();
        if (failAt == 'reload') {
          repo.loadsAfterDelete = 2;
        } else {
          repo.failSchedulerAfterDelete = true;
        }
        final result = await store.deleteForm(
          old.id,
          expected: captured,
          operationId: 'delete-$failAt',
        );
        expect(result.committed, isTrue);
        expect(result.deletion, isTrue);
        expect(
          result.issue,
          failAt == 'reload'
              ? PlantPostCommitIssue.reload
              : PlantPostCommitIssue.scheduler,
        );
        expect(store.findPlant(old.id), isNull);
        expect(await repo.loadPlants(), isEmpty);
        expect(await repo.loadDevices(), isEmpty);
        final stale = await store.saveForm(
          draft('Zombie'),
          plantId: old.id,
          operationId: 'zombie',
        );
        expect(stale.status, PlantCommitStatus.conflict);
        await repo.initialize();
        expect(await repo.loadPlants(), isEmpty);
      },
    );
  }
  test(
    'Delete transaction failure leaves persisted target and store intact',
    () async {
      await repo.database.customStatement(
        "CREATE TRIGGER fail_delete BEFORE DELETE ON devices BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      final result = await store.deleteForm(
        'plant-1',
        expected: token(),
        operationId: 'delete-fail',
      );
      expect(result.status, PlantCommitStatus.notCommitted);
      expect(store.findPlant('plant-1'), isNotNull);
      expect((await repo.loadPlants()).length, 1);
      expect((await repo.loadDevices()).length, 1);
      expect(await repo.deletionCommitted('delete-fail'), isFalse);
    },
  );
  test(
    'uncertain Delete reconciles committed outcome without a second destructive mutation',
    () async {
      final captured = token();
      repo.loseDeleteAck = true;
      repo.deletionLookupFailures = 1;
      final first = await store.deleteForm(
        'plant-1',
        expected: captured,
        operationId: 'uncertain-delete',
      );
      expect(first.status, PlantCommitStatus.uncertain);
      expect(await repo.loadPlants(), isEmpty);
      final checked = await store.deleteForm(
        'plant-1',
        expected: captured,
        operationId: 'uncertain-delete',
      );
      expect(checked.committed, isTrue);
      expect(store.plants, isEmpty);
      await repo.initialize();
      expect(await repo.loadPlants(), isEmpty);
    },
  );
}
