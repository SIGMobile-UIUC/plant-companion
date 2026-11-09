import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'fixtures/foundation_fixtures.dart';

class CountingDatabase extends AppDatabase {
  CountingDatabase() : super(NativeDatabase.memory());
  int reads = 0;
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) {
    reads++;
    return super.rows(sql, args);
  }
}

void main() {
  late MutableClock clock;
  late SqlitePlantRepository repo;
  setUp(() async {
    clock = MutableClock(DateTime.utc(2026, 6, 20, 10));
    repo = memoryRepository(clock);
    await repo.initialize();
  });
  tearDown(() => repo.close());

  test(
    'list uses three reads and latest packet only; history stays complete',
    () async {
      final db = CountingDatabase();
      final measured = SqlitePlantRepository(db, clock: clock);
      try {
        await measured.initialize();
        for (var i = 0; i < 20; i++) {
          final device = (await measured.loadDevices()).single;
          await measured.commitReading(
            'plant-1',
            device,
            SensorReading(recordedAt: clock.now(), light: 500 + i.toDouble()),
          );
        }
        final empty = await measured.save(draft('No packet'));
        db.reads = 0;
        final plants = await measured.loadPlants();
        expect(db.reads, 3);
        expect(plants.first.readings, hasLength(1));
        // Equal packet times resolve by persisted ID; partial packets are not
        // filled from an earlier packet and no data is silently fabricated.
        expect(plants.first.latestReading!.light, 519);
        expect(plants.first.latestReading!.soilMoisture, isNull);
        expect(plants.last.latestReading, isNull);
        expect(await measured.loadHistory(empty), isEmpty);
        final history = await measured.loadHistory('plant-1');
        expect(history, hasLength(21));
        expect(history.first.id, plants.first.latestReading!.id);
        expect(history.last.origin, 'seed');
        db.reads = 0;
        expect((await measured.loadAssignedDevices()).keys, ['plant-1']);
        expect(db.reads, 1);
        final plan = await db.rows(
          '''EXPLAIN QUERY PLAN
        SELECT id FROM sensor_readings WHERE plant_id=?
        ORDER BY recorded_at_ms DESC,id DESC LIMIT 1''',
          ['plant-1'],
        );
        expect(plan.toString(), contains('reading_latest'));
      } finally {
        await measured.close();
      }
    },
  );

  test(
    'one actual-time Florence seed, no duplicate after initialization',
    () async {
      await repo.initialize();
      final p = (await repo.loadPlants()).single;
      final d = (await repo.loadDevices()).single;
      expect(p.nickname, 'Florence');
      expect(p.speciesName, 'Epipremnum aureum');
      expect(p.latestReading!.recordedAt, clock.now());
      expect(p.latestReading!.soilMoisture, 38);
      expect(p.latestReading!.light, 280);
      expect(p.latestReading!.temperature, closeTo(23.8888888889, 1e-8));
      expect(d.createdAt, clock.now());
      expect(d.name, 'ESP32-Sim01');
      expect(d.lastAutoSlot, 0);
    },
  );

  test(
    'draft cancellation consumes no IDs or labels; failed save rolls back',
    () async {
      draft(
        'Abandoned',
        createDevice: true,
      ); // No persistence command on cancel.
      final first = await repo.save(draft('Second', createDevice: true));
      expect(first, 'plant-2');
      expect((await repo.loadDevices()).last.name, 'ESP32-Sim02');
      await repo.database.customStatement(
        "CREATE TRIGGER reject_range BEFORE INSERT ON plant_ranges BEGIN SELECT RAISE(ABORT,'failure'); END",
      );
      await expectLater(
        repo.save(draft('Rejected', createDevice: true)),
        throwsA(anything),
      );
      expect((await repo.loadPlants()).length, 2);
      expect((await repo.loadDevices()).length, 2);
      await repo.database.customStatement('DROP TRIGGER reject_range');
      await repo.save(draft('Third', createDevice: true));
      expect((await repo.loadDevices()).last.id, 'device-3');
      expect((await repo.loadDevices()).last.name, 'ESP32-Sim03');
    },
  );

  test(
    'delete atomically cascades only selected plant and compacts names, not identities',
    () async {
      final second = await repo.save(draft('Second', createDevice: true));
      final third = await repo.save(draft('Third', createDevice: true));
      final before = await repo.loadDevices();
      await repo.deletePlant('plant-1');
      expect((await repo.loadPlants()).map((p) => p.id), [second, third]);
      final after = await repo.loadDevices();
      expect(after.map((d) => d.id), [before[1].id, before[2].id]);
      expect(after.map((d) => d.name), ['ESP32-Sim01', 'ESP32-Sim02']);
      expect(after[0].createdAt, before[1].createdAt);
      expect(after[0].revision, before[1].revision);
      expect(
        await repo.database.rows(
          "SELECT * FROM plant_ranges WHERE plant_id='plant-1'",
        ),
        isEmpty,
      );
      expect(
        await repo.database.rows(
          "SELECT * FROM sensor_readings WHERE plant_id='plant-1'",
        ),
        isEmpty,
      );
      await repo.deletePlant(second);
      await repo.deletePlant(third);
      await repo.initialize();
      expect(await repo.loadPlants(), isEmpty); // Florence is never recreated.
      await repo.save(draft('After deletion', createDevice: true));
      expect((await repo.loadDevices()).single.name, 'ESP32-Sim01');
      expect((await repo.loadDevices()).single.id, 'device-4');
    },
  );

  test(
    'delete failure rolls back plant, ranges, packets, device and labels',
    () async {
      await repo.database.customStatement(
        "CREATE TRIGGER reject_device_delete BEFORE DELETE ON devices BEGIN SELECT RAISE(ABORT,'failure'); END",
      );
      await expectLater(repo.deletePlant('plant-1'), throwsA(anything));
      expect((await repo.loadPlants()).single.readings.length, 1);
      expect((await repo.loadDevices()).single.name, 'ESP32-Sim01');
      expect(
        (await repo.database.rows('SELECT * FROM plant_ranges')).length,
        4,
      );
    },
  );

  test(
    'history of another plant can reference a device deleted with its new owner',
    () async {
      final original = (await repo.loadPlants()).single;
      final device = (await repo.loadDevices()).single;
      await repo.save(draft(original.nickname), plantId: original.id);
      final next = await repo.save(draft('New owner', deviceId: device.id));
      await repo.deletePlant(next);
      expect(await repo.loadDevices(), isEmpty);
      final survivor = (await repo.loadPlants()).single;
      expect(survivor.latestReading, isNull);
      expect(
        (await repo.loadHistory(survivor.id)).single.sourceDeviceId,
        device.id,
      );
      expect(survivor.deviceId, isNull);
    },
  );

  test(
    'seven-day cutoff is inclusive, anchored to latest packet, not November now',
    () async {
      final other = await repo.save(draft('Other', createDevice: true));
      await connectFixtureDevice(repo, other);
      final time = clock.now();
      Future<void> append(String id, DateTime at) async {
        final plant = (await repo.loadPlants()).firstWhere((p) => p.id == id);
        final device = (await repo.loadDevices()).firstWhere(
          (d) => d.id == plant.deviceId,
        );
        expect(
          await repo.commitReading(
            id,
            device,
            SensorReading(recordedAt: at, light: 450),
          ),
          isTrue,
        );
      }

      await append(
        'plant-1',
        time.subtract(const Duration(days: 7, milliseconds: 1)),
      );
      await append('plant-1', time.subtract(const Duration(days: 7)));
      await append(other, time);
      expect((await repo.loadHistory('plant-1')).length, 2);
      clock.value = DateTime.utc(2026, 11, 4);
      await repo.pruneHistory();
      expect((await repo.loadHistory('plant-1')).length, 2);
      await append('plant-1', clock.now());
      final plants = await repo.loadPlants();
      expect((await repo.loadHistory('plant-1')).length, 1);
      expect((await repo.loadHistory(other)).single.recordedAt, time);
      expect(plants.first.latestReading!.recordedAt, clock.now());
    },
  );

  test('device ownership conflict leaves both plants unchanged', () async {
    await expectLater(
      repo.save(draft('Conflict', deviceId: 'device-1')),
      throwsStateError,
    );
    expect((await repo.loadPlants()).length, 1);
    final id = await repo.save(draft('Separate'));
    final updated = await repo.save(draft('Custom edit'), plantId: id);
    expect(updated, id);
    expect((await repo.loadPlants()).length, 2);
    expect((await repo.loadPlants()).last.speciesName, 'Majikium flowerium');
  });

  test(
    'file-backed restart preserves edits and intentional empty database',
    () async {
      final temp = await Directory.systemTemp.createTemp('plant_companion_');
      final file = File('${temp.path}/plants.sqlite');
      var disk = SqlitePlantRepository(
        AppDatabase(NativeDatabase(file)),
        clock: clock,
      );
      try {
        await disk.initialize();
        await disk.save(
          draft('Changed', deviceId: 'device-1'),
          plantId: 'plant-1',
        );
        await disk.commitReading(
          'plant-1',
          (await disk.loadDevices()).single,
          SensorReading(
            recordedAt: clock.now().add(const Duration(minutes: 1)),
            light: 600,
          ),
        );
        await disk.close();
        disk = SqlitePlantRepository(
          AppDatabase(NativeDatabase(file)),
          clock: clock,
        );
        await disk.initialize();
        expect((await disk.loadPlants()).single.nickname, 'Changed');
        expect((await disk.loadPlants()).single.readings, hasLength(1));
        expect((await disk.loadHistory('plant-1')).length, 2);
        expect((await disk.loadHistory('plant-1')).last.origin, 'seed');
        await disk.deletePlant('plant-1');
        await disk.close();
        disk = SqlitePlantRepository(
          AppDatabase(NativeDatabase(file)),
          clock: clock,
        );
        await disk.initialize();
        expect(await disk.loadPlants(), isEmpty);
      } finally {
        await disk.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
