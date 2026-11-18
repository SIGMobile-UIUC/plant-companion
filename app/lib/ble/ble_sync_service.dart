import 'dart:async';
import 'dart:math';
import '../models/device.dart';
import '../persistence/sqlite_plant_repository.dart';
import 'ble_protocol.dart';
import 'ble_transport.dart';

/// A single foreground BLE link and bounded transfers. Device-side sampling
/// continues independently; no phone background service or simulator routing.
class BleSyncService {
  BleSyncService(
    this.persistence,
    this.transport, {
    this.commandTimeout = const Duration(seconds: 12),
  });
  final SqlitePlantRepository persistence;
  final BleTransport transport;
  final Duration commandTimeout;
  Future<void> Function()? onChanged;
  final Map<String, String> messages = {};
  final _random = Random.secure();
  Future<void> _tail = Future.value();
  BleConnection? _connection;
  Device? _device;
  StreamSubscription<List<int>>? _frames;
  BleBatchAssembler? _assembler;
  Completer<BleBatch>? _response;
  Timer? _poll;
  bool _disposed = false, _active = false, _polling = false;
  bool _started = false;
  bool _disposing = false;
  BigInt _token() =>
      (BigInt.from(_random.nextInt(1 << 32)) << 32) |
      BigInt.from(_random.nextInt(1 << 32) | 1);

  Future<T> _serial<T>(Future<T> Function() action) {
    final task = _tail.then((_) {
      if (_disposed) throw StateError('BLE session closed.');
      return action();
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> _publish() async {
    if (!_disposed) await onChanged?.call();
  }

  Future<void> _close() async {
    final connection = _connection, device = _device;
    _connection = null;
    _device = null;
    await _frames?.cancel();
    _frames = null;
    await connection?.close();
    if (device != null) await persistence.bleConnection(device, false);
  }

  void _linkError(Object error) {
    if (_disposed || _disposing) return;
    if (_response?.isCompleted == false) _response!.completeError(error);
    final d = _device;
    if (d != null) messages[d.id] = error.toString();
    // Serialize cleanup after the active command has unwound.
    unawaited(
      _serial(() async {
        await _close();
        await _publish();
      }),
    );
  }

  Future<BleBatch> _command(
    BleOp op, {
    BigInt? token,
    int a = 0,
    int b = 0,
  }) async {
    final id = token ?? _token(), response = Completer<BleBatch>();
    _assembler = BleBatchAssembler(id);
    _response = response;
    final timeout = Timer(commandTimeout, () {
      if (!response.isCompleted) {
        response.completeError(TimeoutException('BLE response timed out.'));
      }
    });
    try {
      final results = await Future.wait<Object?>([
        Future.sync(() => _connection!.write(bleCommand(op, id, a: a, b: b))),
        response.future,
      ], eagerError: true);
      return results[1] as BleBatch;
    } finally {
      timeout.cancel();
      _assembler = null;
      _response = null;
    }
  }

  Future<BleDeviceInfo> _open(Device d) async {
    if (!transport.supported) {
      throw const BleTransportException(
        'Physical BLE requires the iOS or Android app.',
      );
    }
    if (_device?.id == d.id && _connection != null) {
      final info = BleDeviceInfo.decode(await _connection!.readInfo());
      if (info.id != d.id) {
        throw const BleProtocolException('BLE identity changed.');
      }
      _device = d;
      await persistence.bleConnection(d, true);
      return info;
    }
    await _close();
    final candidates = <BleAdvertisement>[
      if (d.platformHint != null) BleAdvertisement(d.platformHint!, d.name),
    ];
    Object? last;
    Future<BleDeviceInfo?> attempt(BleAdvertisement candidate) async {
      BleConnection? link;
      try {
        link = await transport.connect(candidate.platformId);
        final info = BleDeviceInfo.decode(await link.readInfo());
        if (info.id != d.id) {
          await link.close();
          return null;
        }
        _connection = link;
        _device = d;
        _frames = link.frames.listen(
          (bytes) {
            try {
              final batch = _assembler?.accept(bytes);
              if (batch != null && _response?.isCompleted == false) {
                _response!.complete(batch);
              }
            } catch (e) {
              if (_response?.isCompleted == false) _response!.completeError(e);
            }
          },
          onError: (Object e) => _linkError(e),
          onDone: () {
            if (_connection != null) {
              _linkError(const BleTransportException('Device disconnected.'));
            }
          },
        );
        // HELLO END is proof that CCCD subscription is live before commands
        // capable of creating a reading or changing the sync cursor.
        await _command(BleOp.hello);
        await persistence.bleConnection(d, true, hint: candidate.platformId);
        return info;
      } catch (e) {
        last = e;
        await link?.close();
        await _frames?.cancel();
        _frames = null;
        _connection = null;
        _device = null;
        return null;
      }
    }

    for (final c in candidates) {
      final info = await attempt(c);
      if (info != null) return info;
    }
    for (final c in await transport.scan()) {
      if (candidates.any((old) => old.platformId == c.platformId)) continue;
      final info = await attempt(c);
      if (info != null) return info;
    }
    throw last ??
        const BleTransportException(
          'Device not found. Power it on and move closer, then retry.',
        );
  }

  Future<List<Device>> discover() => _serial(() async {
    await _close();
    if (!transport.supported) return [];
    final result = <Device>[];
    for (final advert in await transport.scan()) {
      BleConnection? link;
      try {
        link = await transport.connect(advert.platformId);
        final info = BleDeviceInfo.decode(await link.readInfo());
        if (!result.any((d) => d.id == info.id)) {
          result.add(
            Device(
              id: info.id,
              name: advert.name,
              isConnected: false,
              isPhysical: true,
              platformHint: advert.platformId,
            ),
          );
        }
      } on BleProtocolException {
        // Other services/old diagnostic firmware are excluded.
        continue;
      } finally {
        await link?.close();
      }
    }
    await _publish();
    return result;
  });
  Future<Device> prepare(Device d) => _serial(() async {
    await _open(d);
    messages[d.id] =
        'Physical BLE device ready. Assignment is saved with the form.';
    return d.withConnection(true);
  });
  Future<void> synchronize(
    String plantId,
    Device d, {
    bool refresh = false,
  }) => _serial(() async {
    var freshCommitted = false;
    messages[d.id] = 'Connecting to physical BLE device…';
    await _publish();
    try {
      final info = await _open(d);
      if (!info.storageReady) {
        throw const BleTransportException(
          'Device storage failed. Retained app readings remain available.',
        );
      }
      final s = await persistence.beginBleSync(plantId, d, info);
      final time = await _command(
        BleOp.time,
        a: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      );
      await persistence.importBleBatch(s, time);
      final latest = await _command(BleOp.latest);
      await persistence.importBleBatch(s, latest);
      var visible = latest.records.isEmpty ? null : latest.records.single;
      await _publish();
      if (refresh ||
          s.pending != null ||
          (s.floor > 0 && s.cursor <= s.floor)) {
        final token = await persistence.pendingBleRefresh(s, _token());
        final batch = await _command(BleOp.fresh, token: token);
        await persistence.importBleBatch(s, batch, freshToken: token);
        freshCommitted = true;
        visible = batch.records.single;
        await _publish();
      }
      var cursor = s.cursor, more = true;
      for (var page = 0; more && page < 130; page++) {
        final batch = await _command(
          BleOp.history,
          a: cursor,
          b: bleBatchLimit,
        );
        if (batch.more && batch.cursor <= cursor) {
          throw const BleProtocolException(
            'History transfer made no progress.',
          );
        }
        await persistence.importBleBatch(s, batch, advanceCursor: true);
        cursor = batch.cursor;
        more = batch.more;
        // A failed write above never reaches ACK. A lost ACK is harmless: the
        // board retains its ring and SQLite holds the committed cursor.
        await _connection!.write(bleCommand(BleOp.ack, _token(), a: cursor));
      }
      messages[d.id] = await persistence.bleHasGap(d.id)
          ? 'Physical BLE · Connected · History gap detected; unavailable samples cannot be recovered.'
          : 'Physical BLE · Connected${info.calibrated ? '' : ' · Soil calibration required'}';
      if (visible != null && visible.validity != 15) {
        final missing = [
          for (final entry in {
            1: 'soil moisture',
            2: 'temperature',
            4: 'humidity',
            8: 'light',
          }.entries)
            if (visible.validity & entry.key == 0) entry.value,
        ];
        messages[d.id] =
            '${messages[d.id]} · Unavailable: ${missing.join(', ')}';
      }
      await _publish();
    } catch (e) {
      messages[d.id] = e is TimeoutException
          ? 'BLE transfer timed out. Saved readings and sync cursor are retained; retry is safe.'
          : e.toString();
      await _close();
      await _publish();
      if (freshCommitted) {
        messages[d.id] =
            'Fresh reading saved. History sync paused: ${messages[d.id]}';
        await _publish();
        return;
      }
      rethrow;
    }
  });
  Future<void> _syncAssigned() async {
    if (_polling || !_active || _disposed) return;
    _polling = true;
    try {
      final devices = await persistence.loadAssignedDevices();
      for (final entry in devices.entries) {
        if (!_active || _disposed) break;
        if (entry.value.isPhysical) {
          try {
            await synchronize(entry.key, entry.value);
          } catch (_) {
            /* Visible per-device status; next foreground poll retries. */
          }
        }
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> resume() async {
    if (!_started) {
      _started = true;
      for (final d in (await persistence.loadAssignedDevices()).values.where(
        (d) => d.isPhysical,
      )) {
        await persistence.bleConnection(d, false);
      }
      await _publish();
    }
    _active = true;
    _poll ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_syncAssigned()),
    );
    await _syncAssigned();
  }

  Future<void> assignmentsChanged() => _serial(() async {
    final current = _device;
    if (current == null) return;
    final assigned = await persistence.loadAssignedDevices();
    if (!assigned.values.any(
      (d) => d.id == current.id && d.revision == current.revision,
    )) {
      messages.remove(current.id);
      await _close();
    }
  });

  void pause() {
    _active = false;
    _poll?.cancel();
    _poll = null;
    if (!_disposed) {
      unawaited(
        _serial(() async {
          await _close();
          await _publish();
        }),
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposing = true;
    _active = false;
    _poll?.cancel();
    _poll = null;
    await _tail;
    if (_disposed) return;
    _disposed = true;
    await _close();
  }
}
