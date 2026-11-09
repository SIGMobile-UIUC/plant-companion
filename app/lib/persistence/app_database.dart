import 'package:drift/drift.dart';

/// Explicit SQLite schema: no SQL or platform branching leaks into widgets.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in schema) {
        await customStatement(statement);
      }
    },
    onUpgrade: (_, from, to) async {
      if (from != 1 || to != 2) {
        throw StateError(
          'No migration from $from to $to. Existing data is preserved.',
        );
      }
      await transaction(() async {
        for (final statement in upgradeV1ToV2) {
          await customStatement(statement);
        }
      });
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Additive read index for existing v2 databases; no data/schema reset.
      await customStatement(sourceReadingIndex);
    },
  );

  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async => (await customSelect(
    sql,
    variables: args.map((v) => Variable(v)).toList(),
  ).get()).map((r) => r.data).toList();

  static const schema = [
    'CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'CREATE TABLE id_counters (kind TEXT PRIMARY KEY, next_value INTEGER NOT NULL CHECK(next_value > 0))',
    '''CREATE TABLE devices (
      id TEXT PRIMARY KEY,
      display_ordinal INTEGER NOT NULL UNIQUE CHECK(display_ordinal > 0),
      created_at_ms INTEGER NOT NULL,
      connected INTEGER NOT NULL CHECK(connected IN (0,1)),
      revision INTEGER NOT NULL DEFAULT 0,
      last_auto_slot INTEGER NOT NULL DEFAULT 0 CHECK(last_auto_slot >= 0),
      generation_sequence INTEGER NOT NULL DEFAULT 0 CHECK(generation_sequence >= 0))''',
    '''CREATE TABLE plants (
      id TEXT PRIMARY KEY, nickname TEXT NOT NULL CHECK(length(trim(nickname)) > 0),
      species TEXT NOT NULL CHECK(length(trim(species)) > 0),
      avatar_id TEXT NOT NULL CHECK(avatar_id IN ('pothos','snakePlant','peaceLily')),
      device_id TEXT UNIQUE REFERENCES devices(id) ON DELETE RESTRICT,
      created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL,
      display_order INTEGER NOT NULL,
      full_name TEXT,
      profile_revision INTEGER NOT NULL DEFAULT 0 CHECK(profile_revision >= 0))''',
    '''CREATE TABLE plant_ranges (
      plant_id TEXT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
      metric TEXT NOT NULL CHECK(metric IN ('soilMoisture','light','temperature','humidity')),
      minimum REAL NOT NULL, maximum REAL NOT NULL CHECK(minimum < maximum),
      PRIMARY KEY(plant_id,metric),
      CHECK(metric NOT IN ('soilMoisture','humidity') OR (minimum >= 0 AND maximum <= 100)),
      CHECK(metric != 'light' OR (minimum >= 0 AND maximum <= 200000)),
      CHECK(metric != 'temperature' OR (minimum >= -50 AND maximum <= 100)))''',
    // Historical source identity deliberately survives deletion of the live device.
    '''CREATE TABLE sensor_readings (
      id TEXT PRIMARY KEY, plant_id TEXT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
      source_device_id TEXT NOT NULL, recorded_at_ms INTEGER NOT NULL,
      soil_moisture REAL, light_lux REAL, temperature_c REAL, humidity REAL,
      origin TEXT NOT NULL CHECK(origin IN ('seed','manual','automatic','connection')),
      auto_slot INTEGER,
      CHECK((origin = 'automatic' AND auto_slot IS NOT NULL AND auto_slot >= 1)
         OR (origin != 'automatic' AND auto_slot IS NULL)))''',
    'CREATE INDEX reading_latest ON sensor_readings(plant_id, recorded_at_ms DESC, id DESC)',
    'CREATE UNIQUE INDEX reading_slot ON sensor_readings(source_device_id, auto_slot) WHERE auto_slot IS NOT NULL',
    operationTable,
    currentSourceIndex,
    sourceReadingIndex,
  ];
  static const sourceReadingIndex =
      'CREATE INDEX IF NOT EXISTS reading_by_device ON sensor_readings(source_device_id)';
  static const operationTable = '''CREATE TABLE plant_operations (
    operation_id TEXT PRIMARY KEY,kind TEXT NOT NULL CHECK(kind IN ('save','delete')),
    plant_id TEXT NOT NULL,request_json TEXT NOT NULL,result_json TEXT NOT NULL)''';
  static const currentSourceIndex =
      'CREATE INDEX reading_current_source ON sensor_readings(plant_id,source_device_id,recorded_at_ms DESC,id DESC)';
  static const upgradeV1ToV2 = [
    'ALTER TABLE plants ADD COLUMN full_name TEXT',
    'ALTER TABLE plants ADD COLUMN profile_revision INTEGER NOT NULL DEFAULT 0 CHECK(profile_revision >= 0)',
    operationTable,
    currentSourceIndex,
  ];
}
