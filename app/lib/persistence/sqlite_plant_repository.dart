import 'dart:math' as math;
import 'dart:convert';
import '../models/device.dart';
import '../models/plant.dart';
import '../models/plant_avatar_id.dart';
import '../models/plant_form_draft.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';
import '../models/plant_commit.dart';
import '../services/clock.dart';
import '../services/plant_repository.dart';
import '../utils/sensor_units.dart';
import 'app_database.dart';

class SqlitePlantRepository implements PlantRepository {
  SqlitePlantRepository(this.database, {this.clock = const SystemClock()});
  final AppDatabase database;
  final Clock clock;
  static const historyWindow = Duration(days: 7);
  static const interval = Duration(minutes: 20);

  @override
  Future<void> initialize() async {
    await database.transaction(() async {
      final initialized = await database.rows(
        "SELECT value FROM app_meta WHERE key='initialized'",
      );
      if (initialized.isEmpty) {
        if ((await database.rows('SELECT id FROM plants')).isNotEmpty) {
          throw StateError(
            'Unrecognized database; refusing to overwrite plants.',
          );
        }
        final now = clock.now().toUtc();
        final seeded = await _save(
          PlantFormDraft(
            nickname: 'Florence',
            speciesName: 'Epipremnum aureum',
            avatar: PlantAvatarId.pothos,
            ranges: PlantAvatarId.pothos.hints,
            createDevice: true,
          ),
          null,
          now,
          operationId: 'initial-florence',
          seedConnection: true,
        );
        final id = seeded.plantId;
        final deviceId =
            (await database.rows('SELECT device_id FROM plants WHERE id=?', [
                  id,
                ])).single['device_id']
                as String;
        await _insertReading(
          id,
          deviceId,
          SensorReading(
            recordedAt: now,
            soilMoisture: 38,
            light: 280,
            temperature: fahrenheitToCelsius(75),
            humidity: 42,
          ),
          'seed',
          null,
        );
        await database.customStatement(
          "INSERT INTO app_meta VALUES ('initialized','1')",
        );
      }
      await _pruneAll();
    });
  }

  Future<String> _identity(String kind) async {
    await database.customStatement(
      'INSERT OR IGNORE INTO id_counters VALUES (?,1)',
      [kind],
    );
    final number =
        (await database.rows(
              'SELECT next_value FROM id_counters WHERE kind=?',
              [kind],
            )).single['next_value']
            as int;
    await database.customStatement(
      'UPDATE id_counters SET next_value=next_value+1 WHERE kind=?',
      [kind],
    );
    final suffix = number.toString().padLeft(kind == 'reading' ? 16 : 1, '0');
    return '$kind-$suffix';
  }

  @override
  Future<String> save(PlantFormDraft draft, {String? plantId}) async =>
      (await saveWithReceipt(
        draft,
        plantId: plantId,
        operationId: newPlantOperationId(),
      )).plantId;

  @override
  Future<PlantSaveReceipt?> findSaveReceipt(String operationId) async {
    final rows = await database.rows(
      'SELECT kind,result_json FROM plant_operations WHERE operation_id=?',
      [operationId],
    );
    if (rows.isEmpty) return null;
    if (rows.single['kind'] != 'save') {
      throw PlantOperationConflict();
    }
    return PlantSaveReceipt.fromJson(
      jsonDecode(rows.single['result_json'] as String) as Map<String, dynamic>,
    );
  }

  @override
  Future<PlantSaveReceipt> saveWithReceipt(
    PlantFormDraft draft, {
    String? plantId,
    required String operationId,
  }) async {
    draft.validate();
    final request = jsonEncode({'plantId': plantId, ...draft.toJson()});
    try {
      return await database.transaction(() async {
        final previous = await database.rows(
          'SELECT kind,request_json,result_json FROM plant_operations WHERE operation_id=?',
          [operationId],
        );
        if (previous.isNotEmpty) {
          final row = previous.single;
          if (row['kind'] != 'save' || row['request_json'] != request) {
            throw PlantOperationConflict();
          }
          return PlantSaveReceipt.fromJson(
            jsonDecode(row['result_json'] as String) as Map<String, dynamic>,
          );
        }
        final receipt = await _save(
          draft,
          plantId,
          clock.now().toUtc(),
          operationId: operationId,
        );
        await database.customStatement(
          'INSERT INTO plant_operations(operation_id,kind,plant_id,request_json,result_json) VALUES (?,?,?,?,?)',
          [
            operationId,
            'save',
            receipt.plantId,
            request,
            jsonEncode(receipt.toJson()),
          ],
        );
        return receipt;
      });
    } on Exception catch (error) {
      // Domain/ownership errors are Error subtypes and remain identifiable.
      // Exceptions from this SQLite operation retain their underlying cause.
      throw PlantPersistenceFailure(error);
    }
  }

  Future<PlantSaveReceipt> _save(
    PlantFormDraft draft,
    String? plantId,
    DateTime now, {
    required String operationId,
    bool seedConnection = false,
  }) async {
    draft.validate();
    Map<String, dynamic>? old;
    if (plantId != null) {
      final rows = await database.rows('SELECT * FROM plants WHERE id=?', [
        plantId,
      ]);
      if (rows.isEmpty) throw PlantEditConflict();
      old = rows.single;
    }
    final previousDevice = await _deviceById(old?['device_id'] as String?);
    if (draft.editToken != null) {
      if (old == null) throw PlantEditConflict();
      _checkEditToken(old, previousDevice, draft.editToken!);
    }
    String? deviceId = draft.deviceId;
    if (draft.createDevice) {
      deviceId = await _identity('device');
      final count =
          (await database.rows('SELECT COUNT(*) AS n FROM devices')).single['n']
              as int;
      await database.customStatement(
        'INSERT INTO devices(id,display_ordinal,created_at_ms,connected) VALUES (?,?,?,?)',
        [
          deviceId,
          count + 1,
          now.millisecondsSinceEpoch,
          seedConnection ? 1 : 0,
        ],
      );
    } else if (deviceId != null) {
      if ((await database.rows('SELECT id FROM devices WHERE id=?', [
        deviceId,
      ])).isEmpty) {
        throw PlantEditConflict();
      }
      final owner = await database.rows(
        'SELECT id FROM plants WHERE device_id=?',
        [deviceId],
      );
      if (owner.isNotEmpty && owner.single['id'] != plantId) {
        throw DeviceAssignmentConflict();
      }
    }
    final id = plantId ?? await _identity('plant');
    if (old != null &&
        old['device_id'] != deviceId &&
        old['device_id'] != null) {
      await database.customStatement(
        'UPDATE devices SET revision=revision+1 WHERE id=?',
        [old['device_id']],
      );
    }
    if ((old == null || old['device_id'] != deviceId) && deviceId != null) {
      await database.customStatement(
        'UPDATE devices SET revision=revision+1,connected=? WHERE id=?',
        [seedConnection ? 1 : 0, deviceId],
      );
    }
    final time = now.millisecondsSinceEpoch;
    if (old == null) {
      final order = (await database.rows(
        'SELECT COALESCE(MAX(display_order),0)+1 AS n FROM plants',
      )).single['n'];
      await database.customStatement(
        'INSERT INTO plants(id,nickname,species,avatar_id,device_id,created_at_ms,updated_at_ms,display_order,full_name,profile_revision) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          draft.nickname.trim(),
          draft.speciesName.trim(),
          draft.avatar.name,
          deviceId,
          time,
          time,
          order,
          _normalizedFullName(draft.fullName),
          0,
        ],
      );
    } else {
      await database.customStatement(
        'UPDATE plants SET nickname=?,species=?,avatar_id=?,device_id=?,updated_at_ms=?,full_name=?,profile_revision=profile_revision+1 WHERE id=?',
        [
          draft.nickname.trim(),
          draft.speciesName.trim(),
          draft.avatar.name,
          deviceId,
          time,
          draft.updatesFullName
              ? _normalizedFullName(draft.fullName)
              : old['full_name'],
          id,
        ],
      );
      await database.customStatement(
        'DELETE FROM plant_ranges WHERE plant_id=?',
        [id],
      );
    }
    for (final metric in SensorMetric.values) {
      final range = draft.ranges[metric]!;
      await database.customStatement(
        'INSERT INTO plant_ranges VALUES (?,?,?,?)',
        [id, metric.name, range.minimum, range.maximum],
      );
    }
    return PlantSaveReceipt(
      operationId: operationId,
      plantId: id,
      previousDevice: previousDevice,
      assignedDevice: await _deviceById(deviceId),
      deviceCreated: draft.createDevice,
      connectionRequested: draft.connectDevice,
    );
  }

  static String? _normalizedFullName(String? value) =>
      value?.trim().isEmpty != false ? null : value!.trim();
  Future<Device?> _deviceById(String? id) async {
    if (id == null) return null;
    final rows = await database.rows('SELECT * FROM devices WHERE id=?', [id]);
    return rows.isEmpty ? null : _device(rows.single);
  }

  void _checkEditToken(
    Map<String, dynamic> plant,
    Device? device,
    PlantEditToken token,
  ) {
    if (plant['profile_revision'] != token.profileRevision ||
        plant['device_id'] != token.deviceId ||
        device?.revision != token.deviceRevision) {
      throw PlantEditConflict();
    }
  }

  @override
  Future<List<Device>> loadDevices() async => (await database.rows(
    'SELECT * FROM devices ORDER BY display_ordinal',
  )).map(_device).toList();

  @override
  Future<Map<String, Device>> loadAssignedDevices() async => {
    for (final row in await database.rows(
      'SELECT d.*,p.id AS plant_id FROM devices d JOIN plants p ON p.device_id=d.id',
    ))
      row['plant_id'] as String: _device(row),
  };

  @override
  Future<DeviceReadingContext?> loadAcquisitionContext(String plantId) async {
    final rows = await database.rows(
      '''
      SELECT d.*,p.id AS plant_id,p.profile_revision AS plant_profile_revision,
             l.minimum AS light_minimum,l.maximum AS light_maximum,
             m.minimum AS moisture_minimum,m.maximum AS moisture_maximum,
             t.minimum AS temperature_minimum,t.maximum AS temperature_maximum,
             h.minimum AS humidity_minimum,h.maximum AS humidity_maximum,
             r.id AS previous_packet_id,r.source_device_id,r.recorded_at_ms,
             r.soil_moisture,r.light_lux,r.temperature_c,r.humidity,r.origin
      FROM plants p JOIN devices d ON d.id=p.device_id
      JOIN plant_ranges l ON l.plant_id=p.id AND l.metric='light'
      JOIN plant_ranges m ON m.plant_id=p.id AND m.metric='soilMoisture'
      JOIN plant_ranges t ON t.plant_id=p.id AND t.metric='temperature'
      JOIN plant_ranges h ON h.plant_id=p.id AND h.metric='humidity'
      LEFT JOIN sensor_readings r ON r.rowid=(
        SELECT rowid FROM sensor_readings WHERE source_device_id=d.id
        ORDER BY rowid DESC LIMIT 1)
      WHERE p.id=?
    ''',
      [plantId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final previous = row['previous_packet_id'] == null
        ? null
        : _reading({...row, 'id': row['previous_packet_id']});
    return DeviceReadingContext(
      _device(row),
      previous,
      plantId: row['plant_id'] as String,
      profileRevision: row['plant_profile_revision'] as int,
      idealRanges: {
        SensorMetric.light: TargetRange(
          (row['light_minimum'] as num).toDouble(),
          (row['light_maximum'] as num).toDouble(),
        ),
        for (final (metric, prefix) in [
          (SensorMetric.soilMoisture, 'moisture'),
          (SensorMetric.temperature, 'temperature'),
          (SensorMetric.humidity, 'humidity'),
        ])
          metric: TargetRange(
            (row['${prefix}_minimum'] as num).toDouble(),
            (row['${prefix}_maximum'] as num).toDouble(),
          ),
      },
    );
  }

  Device _device(Map<String, dynamic> row) {
    final ordinal = row['display_ordinal'] as int;
    return Device(
      id: row['id'] as String,
      name: Device.displayName(ordinal),
      displayOrdinal: ordinal,
      isConnected: row['connected'] == 1,
      createdAt: _date(row['created_at_ms']),
      revision: row['revision'] as int,
      lastAutoSlot: row['last_auto_slot'] as int,
      generationSequence: row['generation_sequence'] as int,
    );
  }

  static DateTime _date(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis as int, isUtc: true);

  @override
  Future<List<Plant>> loadPlants() => database.transaction(() async {
    final rows = await database.rows(
      'SELECT * FROM plants ORDER BY display_order,id',
    );
    final rangesByPlant = <String, Map<SensorMetric, TargetRange>>{};
    for (final r in await database.rows('SELECT * FROM plant_ranges')) {
      (rangesByPlant[r['plant_id'] as String] ??= {})[SensorMetric.values
          .byName(r['metric'] as String)] = TargetRange(
        (r['minimum'] as num).toDouble(),
        (r['maximum'] as num).toDouble(),
      );
    }
    // One indexed lookup per plant inside SQLite; no retained-history transfer.
    final latest = {
      for (final r in await database.rows('''
        SELECT r.* FROM plants p JOIN sensor_readings r ON r.id=(
          SELECT id FROM sensor_readings WHERE plant_id=p.id AND source_device_id=p.device_id
          ORDER BY recorded_at_ms DESC,id DESC LIMIT 1)
      '''))
        r['plant_id'] as String: _reading(r),
    };
    final result = <Plant>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final ranges = rangesByPlant[id] ?? {};
      if (ranges.length != SensorMetric.values.length) {
        throw StateError('Incomplete ranges: $id');
      }
      result.add(
        Plant(
          id: id,
          nickname: row['nickname'] as String,
          speciesName: row['species'] as String,
          avatar: PlantAvatarId.values.byName(row['avatar_id'] as String),
          profile: PlantProfile(
            id: 'custom',
            plantType: row['species'] as String,
            ranges: Map.unmodifiable(ranges),
          ),
          deviceId: row['device_id'] as String?,
          readings: List.unmodifiable([if (latest[id] != null) latest[id]!]),
          createdAt: _date(row['created_at_ms']),
          updatedAt: _date(row['updated_at_ms']),
          displayOrder: row['display_order'] as int,
          fullName: row['full_name'] as String?,
          profileRevision: row['profile_revision'] as int,
        ),
      );
    }
    return List.unmodifiable(result);
  });

  @override
  Future<List<SensorReading>> loadHistory(
    String plantId,
  ) async => List.unmodifiable(
    (await database.rows(
      'SELECT * FROM sensor_readings WHERE plant_id=? ORDER BY recorded_at_ms DESC,id DESC',
      [plantId],
    )).map(_reading),
  );

  SensorReading _reading(Map<String, dynamic> r) => SensorReading(
    id: r['id'] as String,
    sourceDeviceId: r['source_device_id'] as String,
    origin: r['origin'] as String,
    recordedAt: _date(r['recorded_at_ms']),
    soilMoisture: (r['soil_moisture'] as num?)?.toDouble(),
    light: (r['light_lux'] as num?)?.toDouble(),
    temperature: (r['temperature_c'] as num?)?.toDouble(),
    humidity: (r['humidity'] as num?)?.toDouble(),
  );

  @override
  Future<void> deletePlant(
    String plantId, {
    PlantEditToken? expected,
    String? operationId,
  }) => database.transaction(() async {
    final request = jsonEncode({
      'plantId': plantId,
      'expected': expected?.toJson(),
    });
    if (operationId != null) {
      final previous = await database.rows(
        'SELECT kind,request_json FROM plant_operations WHERE operation_id=?',
        [operationId],
      );
      if (previous.isNotEmpty) {
        if (previous.single['kind'] != 'delete' ||
            previous.single['request_json'] != request) {
          throw PlantOperationConflict();
        }
        return;
      }
    }
    final rows = await database.rows('SELECT * FROM plants WHERE id=?', [
      plantId,
    ]);
    if (rows.isEmpty) {
      if (expected != null) throw PlantEditConflict();
      return;
    }
    if (expected != null) {
      _checkEditToken(
        rows.single,
        await _deviceById(rows.single['device_id'] as String?),
        expected,
      );
    }
    final deviceId = rows.single['device_id'];
    await database.customStatement('DELETE FROM plants WHERE id=?', [plantId]);
    if (deviceId != null) {
      await database.customStatement('DELETE FROM devices WHERE id=?', [
        deviceId,
      ]);
      final surviving = await database.rows(
        'SELECT id FROM devices ORDER BY display_ordinal',
      );
      final maxOrdinal =
          (await database.rows(
                'SELECT COALESCE(MAX(display_ordinal),0) AS n FROM devices',
              )).single['n']
              as int;
      // Move into a disjoint positive range before compacting UNIQUE ordinals.
      await database.customStatement(
        'UPDATE devices SET display_ordinal=display_ordinal+?',
        [maxOrdinal + 1],
      );
      for (var i = 0; i < surviving.length; i++) {
        await database.customStatement(
          'UPDATE devices SET display_ordinal=? WHERE id=?',
          [i + 1, surviving[i]['id']],
        );
      }
    }
    if (operationId != null) {
      await database.customStatement(
        'INSERT INTO plant_operations(operation_id,kind,plant_id,request_json,result_json) VALUES (?,?,?,?,?)',
        [operationId, 'delete', plantId, request, '{}'],
      );
    }
  });

  @override
  Future<bool> deletionCommitted(
    String operationId,
  ) async => (await database.rows(
    "SELECT operation_id FROM plant_operations WHERE operation_id=? AND kind='delete'",
    [operationId],
  )).isNotEmpty;

  @override
  Future<void> setConnection(String deviceId, bool connected) async {
    await database.customStatement(
      'UPDATE devices SET connected=?,revision=revision+1 WHERE id=?',
      [connected ? 1 : 0, deviceId],
    );
  }

  @override
  Future<Device?> reconnectAssigned(
    String plantId,
    Device captured,
  ) => database.transaction(() async {
    final rows = await database.rows(
      'SELECT d.* FROM devices d JOIN plants p ON p.device_id=d.id WHERE p.id=? AND d.id=?',
      [plantId, captured.id],
    );
    if (rows.isEmpty || captured.isConnected) return null;
    final current = _device(rows.single);
    if (current.isConnected ||
        current.revision != captured.revision ||
        current.generationSequence != captured.generationSequence) {
      return null;
    }
    await database.customStatement(
      'UPDATE devices SET connected=1,revision=revision+1 WHERE id=?',
      [captured.id],
    );
    return _device(
      (await database.rows('SELECT * FROM devices WHERE id=?', [
        captured.id,
      ])).single,
    );
  });

  @override
  Future<bool> commitReading(
    String plantId,
    Device captured,
    SensorReading reading, {
    String origin = 'manual',
    int? autoSlot,
    int? expectedProfileRevision,
  }) async {
    final values = SensorMetric.values.map(reading.valueFor).toList();
    if (values.any((v) => v != null && !v.isFinite)) {
      throw ArgumentError('Sensor values must be finite.');
    }
    if (values.every((v) => v == null)) return false;
    return database.transaction(() async {
      final rows = await database.rows(
        'SELECT d.*,p.profile_revision AS plant_profile_revision FROM devices d JOIN plants p ON p.device_id=d.id WHERE p.id=? AND d.id=?',
        [plantId, captured.id],
      );
      if (rows.isEmpty) return false;
      final current = _device(rows.single);
      if (expectedProfileRevision != null &&
          rows.single['plant_profile_revision'] != expectedProfileRevision) {
        return false;
      }
      if (!current.isConnected ||
          current.revision != captured.revision ||
          current.generationSequence != captured.generationSequence) {
        return false;
      }
      if (origin == 'automatic' &&
          (autoSlot == null || autoSlot <= current.lastAutoSlot)) {
        return false;
      }
      await _insertReading(plantId, current.id, reading, origin, autoSlot);
      var slot = current.lastAutoSlot;
      if (origin == 'automatic') slot = autoSlot!;
      if (origin == 'connection') {
        slot = math.max(slot, slotAt(current, reading.recordedAt));
      }
      await database.customStatement(
        'UPDATE devices SET generation_sequence=generation_sequence+1,last_auto_slot=? WHERE id=?',
        [slot, current.id],
      );
      await _prune(plantId);
      return true;
    });
  }

  static int slotAt(Device device, DateTime now) => math.max(
    0,
    now.toUtc().difference(device.createdAt!).inMilliseconds ~/
        interval.inMilliseconds,
  );

  Future<void> _insertReading(
    String plantId,
    String deviceId,
    SensorReading r,
    String origin,
    int? autoSlot,
  ) async {
    await database.customStatement(
      'INSERT INTO sensor_readings VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        await _identity('reading'),
        plantId,
        deviceId,
        r.recordedAt.toUtc().millisecondsSinceEpoch,
        r.soilMoisture,
        r.light,
        r.temperature,
        r.humidity,
        origin,
        autoSlot,
      ],
    );
  }

  Future<void> _prune(String plantId) => database.customStatement(
    '''DELETE FROM sensor_readings WHERE plant_id=? AND recorded_at_ms <
       (SELECT MAX(recorded_at_ms) FROM sensor_readings WHERE plant_id=?) - ?''',
    [plantId, plantId, historyWindow.inMilliseconds],
  );

  Future<void> _pruneAll() => database.customStatement(
    '''DELETE FROM sensor_readings WHERE id IN (
      SELECT packet.id FROM sensor_readings packet JOIN (
        SELECT plant_id,MAX(recorded_at_ms) AS latest FROM sensor_readings
        GROUP BY plant_id
      ) cutoff ON cutoff.plant_id=packet.plant_id
      WHERE packet.recorded_at_ms < cutoff.latest-?)''',
    [historyWindow.inMilliseconds],
  );

  @override
  Future<void> pruneHistory() => database.transaction(_pruneAll);
  @override
  Future<void> close() => database.close();
}
