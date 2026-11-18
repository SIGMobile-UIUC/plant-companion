import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plant_companion/ble/ble_protocol.dart';
import 'package:plant_companion/ble/ble_sync_service.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/services/plant_condition_calculator.dart';
import 'package:plant_companion/services/reading_scheduler.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'package:plant_companion/screens/plant_details_screen.dart';
import 'package:plant_companion/widgets/reading_card.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'fixtures/ble_peripheral.dart';

Uint8List unhex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

class CleanupFailureService extends BleSyncService {
  CleanupFailureService(super.persistence, super.transport);
  @override
  Future<void> assignmentsChanged() async {
    throw StateError('test cleanup failure');
  }
}

void main() {
  late SqlitePlantRepository repo;
  late TestBlePeripheral peripheral;
  late BleSyncService service;
  Future<Device> assign() async {
    final plant = (await repo.loadPlants()).single;
    final discovered = (await service.discover()).single;
    await service.prepare(discovered);
    await repo.save(
      PlantFormDraft(
        nickname: plant.nickname,
        speciesName: plant.speciesName,
        avatar: plant.avatar,
        ranges: plant.profile.ranges,
        deviceId: discovered.id,
        physicalDevice: discovered,
        connectDevice: true,
      ),
      plantId: plant.id,
    );
    return (await repo.loadAssignedDevices()).values.single;
  }

  setUp(() async {
    repo = SqlitePlantRepository(AppDatabase(NativeDatabase.memory()));
    await repo.initialize();
    peripheral = TestBlePeripheral()..sample(kind: 1);
    service = BleSyncService(
      repo,
      peripheral,
      commandTimeout: const Duration(milliseconds: 200),
    );
  });
  tearDown(() async {
    await service.dispose();
    await repo.close();
  });

  test(
    'production C++ goldens decode in Dart including full 64-bit request',
    () {
      final golden =
          jsonDecode(File('../protocol/golden-v1.json').readAsStringSync())
              as Map<String, dynamic>;
      final record = BleRecord.decode(unhex(golden['record'] as String));
      expect(record.sequence, 42);
      expect(record.moisture, 50.5);
      expect(record.temperature, 23.56);
      expect(record.light, 123.456);
      final token = BigInt.parse('fedcba9876543210', radix: 16);
      expect(record.request, token);
      expect(
        bleCommand(BleOp.fresh, token, a: 123, b: 8),
        unhex(golden['command'] as String),
      );
      final assembler = BleBatchAssembler(token);
      for (final chunk in (golden['chunks'] as List).reversed) {
        expect(assembler.accept(unhex(chunk as String)), isNull);
      }
      final end = wireBatch([], token, cursor: 42, newest: 42).single;
      end[10] = 1;
      expect(assembler.accept(end)!.records.single.sequence, 42);
    },
  );

  test(
    'discovery and connection preparation do not persist an assignment',
    () async {
      final original = (await repo.loadPlants()).single.deviceId;
      final device = (await service.discover()).single;
      await service.prepare(device);
      expect((await repo.loadDevices()).length, 1);
      expect((await repo.loadPlants()).single.deviceId, original);
      expect(peripheral.commands, [BleOp.hello]);
    },
  );

  test(
    'Florence uses physical readings, Refresh correlates and schedule is unchanged',
    () async {
      final device = await assign();
      await service.synchronize('plant-1', device);
      final plant = (await repo.loadPlants()).single;
      expect(plant.nickname, 'Florence');
      expect(plant.latestReading!.origin, 'ble_startup');
      expect(plant.latestReading!.measuredAt, isNotNull);
      final deadline = peripheral.nextDeadline;
      await service.synchronize(plant.id, device, refresh: true);
      final fresh = (await repo.loadPlants()).single.latestReading!;
      expect(fresh.origin, 'ble_manual');
      expect(fresh.sourceDeviceId, device.id);
      expect(fresh.soilMoisture, 50.5);
      expect(fresh.temperature, 23.56);
      expect(peripheral.nextDeadline, deadline);
      expect(peripheral.commands, contains(BleOp.fresh));
      final before = (await repo.loadHistory(plant.id)).length;
      final scheduler = ReadingScheduler(
        repo,
        FakeSensorRepository(delay: Duration.zero),
      );
      await scheduler.processDue();
      scheduler.dispose();
      expect((await repo.loadHistory(plant.id)).length, before);
      expect(await repo.commitReading(plant.id, device, fresh), isFalse);
    },
  );

  test('offline catch-up is paged, replay/ACK loss do not duplicate', () async {
    final device = await assign();
    await service.synchronize('plant-1', device);
    for (var i = 0; i < 21; i++) {
      peripheral.advance(1200);
    }
    peripheral.failAck = true;
    await expectLater(
      service.synchronize('plant-1', device),
      throwsA(isA<Exception>()),
    );
    final afterFailure =
        (await repo.database.rows(
              'SELECT cursor FROM ble_sync_state',
            )).single['cursor']
            as int;
    expect(afterFailure, greaterThan(2));
    await service.synchronize('plant-1', device);
    await service.synchronize('plant-1', device);
    final history = (await repo.loadHistory(
      'plant-1',
    )).where((r) => r.origin.startsWith('ble_')).toList();
    expect(history.length, 22);
    expect(history.map((r) => r.id).toSet().length, 22);
    expect(
      (await repo.database.rows(
        'SELECT cursor FROM ble_sync_state',
      )).single['cursor'],
      peripheral.records.length,
    );
    expect(
      (await repo.loadPlants()).single.latestReading!.sequence,
      peripheral.records.length,
    );
  });

  test(
    'interrupted chunks preserve cursor and retry imports exactly once',
    () async {
      final device = await assign();
      await service.synchronize('plant-1', device);
      peripheral.advance(1200);
      final before = (await repo.database.rows(
        'SELECT cursor FROM ble_sync_state',
      )).single['cursor'];
      peripheral.interruptHistory = true;
      await expectLater(
        service.synchronize('plant-1', device),
        throwsA(isA<BleProtocolException>()),
      );
      expect(
        (await repo.database.rows(
          'SELECT cursor FROM ble_sync_state',
        )).single['cursor'],
        before,
      );
      await service.synchronize('plant-1', device);
      expect(
        (await repo.loadHistory(
          'plant-1',
        )).where((r) => r.origin.startsWith('ble_')).length,
        2,
      );
    },
  );

  test(
    'overwritten history marks a visible persistent gap and imports retained rows',
    () async {
      for (var i = 0; i < 15; i++) {
        peripheral.advance(1200);
      }
      peripheral.records.removeRange(0, 8);
      final device = await assign();
      await service.synchronize('plant-1', device);
      expect(await repo.bleHasGap(device.id), isTrue);
      expect(service.messages[device.id], contains('History gap'));
      expect(
        (await repo.loadHistory(
          'plant-1',
        )).where((r) => r.origin.startsWith('ble_')).length,
        8,
      );
    },
  );

  test(
    'reassignment rejects in-flight packets and prevents former-owner attribution',
    () async {
      final device = await assign();
      await service.synchronize('plant-1', device);
      final info = BleDeviceInfo(
        id: device.id,
        streamId: peripheral.stream,
        oldest: 1,
        latest: peripheral.sequence,
        calibrated: true,
        storageReady: true,
      );
      final captured = await repo.beginBleSync('plant-1', device, info);
      final florence = (await repo.loadPlants()).single;
      await repo.save(
        PlantFormDraft(
          nickname: florence.nickname,
          speciesName: florence.speciesName,
          avatar: florence.avatar,
          ranges: florence.profile.ranges,
        ),
        plantId: florence.id,
      );
      await expectLater(
        repo.importBleBatch(captured, const BleBatch([], 0, 0, false, false)),
        throwsStateError,
      );
      peripheral.advance(
        1200,
      ); // Sample recorded while the device had no owner.
      final newcomer = await repo.save(
        PlantFormDraft(
          nickname: 'Basil',
          speciesName: florence.speciesName,
          avatar: florence.avatar,
          ranges: florence.profile.ranges,
          deviceId: device.id,
        ),
      );
      final current = (await repo.loadAssignedDevices())[newcomer]!;
      await service.synchronize(newcomer, current);
      final history = await repo.loadHistory(newcomer);
      expect(history.length, 1);
      expect(history.single.origin, 'ble_manual');
      expect(
        (await repo.loadHistory(
          'plant-1',
        )).where((r) => r.origin.startsWith('ble_')).length,
        1,
      );
    },
  );

  test(
    'malformed CRC, truncated END and conflicting fragments are rejected',
    () {
      final raw = wireRecord(sequence: 1);
      raw[30] ^= 1;
      expect(() => BleRecord.decode(raw), throwsA(isA<BleProtocolException>()));
      final token = BigInt.from(5),
          frames = wireBatch(
            [wireRecord(sequence: 1)],
            token,
            cursor: 0,
            newest: 1,
          );
      final a = BleBatchAssembler(token);
      a.accept(frames.first);
      final conflict = Uint8List.fromList(frames.first);
      conflict[12] ^= 1;
      expect(() => a.accept(conflict), throwsA(isA<BleProtocolException>()));
      expect(() => a.accept(frames.last), throwsA(isA<BleProtocolException>()));
      expect(
        () => BleDeviceInfo.decode(Uint8List(20)),
        throwsA(isA<BleProtocolException>()),
      );
      expect(
        () => BleBatchAssembler(token).accept([1, 2]),
        throwsA(isA<BleProtocolException>()),
      );
    },
  );

  test(
    'failed SQLite fresh commit sends no ACK and reuses durable request token',
    () async {
      final device = await assign();
      await service.synchronize('plant-1', device);
      final before = (await repo.database.rows(
        'SELECT cursor FROM ble_sync_state',
      )).single['cursor'];
      final acks = peripheral.acks;
      await repo.database.customStatement(
        "CREATE TRIGGER fail_ble BEFORE INSERT ON ble_records WHEN NEW.kind=3 BEGIN SELECT RAISE(ABORT,'test SQLite failure'); END",
      );
      await expectLater(
        service.synchronize('plant-1', device, refresh: true),
        throwsA(anything),
      );
      expect(peripheral.acks, acks);
      expect(
        (await repo.database.rows(
          'SELECT cursor FROM ble_sync_state',
        )).single['cursor'],
        before,
      );
      final pending = (await repo.database.rows(
        'SELECT pending_refresh FROM ble_sync_state',
      )).single['pending_refresh'];
      expect(pending, isNotNull);
      await repo.database.customStatement('DROP TRIGGER fail_ble');
      await service.synchronize('plant-1', device, refresh: true);
      expect(peripheral.freshTokens.length, 2);
      expect(peripheral.freshTokens[0], peripheral.freshTokens[1]);
      expect(peripheral.records.where((r) => r[1] == 3).length, 1);
      expect(
        (await repo.database.rows(
          'SELECT pending_refresh FROM ble_sync_state',
        )).single['pending_refresh'],
        isNull,
      );
    },
  );

  test(
    'wrong Refresh request never reports success or clears pending request',
    () async {
      final device = await assign();
      await service.synchronize('plant-1', device);
      peripheral.wrongFresh = true;
      await expectLater(
        service.synchronize('plant-1', device, refresh: true),
        throwsA(isA<BleProtocolException>()),
      );
      expect(
        (await repo.database.rows(
          'SELECT pending_refresh FROM ble_sync_state',
        )).single['pending_refresh'],
        isNotNull,
      );
      expect(
        (await repo.loadPlants()).single.latestReading!.origin,
        'ble_startup',
      );
    },
  );

  test(
    'fresh commit remains successful when subsequent history ACK is lost',
    () async {
      final device = await assign();
      await service.synchronize('plant-1', device);
      peripheral.failAck = true;
      await service.synchronize('plant-1', device, refresh: true);
      expect(
        (await repo.loadPlants()).single.latestReading!.origin,
        'ble_manual',
      );
      expect(service.messages[device.id], contains('Fresh reading saved'));
    },
  );

  test(
    'physical post-save acquisition failure preserves plant and saved association',
    () async {
      final selected = (await service.discover()).single;
      final plant = (await repo.loadPlants()).single;
      final store = PlantStore(persistence: repo, ble: service);
      await store.initialized;
      peripheral.unavailable = true;
      final id = await store.saveDraft(
        PlantFormDraft(
          nickname: plant.nickname,
          speciesName: plant.speciesName,
          avatar: plant.avatar,
          ranges: plant.profile.ranges,
          deviceId: selected.id,
          physicalDevice: selected,
          connectDevice: true,
        ),
        plantId: plant.id,
      );
      expect(id, plant.id);
      expect((await repo.loadPlants()).single.deviceId, selected.id);
      expect((await repo.loadPlants()).single.latestReading, isNull);
      expect((await repo.loadHistory(id)).single.origin, 'seed');
      store.dispose();
      await service.dispose();
    },
  );

  test(
    'post-commit BLE cleanup error reports a warning after save and delete',
    () async {
      await service.dispose();
      service = CleanupFailureService(repo, peripheral);
      final store = PlantStore(persistence: repo, ble: service);
      await store.initialized;
      final plant = store.plants.single;
      final saved = await store.saveForm(
        PlantFormDraft(
          nickname: 'Still saved',
          speciesName: plant.speciesName,
          avatar: plant.avatar,
          ranges: plant.profile.ranges,
        ),
        plantId: plant.id,
        operationId: 'ble-cleanup-save',
      );
      expect(saved.committed, isTrue);
      expect((await repo.loadPlants()).single.nickname, 'Still saved');
      expect(saved.issue, isNotNull);
      final deleted = await store.deleteForm(
        plant.id,
        operationId: 'ble-cleanup-delete',
      );
      expect(deleted.committed, isTrue);
      expect(await repo.loadPlants(), isEmpty);
      expect(deleted.issue, isNotNull);
      store.dispose();
      await service.dispose();
    },
  );

  test(
    'unanchored older boot remains unknown; current boot anchored; partial sensor valid',
    () async {
      peripheral.reboot();
      peripheral.sample(mask: 14);
      final device = await assign();
      await service.synchronize('plant-1', device);
      final history = (await repo.loadHistory(
        'plant-1',
      )).where((r) => r.origin.startsWith('ble_')).toList();
      expect(history.first.soilMoisture, isNull);
      expect(history.first.temperature, isNotNull);
      expect(history.first.measuredAt, isNotNull);
      expect(history.last.measuredAt, isNull);
      expect(history.last.timeQuality, 'unknown');
      expect(
        ReadingPresentation(
          (await repo.loadPlants()).single,
        ).values.values.where((v) => v != null).length,
        3,
      );
    },
  );

  test(
    'database reopen and new service reconnect saved stable identity via scan',
    () async {
      await service.dispose();
      await repo.close();
      final dir = Directory.systemTemp.createTempSync('plant-ble-');
      final file = File('${dir.path}/test.sqlite');
      repo = SqlitePlantRepository(AppDatabase(NativeDatabase(file)));
      await repo.initialize();
      service = BleSyncService(repo, peripheral);
      final device = await assign();
      await service.synchronize('plant-1', device);
      await service.dispose();
      await repo.close();
      repo = SqlitePlantRepository(AppDatabase(NativeDatabase(file)));
      await repo.initialize();
      service = BleSyncService(repo, peripheral);
      await repo.database.customStatement(
        "UPDATE devices SET platform_hint='stale-platform-hint' WHERE kind='physical'",
      );
      final restored = (await repo.loadAssignedDevices()).values.single;
      expect(restored.id, device.id);
      expect(restored.isPhysical, isTrue);
      peripheral.advance(1200);
      await service.synchronize('plant-1', restored);
      expect(
        (await repo.loadPlants()).single.latestReading!.origin,
        'ble_scheduled',
      );
      // NativeDatabase is closed by tearDown before the temp directory is removed.
      addTearDown(() async {
        await service.dispose();
        await repo.close();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
    },
  );

  testWidgets(
    'fake peripheral physical readings appear through normal Florence UI',
    (tester) async {
      late PlantStore store;
      await tester.runAsync(() async {
        final device = await assign();
        await service.synchronize('plant-1', device);
        store = PlantStore(persistence: repo, ble: service);
        await store.initialized;
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: const MaterialApp(
            home: PlantDetailsScreen(plantId: 'plant-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Florence'), findsWidgets);
      final shown = {
        for (final card in tester.widgetList<ReadingCard>(
          find.byType(ReadingCard),
        ))
          card.metric: card.value,
      };
      expect(shown, {
        SensorMetric.soilMoisture: 50.5,
        SensorMetric.temperature: 23.56,
        SensorMetric.humidity: 45.67,
        SensorMetric.light: 123.456,
      });
      expect(find.textContaining('Physical BLE'), findsOneWidget);
      expect(find.byKey(const Key('refresh-button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
