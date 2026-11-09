import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/plant_commit.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'package:plant_companion/services/plant_repository.dart';
import 'fixtures/foundation_fixtures.dart';
import 'fixtures/schema_v1.dart';

Future<void> populateVersionOne(
  PhaseCV1Database db,
  DateTime at, {
  bool empty = false,
}) async {
  await db.customStatement(
    "INSERT INTO app_meta(key,value) VALUES ('initialized','1')",
  );
  for (final kind in ['plant', 'device', 'reading']) {
    await db.customStatement(
      'INSERT INTO id_counters(kind,next_value) VALUES (?,?)',
      [kind, empty ? 50 : 3],
    );
  }
  if (empty) return;
  for (var i = 1; i <= 2; i++) {
    await db.customStatement(
      'INSERT INTO devices(id,display_ordinal,created_at_ms,connected,revision,last_auto_slot,generation_sequence) VALUES (?,?,?,?,?,?,?)',
      [
        'device-$i',
        i,
        at.millisecondsSinceEpoch - i * 1000,
        i == 1 ? 1 : 0,
        i + 2,
        i + 4,
        i + 10,
      ],
    );
    await db.customStatement(
      'INSERT INTO plants(id,nickname,species,avatar_id,device_id,created_at_ms,updated_at_ms,display_order) VALUES (?,?,?,?,?,?,?,?)',
      [
        'plant-$i',
        'Original $i',
        'Custom species $i',
        i == 1 ? 'pothos' : 'snakePlant',
        'device-$i',
        at.millisecondsSinceEpoch,
        at.millisecondsSinceEpoch + 1,
        i,
      ],
    );
    for (final m in SensorMetric.values) {
      final r = PlantAvatarId.pothos.hints[m]!;
      await db.customStatement(
        'INSERT INTO plant_ranges(plant_id,metric,minimum,maximum) VALUES (?,?,?,?)',
        ['plant-$i', m.name, r.minimum, r.maximum],
      );
    }
    await db.customStatement(
      'INSERT INTO sensor_readings(id,plant_id,source_device_id,recorded_at_ms,soil_moisture,light_lux,temperature_c,humidity,origin,auto_slot) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'reading-$i',
        'plant-$i',
        'device-1',
        at.millisecondsSinceEpoch,
        38,
        280,
        23.88888888888889,
        42,
        'manual',
        null,
      ],
    );
  }
}

void main() {
  late MutableClock clock;
  late SqlitePlantRepository repo;
  setUp(() async {
    clock = MutableClock(DateTime.utc(2026, 11, 6, 12));
    repo = memoryRepository(clock);
    await repo.initialize();
  });
  tearDown(() => repo.close());
  Future<PlantEditToken> token(String id) async {
    final p = (await repo.loadPlants()).firstWhere((p) => p.id == id),
        d = (await repo.loadAssignedDevices())[id];
    return PlantEditToken(
      profileRevision: p.profileRevision,
      deviceId: p.deviceId,
      deviceRevision: d?.revision,
    );
  }

  test(
    'fresh v2 preserves approved exact Florence bootstrap and no fabricated full name',
    () async {
      expect(
        (await repo.database.rows(
          'PRAGMA user_version',
        )).single['user_version'],
        2,
      );
      final p = (await repo.loadPlants()).single,
          d = (await repo.loadDevices()).single;
      expect(p.fullName, isNull);
      expect(p.profileRevision, 0);
      expect(p.latestReading!.light, 280);
      expect(p.latestReading!.recordedAt, clock.now());
      expect(d.isConnected, isTrue);
      expect(d.createdAt, clock.now());
    },
  );
  test(
    'new durable assignment is disconnected until real guarded connection; flags are intent only',
    () async {
      final receipt = await repo.saveWithReceipt(
        draft('New', createDevice: true, connectDevice: true),
        operationId: 'new',
      );
      expect(receipt.deviceCreated, isTrue);
      expect(receipt.assignedDevice!.isConnected, isFalse);
      expect(receipt.needsConnectionPacket, isTrue);
      expect(receipt.assignedDevice!.createdAt, clock.now());
      expect((await repo.loadPlants()).last.latestReading, isNull);
      expect(await repo.loadHistory(receipt.plantId), isEmpty);
      final connected = await connectFixtureDevice(repo, receipt.plantId);
      expect(connected.isConnected, isTrue);
      expect(connected.createdAt, receipt.assignedDevice!.createdAt);
      expect(connected.generationSequence, 0);
      expect((await repo.loadPlants()).last.latestReading, isNull);
    },
  );
  test(
    'unchanged connected assignment preserves state/revision/anchor and does not request a packet',
    () async {
      final before = (await repo.loadDevices()).single;
      final receipt = await repo.saveWithReceipt(
        draft('Rename', deviceId: before.id, connectDevice: true),
        plantId: 'plant-1',
        operationId: 'same',
      );
      final after = receipt.assignedDevice!;
      expect(receipt.needsConnectionPacket, isFalse);
      expect(
        (
          after.id,
          after.isConnected,
          after.revision,
          after.createdAt,
          after.lastAutoSlot,
          after.generationSequence,
        ),
        (
          before.id,
          true,
          before.revision,
          before.createdAt,
          before.lastAutoSlot,
          before.generationSequence,
        ),
      );
    },
  );
  test(
    'full name omission preserves; explicit null clears; plant copies retain fields',
    () async {
      PlantFormDraft named(Object? name) => PlantFormDraft(
        nickname: 'Bart',
        speciesName: 'Custom',
        avatar: PlantAvatarId.pothos,
        ranges: PlantAvatarId.pothos.hints,
        deviceId: 'device-1',
        fullName: name,
      );
      await repo.save(
        named('  Bartholomew Cornelius III  '),
        plantId: 'plant-1',
      );
      await repo.save(
        draft('Renamed', deviceId: 'device-1'),
        plantId: 'plant-1',
      );
      final p = (await repo.loadPlants()).single;
      expect(p.fullName, 'Bartholomew Cornelius III');
      expect(p.withoutDevice().fullName, p.fullName);
      expect(p.withReadings([]).fullName, p.fullName);
      expect(p.withReadings([]).profileRevision, p.profileRevision);
      await repo.save(named(null), plantId: p.id);
      expect((await repo.loadPlants()).single.fullName, isNull);
    },
  );
  for (final n in [25, 26]) {
    test('full-name grapheme boundary $n', () async {
      final value = List.filled(n, '👩🏽‍🌾').join();
      final form = PlantFormDraft(
        nickname: 'N',
        speciesName: 'S',
        avatar: PlantAvatarId.pothos,
        ranges: PlantAvatarId.pothos.hints,
        fullName: value,
      );
      if (n == 25) {
        final id = await repo.save(form);
        expect(
          (await repo.loadPlants()).firstWhere((p) => p.id == id).fullName,
          value,
        );
      } else {
        await expectLater(
          repo.save(form),
          throwsA(isA<PlantValidationError>()),
        );
        expect((await repo.loadPlants()).length, 1);
      }
    });
  }
  test(
    'two edit drafts compare profile revision atomically; sensor packets do not conflict',
    () async {
      final captured = await token('plant-1');
      await repo.commitReading(
        'plant-1',
        (await repo.loadDevices()).single,
        SensorReading(recordedAt: clock.now(), light: 600),
      );
      PlantFormDraft form(String name) => PlantFormDraft(
        nickname: name,
        speciesName: 'Custom',
        avatar: PlantAvatarId.pothos,
        ranges: PlantAvatarId.pothos.hints,
        deviceId: 'device-1',
        editToken: captured,
      );
      await repo.save(form('First'), plantId: 'plant-1');
      await expectLater(
        repo.save(form('Stale')),
        throwsA(anything),
      ); // Explicit ID guard below.
      await expectLater(
        repo.save(form('Stale'), plantId: 'plant-1'),
        throwsA(isA<PlantEditConflict>()),
      );
      expect((await repo.loadPlants()).single.nickname, 'First');
      expect((await repo.loadHistory('plant-1')).length, 2);
    },
  );
  test(
    'stale Delete cannot remove changed assignment or another owner; deleted Edit cannot resurrect',
    () async {
      final captured = await token('plant-1');
      await repo.save(draft('Unassigned'), plantId: 'plant-1');
      final other = await repo.save(draft('Other', deviceId: 'device-1'));
      await expectLater(
        repo.deletePlant(
          'plant-1',
          expected: captured,
          operationId: 'stale-delete',
        ),
        throwsA(isA<PlantEditConflict>()),
      );
      expect((await repo.loadDevices()).single.id, 'device-1');
      expect((await repo.loadAssignedDevices())[other]!.id, 'device-1');
      await repo.deletePlant('plant-1');
      await expectLater(
        repo.save(draft('Zombie'), plantId: 'plant-1'),
        throwsA(isA<PlantEditConflict>()),
      );
      expect((await repo.loadPlants()).single.id, other);
    },
  );
  test(
    'a selected device deleted mid-edit is rejected atomically without changing the plant',
    () async {
      final other = await repo.save(
        draft('Temporary owner', createDevice: true),
      );
      final selected = (await repo.loadAssignedDevices())[other]!;
      await repo.save(draft('Released'), plantId: other);
      final captured = await token('plant-1');
      await repo.save(draft('Reowned', deviceId: selected.id), plantId: other);
      await repo.deletePlant(other);
      await expectLater(
        repo.save(
          PlantFormDraft(
            nickname: 'Must not save',
            speciesName: 'Custom species',
            avatar: PlantAvatarId.pothos,
            ranges: PlantAvatarId.pothos.hints,
            deviceId: selected.id,
            editToken: captured,
          ),
          plantId: 'plant-1',
        ),
        throwsA(isA<PlantEditConflict>()),
      );
      expect((await repo.loadPlants()).single.nickname, 'Florence');
      expect((await repo.loadDevices()).single.id, 'device-1');
    },
  );
  test(
    'A to B shows no A data before B packet; failures/disconnect/unassign retain immutable history',
    () async {
      final original = (await repo.loadHistory('plant-1')).single;
      final holder = await repo.save(draft('B holder', createDevice: true));
      final b = (await repo.loadAssignedDevices())[holder]!;
      await repo.save(draft('B holder'), plantId: holder);
      await repo.save(draft('Florence', deviceId: b.id), plantId: 'plant-1');
      expect((await repo.loadPlants()).first.latestReading, isNull);
      expect((await repo.loadHistory('plant-1')).single.id, original.id);
      final connected = await connectFixtureDevice(repo, 'plant-1');
      expect(
        await repo.commitReading(
          'plant-1',
          connected,
          SensorReading(recordedAt: clock.now()),
        ),
        isFalse,
      );
      expect((await repo.loadPlants()).first.latestReading, isNull);
      clock.value = clock.now().add(const Duration(minutes: 2));
      expect(
        await repo.commitReading(
          'plant-1',
          connected,
          SensorReading(recordedAt: clock.now(), light: 777),
        ),
        isTrue,
      );
      final realB = (await repo.loadPlants()).first.latestReading!;
      expect(realB.sourceDeviceId, b.id);
      expect(realB.light, 777);
      await repo.setConnection(b.id, false);
      expect((await repo.loadPlants()).first.latestReading!.id, realB.id);
      expect(
        (await repo.loadPlants()).first.latestReading!.recordedAt,
        realB.recordedAt,
      );
      await repo.save(draft('Florence'), plantId: 'plant-1');
      expect((await repo.loadPlants()).first.latestReading, isNull);
      final history = await repo.loadHistory('plant-1');
      expect(history.map((r) => r.sourceDeviceId), [b.id, 'device-1']);
      expect(history.last.id, original.id);
      expect((await repo.loadDevices()).length, 2);
      final plan = await repo.database.rows(
        'EXPLAIN QUERY PLAN SELECT id FROM sensor_readings WHERE plant_id=? AND source_device_id=? ORDER BY recorded_at_ms DESC,id DESC LIMIT 1',
        ['plant-1', b.id],
      );
      expect(plan.toString(), contains('reading_current_source'));
    },
  );
  test(
    'operation identity replays exact committed Add without consuming IDs; changed request rejected',
    () async {
      final first = await repo.saveWithReceipt(
        draft('Once', createDevice: true),
        operationId: 'stable',
      );
      final replay = await repo.saveWithReceipt(
        draft('Once', createDevice: true),
        operationId: 'stable',
      );
      expect(replay.plantId, first.plantId);
      expect(replay.assignedDevice!.id, first.assignedDevice!.id);
      expect((await repo.loadPlants()).length, 2);
      expect((await repo.loadDevices()).length, 2);
      await expectLater(
        repo.saveWithReceipt(draft('Different'), operationId: 'stable'),
        throwsStateError,
      );
      final third = await repo.save(draft('Next', createDevice: true));
      expect(third, 'plant-3');
    },
  );
  test(
    'failed transaction rolls back device and operation receipt; retry is safe',
    () async {
      await repo.database.customStatement(
        "CREATE TRIGGER fail_save BEFORE INSERT ON plant_ranges BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(
        repo.saveWithReceipt(
          draft('Retry', createDevice: true),
          operationId: 'retry',
        ),
        throwsA(isA<PlantPersistenceFailure>()),
      );
      expect(await repo.findSaveReceipt('retry'), isNull);
      expect((await repo.loadDevices()).length, 1);
      await repo.database.customStatement('DROP TRIGGER fail_save');
      final result = await repo.saveWithReceipt(
        draft('Retry', createDevice: true),
        operationId: 'retry',
      );
      expect(result.plantId, 'plant-2');
      expect(result.assignedDevice!.id, 'device-2');
    },
  );
  test(
    'Delete journal shares transaction and exact replay cannot delete a replacement',
    () async {
      final expected = await token('plant-1');
      await repo.deletePlant(
        'plant-1',
        expected: expected,
        operationId: 'delete-once',
      );
      final replacement = await repo.save(
        draft('Replacement', createDevice: true),
      );
      await repo.deletePlant(
        'plant-1',
        expected: expected,
        operationId: 'delete-once',
      );
      expect(await repo.deletionCommitted('delete-once'), isTrue);
      expect((await repo.loadPlants()).single.id, replacement);
      expect((await repo.loadDevices()).single.name, 'ESP32-Sim01');
      expect((await repo.loadDevices()).single.id, 'device-2');
    },
  );

  for (final empty in [false, true]) {
    test(
      'native populated/empty v1 to v2 migration preserves all old values: empty=$empty',
      () async {
        final folder = await Directory.systemTemp.createTemp(
              'phase_d_migration_',
            ),
            file = File('${folder.path}/plants.sqlite');
        final legacy = PhaseCV1Database(NativeDatabase(file));
        final before = <String, List<Map<String, dynamic>>>{};
        const tables = [
          'app_meta',
          'id_counters',
          'devices',
          'plants',
          'plant_ranges',
          'sensor_readings',
        ];
        await populateVersionOne(legacy, clock.now(), empty: empty);
        for (final table in tables) {
          before[table] = await legacy.rows(
            'SELECT * FROM $table ORDER BY rowid',
          );
        }
        await legacy.close();
        var db = AppDatabase(NativeDatabase(file));
        try {
          final migrated = SqlitePlantRepository(db, clock: clock);
          await migrated.initialize();
          expect(
            (await db.rows('PRAGMA user_version')).single['user_version'],
            2,
          );
          for (final table in tables) {
            final after = (await db.rows(
              'SELECT * FROM $table ORDER BY rowid',
            )).map((row) => Map<String, dynamic>.from(row)).toList();
            if (table == 'plants') {
              for (final row in after) {
                expect(row.remove('full_name'), isNull);
                expect(row.remove('profile_revision'), 0);
              }
            }
            expect(after, before[table], reason: table);
          }
          expect((await migrated.loadPlants()).length, empty ? 0 : 2);
          await db.close();
          db = AppDatabase(NativeDatabase(file));
          final reopened = SqlitePlantRepository(db, clock: clock);
          await reopened.initialize();
          expect((await reopened.loadPlants()).length, empty ? 0 : 2);
          expect(
            (await db.rows(
              "SELECT next_value FROM id_counters WHERE kind='plant'",
            )).single['next_value'],
            empty ? 50 : 3,
          );
        } finally {
          await db.close();
          await folder.delete(recursive: true);
        }
      },
    );
  }
  test(
    'interrupted/failed migration rolls back additive columns and preserves v1 data for recovery',
    () async {
      final folder = await Directory.systemTemp.createTemp(
            'phase_d_migration_failure_',
          ),
          file = File('${folder.path}/plants.sqlite');
      var legacy = PhaseCV1Database(NativeDatabase(file));
      await populateVersionOne(legacy, clock.now());
      await legacy.customStatement(
        'CREATE VIEW plant_operations AS SELECT id FROM plants',
      );
      await legacy.close();
      final broken = AppDatabase(NativeDatabase(file));
      await expectLater(broken.rows('SELECT * FROM plants'), throwsA(anything));
      await broken.close();
      legacy = PhaseCV1Database(NativeDatabase(file));
      try {
        expect(
          (await legacy.rows('PRAGMA user_version')).single['user_version'],
          1,
        );
        expect(
          (await legacy.rows(
            'PRAGMA table_info(plants)',
          )).map((r) => r['name']),
          isNot(contains('full_name')),
        );
        expect((await legacy.rows('SELECT * FROM plants')).length, 2);
        expect((await legacy.rows('SELECT * FROM sensor_readings')).length, 2);
        await legacy.customStatement('DROP VIEW plant_operations');
      } finally {
        await legacy.close();
      }
      final recovered = SqlitePlantRepository(
        AppDatabase(NativeDatabase(file)),
        clock: clock,
      );
      try {
        await recovered.initialize();
        expect((await recovered.loadPlants()).length, 2);
      } finally {
        await recovered.close();
        await folder.delete(recursive: true);
      }
    },
  );
}
