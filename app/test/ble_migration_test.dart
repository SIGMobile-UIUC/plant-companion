import 'dart:io';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';

class LegacyV2Database extends AppDatabase {
  LegacyV2Database(super.executor);
  @override
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      // Exactly the pre-BLE schema, without the additive v3 statements.
      for (final sql in AppDatabase.schema.take(
        AppDatabase.schema.length - AppDatabase.upgradeV2ToV3.length,
      )) {
        await customStatement(sql);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys=ON');
    },
  );
}

void main() {
  test(
    'populated native v2 migrates to v3 without changing any existing row',
    () async {
      final dir = Directory.systemTemp.createTempSync('plant-v2-ble-'),
          file = File('${dir.path}/app.sqlite');
      final old = LegacyV2Database(NativeDatabase(file));
      final legacy = SqlitePlantRepository(old);
      await legacy.initialize();
      final tables = [
        'plants',
        'devices',
        'plant_ranges',
        'sensor_readings',
        'plant_operations',
        'id_counters',
        'app_meta',
      ];
      final before = {
        for (final table in tables)
          table: await old.rows('SELECT * FROM $table ORDER BY rowid'),
      };
      await old.close();
      final db = AppDatabase(NativeDatabase(file));
      try {
        final repo = SqlitePlantRepository(db);
        await repo.initialize();
        expect(
          (await db.rows('PRAGMA user_version')).single['user_version'],
          3,
        );
        for (final table in tables) {
          final after = (await db.rows(
            'SELECT * FROM $table ORDER BY rowid',
          )).map((r) => Map<String, dynamic>.from(r)).toList();
          if (table == 'devices') {
            for (final row in after) {
              expect(row.remove('kind'), 'simulated');
              expect(row.remove('ble_name'), isNull);
              expect(row.remove('platform_hint'), isNull);
            }
          }
          expect(after, before[table], reason: table);
        }
        expect(await db.rows('SELECT * FROM ble_records'), isEmpty);
        expect((await repo.loadPlants()).single.nickname, 'Florence');
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
}
