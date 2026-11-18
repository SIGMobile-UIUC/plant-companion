part of 'sqlite_plant_repository.dart';

class BleSyncSnapshot {
  const BleSyncSnapshot(
    this.plantId,
    this.device,
    this.profileRevision,
    this.streamId,
    this.generation,
    this.cursor,
    this.floor,
    this.pending,
    this.gap,
  );
  final String plantId;
  final Device device;
  final int profileRevision, streamId, generation, cursor, floor;
  final BigInt? pending;
  final bool gap;
}

SensorReading _bleReading(Map<String, dynamic> r) => SensorReading(
  id: '${r['device_id']}:${r['stream_id']}:${r['sequence']}',
  sourceDeviceId: r['device_id'] as String,
  origin: switch (r['kind']) {
    1 => 'ble_startup',
    2 => 'ble_scheduled',
    _ => 'ble_manual',
  },
  recordedAt: DateTime.fromMillisecondsSinceEpoch(
    r['measured_at_ms'] as int? ?? 0,
    isUtc: true,
  ),
  timestampKnown: r['measured_at_ms'] != null,
  timeQuality: r['time_quality'] as String,
  sequence: r['sequence'] as int,
  bootId: r['boot_id'] as int,
  soilMoisture: (r['moisture'] as num?)?.toDouble(),
  temperature: (r['temperature'] as num?)?.toDouble(),
  humidity: (r['humidity'] as num?)?.toDouble(),
  light: (r['light'] as num?)?.toDouble(),
);

/// Physical storage is additive; legacy simulator packets/receipts stay intact.
extension BlePersistence on SqlitePlantRepository {
  Future<BleSyncSnapshot> beginBleSync(
    String plantId,
    Device device,
    BleDeviceInfo info,
  ) => database.transaction(() async {
    if (!device.isPhysical || info.id != device.id) {
      throw StateError('BLE identity mismatch.');
    }
    final owner = await database.rows(
      'SELECT p.profile_revision,d.revision FROM plants p JOIN devices d ON d.id=p.device_id WHERE p.id=? AND d.id=? AND d.kind=\'physical\'',
      [plantId, device.id],
    );
    if (owner.isEmpty || owner.single['revision'] != device.revision) {
      throw StateError('Device assignment changed.');
    }
    final rows = await database.rows(
      'SELECT * FROM ble_sync_state WHERE device_id=?',
      [device.id],
    );
    final old = rows.isEmpty ? null : rows.single;
    final changedStream = old != null && old['stream_id'] != info.streamId;
    final changedOwner = old != null && old['owner_id'] != plantId;
    final generation = old == null
        ? 1
        : (old['generation'] as int) + (changedStream ? 1 : 0);
    final cursor = old == null || changedStream ? 0 : old['cursor'] as int;
    if (cursor > info.latest) {
      throw StateError(
        'Device history moved backwards without a new stream identity.',
      );
    }
    final floor = changedOwner
        ? info.latest
        : (changedStream ? 0 : old?['floor_seq'] as int? ?? 0);
    final pending = changedOwner || changedStream
        ? null
        : old?['pending_refresh'];
    await database.customStatement(
      '''INSERT INTO ble_sync_state(device_id,stream_id,generation,cursor,owner_id,floor_seq,pending_refresh,history_gap)
      VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(device_id) DO UPDATE SET stream_id=excluded.stream_id,generation=excluded.generation,
      cursor=excluded.cursor,owner_id=excluded.owner_id,floor_seq=excluded.floor_seq,pending_refresh=excluded.pending_refresh,history_gap=excluded.history_gap''',
      [
        device.id,
        info.streamId,
        generation,
        cursor,
        plantId,
        floor,
        pending,
        changedStream ? 1 : old?['history_gap'] ?? 0,
      ],
    );
    return BleSyncSnapshot(
      plantId,
      device,
      owner.single['profile_revision'] as int,
      info.streamId,
      generation,
      cursor,
      floor,
      pending == null ? null : BigInt.parse(pending as String),
      changedStream || old?['history_gap'] == 1,
    );
  });

  Future<void> _guardBle(BleSyncSnapshot s) async {
    final rows = await database.rows(
      '''SELECT p.profile_revision,d.revision,s.stream_id,s.generation,s.owner_id FROM plants p
      JOIN devices d ON d.id=p.device_id JOIN ble_sync_state s ON s.device_id=d.id WHERE p.id=? AND d.id=?''',
      [s.plantId, s.device.id],
    );
    if (rows.isEmpty ||
        rows.single['revision'] != s.device.revision ||
        rows.single['profile_revision'] != s.profileRevision ||
        rows.single['stream_id'] != s.streamId ||
        rows.single['generation'] != s.generation ||
        rows.single['owner_id'] != s.plantId) {
      throw StateError('Device assignment changed; BLE packet rejected.');
    }
  }

  Future<void> bleConnection(Device d, bool connected, {String? hint}) async {
    await database.customStatement(
      'UPDATE devices SET connected=?,platform_hint=COALESCE(?,platform_hint) WHERE id=? AND revision=? AND kind=\'physical\'',
      [connected ? 1 : 0, hint, d.id, d.revision],
    );
  }

  Future<BigInt> pendingBleRefresh(BleSyncSnapshot s, BigInt proposed) =>
      database.transaction(() async {
        await _guardBle(s);
        final row = (await database.rows(
          'SELECT pending_refresh FROM ble_sync_state WHERE device_id=?',
          [s.device.id],
        )).single;
        final token = row['pending_refresh'] as String? ?? proposed.toString();
        await database.customStatement(
          'UPDATE ble_sync_state SET pending_refresh=? WHERE device_id=?',
          [token, s.device.id],
        );
        return BigInt.parse(token);
      });

  Future<void> importBleBatch(
    BleSyncSnapshot s,
    BleBatch batch, {
    bool advanceCursor = false,
    BigInt? freshToken,
  }) => database.transaction(() async {
    await _guardBle(s);
    if (freshToken != null &&
        (batch.records.length != 1 ||
            batch.records.single.kind != 3 ||
            batch.records.single.request != freshToken)) {
      throw const BleProtocolException(
        'Refresh did not return its matching fresh measurement.',
      );
    }
    final state = (await database.rows(
      'SELECT cursor FROM ble_sync_state WHERE device_id=?',
      [s.device.id],
    )).single;
    final cursor = state['cursor'] as int;
    if (advanceCursor) {
      var previous = cursor;
      for (final r in batch.records) {
        if (r.sequence <= previous ||
            (!batch.gap && r.sequence != previous + 1)) {
          throw const BleProtocolException(
            'Invalid history sequence; cursor retained.',
          );
        }
        previous = r.sequence;
      }
      if (batch.cursor != previous) {
        throw const BleProtocolException(
          'History cursor does not match the committed batch.',
        );
      }
    }
    if (advanceCursor &&
        (batch.cursor < cursor ||
            (batch.records.isNotEmpty &&
                batch.records.first.sequence > cursor + 1 &&
                !batch.gap))) {
      throw const BleProtocolException(
        'Unexplained history gap; cursor retained.',
      );
    }
    for (final r in batch.records) {
      final raw = base64Encode(r.raw);
      final existing = await database.rows(
        'SELECT raw FROM ble_records WHERE device_id=? AND stream_id=? AND sequence=?',
        [s.device.id, s.streamId, r.sequence],
      );
      if (existing.isNotEmpty) {
        if (existing.single['raw'] != raw) {
          throw const BleProtocolException(
            'Conflicting persisted BLE sequence.',
          );
        }
        continue;
      }
      int? measured = r.utcSeconds == 0 ? null : r.utcSeconds * 1000;
      var quality = measured == null ? 'unknown' : 'device_anchored';
      if (measured == null) {
        final anchors = await database.rows(
          'SELECT measured_at_ms,uptime FROM ble_records WHERE device_id=? AND stream_id=? AND boot_id=? AND kind=4 ORDER BY sequence LIMIT 1',
          [s.device.id, s.streamId, r.bootId],
        );
        if (anchors.isNotEmpty) {
          measured =
              (anchors.single['measured_at_ms'] as int) +
              (r.uptimeSeconds - (anchors.single['uptime'] as int)) * 1000;
          quality = 'phone_anchored';
        }
      }
      await database.customStatement(
        '''INSERT INTO ble_records(device_id,stream_id,generation,sequence,plant_id,boot_id,uptime,measured_at_ms,time_quality,kind,request_token,moisture,temperature,humidity,light,raw)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
        [
          s.device.id,
          s.streamId,
          s.generation,
          r.sequence,
          r.isAnchor || r.sequence <= s.floor ? null : s.plantId,
          r.bootId,
          r.uptimeSeconds,
          measured,
          quality,
          r.kind,
          r.request.toString(),
          r.moisture,
          r.temperature,
          r.humidity,
          r.light,
          raw,
        ],
      );
      if (r.isAnchor) {
        await database.customStatement(
          '''UPDATE ble_records SET measured_at_ms=?+(uptime-?)*1000,time_quality='phone_anchored'
          WHERE device_id=? AND stream_id=? AND boot_id=? AND measured_at_ms IS NULL''',
          [
            r.utcSeconds * 1000,
            r.uptimeSeconds,
            s.device.id,
            s.streamId,
            r.bootId,
          ],
        );
      }
    }
    if (advanceCursor) {
      await database.customStatement(
        'UPDATE ble_sync_state SET cursor=?,history_gap=MAX(history_gap,?) WHERE device_id=?',
        [batch.cursor, batch.gap ? 1 : 0, s.device.id],
      );
    }
    if (freshToken != null) {
      await database.customStatement(
        'UPDATE ble_sync_state SET pending_refresh=NULL WHERE device_id=? AND pending_refresh=?',
        [s.device.id, freshToken.toString()],
      );
    }
    // Known measurement times use latest-packet-relative retention. Unknown
    // boot times remain explicitly unknown and are bounded by the ring capacity.
    await database.customStatement(
      '''DELETE FROM ble_records WHERE device_id=? AND kind!=4 AND measured_at_ms <
      (SELECT MAX(measured_at_ms) FROM ble_records WHERE device_id=? AND kind!=4)-?''',
      [
        s.device.id,
        s.device.id,
        SqlitePlantRepository.historyWindow.inMilliseconds,
      ],
    );
    await database.customStatement(
      '''DELETE FROM ble_records WHERE device_id=? AND measured_at_ms IS NULL AND sequence <
      (SELECT MAX(sequence)-1024 FROM ble_records WHERE device_id=? AND stream_id=?) AND stream_id=?''',
      [s.device.id, s.device.id, s.streamId, s.streamId],
    );
  });

  Future<bool> bleHasGap(String deviceId) async => (await database.rows(
    'SELECT history_gap FROM ble_sync_state WHERE device_id=?',
    [deviceId],
  )).any((r) => r['history_gap'] == 1);
}
