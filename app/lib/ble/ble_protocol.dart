import 'dart:typed_data';

const bleServiceUuid = 'd1a10000-7c2f-4a9d-a6b4-36b51743c301';
const bleInfoUuid = 'd1a10001-7c2f-4a9d-a6b4-36b51743c301';
const bleControlUuid = 'd1a10002-7c2f-4a9d-a6b4-36b51743c301';
const bleDataUuid = 'd1a10003-7c2f-4a9d-a6b4-36b51743c301';
const bleProtocolVersion = 1;
const bleBatchLimit = 8;

enum BleOp { hello, history, latest, fresh, time, ack }

class BleProtocolException implements Exception {
  const BleProtocolException(this.message, {this.code, this.retryAfterMs = 0});
  final String message;
  final int? code;
  final int retryAfterMs;
  @override
  String toString() => message;
}

ByteData _data(List<int> bytes) =>
    ByteData.sublistView(Uint8List.fromList(bytes));
BigInt _u64(ByteData b, int offset) =>
    BigInt.from(b.getUint32(offset, Endian.little)) |
    (BigInt.from(b.getUint32(offset + 4, Endian.little)) << 32);
void _put64(ByteData b, int offset, BigInt value) {
  if (value.isNegative || value.bitLength > 64) {
    throw const BleProtocolException('Invalid BLE request identity.');
  }
  b.setUint32(offset, (value & BigInt.from(0xffffffff)).toInt(), Endian.little);
  b.setUint32(offset + 4, (value >> 32).toInt(), Endian.little);
}

int bleCrc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final byte in bytes) {
    c ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      c = (c >>> 1) ^ ((c & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  return (~c) & 0xffffffff;
}

int _crc16(List<int> bytes) {
  var c = 0xffff;
  for (final byte in bytes) {
    c ^= byte << 8;
    for (var bit = 0; bit < 8; bit++) {
      c = ((c & 0x8000) != 0 ? (c << 1) ^ 0x1021 : c << 1) & 0xffff;
    }
  }
  return c;
}

Uint8List bleCommand(BleOp op, BigInt token, {int a = 0, int b = 0}) {
  if (a < 0 || a > 0xffffffff || b < 0 || b > 0xffffffff) {
    throw const BleProtocolException('Invalid BLE command bounds.');
  }
  final bytes = Uint8List(20), data = ByteData.sublistView(bytes);
  bytes[0] = bleProtocolVersion;
  bytes[1] = op.index;
  _put64(data, 2, token);
  data.setUint32(10, a, Endian.little);
  data.setUint32(14, b, Endian.little);
  data.setUint16(18, _crc16(bytes.sublist(0, 18)), Endian.little);
  return bytes;
}

class BleDeviceInfo {
  const BleDeviceInfo({
    required this.id,
    required this.streamId,
    required this.oldest,
    required this.latest,
    required this.calibrated,
    required this.storageReady,
  });
  final String id;
  final int streamId, oldest, latest;
  final bool calibrated, storageReady;
  factory BleDeviceInfo.decode(List<int> bytes) {
    if (bytes.length != 20 ||
        bytes[0] != 1 ||
        bytes[1] & 7 != 7 ||
        bytes[1] & ~31 != 0 ||
        bytes.sublist(2, 8).every((v) => v == 0)) {
      throw const BleProtocolException(
        'Incompatible Plant Companion firmware.',
      );
    }
    final b = _data(bytes),
        oldest = b.getUint32(12, Endian.little),
        latest = b.getUint32(16, Endian.little),
        stream = b.getUint32(8, Endian.little);
    if (stream == 0 || oldest > latest || (oldest == 0) != (latest == 0)) {
      throw const BleProtocolException('Invalid device history information.');
    }
    return BleDeviceInfo(
      id: 'ble:${bytes.sublist(2, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
      streamId: stream,
      oldest: oldest,
      latest: latest,
      calibrated: bytes[1] & 8 != 0,
      storageReady: bytes[1] & 16 == 0,
    );
  }
}

class BleRecord {
  BleRecord._(
    this.raw,
    this.sequence,
    this.kind,
    this.validity,
    this.flags,
    this.bootId,
    this.uptimeSeconds,
    this.utcSeconds,
    this.request,
    this.moisture,
    this.temperature,
    this.humidity,
    this.light,
  );
  final Uint8List raw;
  final int sequence, kind, validity, flags, bootId, uptimeSeconds, utcSeconds;
  final BigInt request;
  final double? moisture, temperature, humidity, light;
  bool get isAnchor => kind == 4;
  String get origin => switch (kind) {
    1 => 'ble_startup',
    2 => 'ble_scheduled',
    3 => 'ble_manual',
    _ => 'ble_anchor',
  };
  factory BleRecord.decode(List<int> input) {
    final bytes = Uint8List.fromList(input);
    if (bytes.length != 48) {
      throw const BleProtocolException('Incomplete BLE record.');
    }
    final d = _data(bytes), kind = bytes[1], mask = bytes[2], flags = bytes[3];
    final seq = d.getUint32(4, Endian.little),
        boot = d.getUint32(8, Endian.little),
        utc = d.getUint32(16, Endian.little),
        m = d.getUint16(28, Endian.little),
        t = d.getInt16(30, Endian.little),
        h = d.getUint16(32, Endian.little),
        lux = d.getUint32(36, Endian.little);
    if (bytes[0] != 1 ||
        kind < 1 ||
        kind > 4 ||
        mask & ~15 != 0 ||
        flags & ~3 != 0 ||
        seq == 0 ||
        boot == 0 ||
        d.getUint32(40, Endian.little) != 0 ||
        bleCrc32(bytes.sublist(0, 44)) != d.getUint32(44, Endian.little) ||
        (mask & 1 != 0 ? m > 10000 : m != 65535) ||
        (mask & 2 != 0 ? t < -4000 || t > 12500 : t != -32768) ||
        (mask & 4 != 0 ? h > 10000 : h != 65535) ||
        (mask & 8 != 0 ? lux == 0xffffffff : lux != 0xffffffff) ||
        (kind == 4 && (mask != 0 || utc == 0))) {
      throw const BleProtocolException('Invalid or corrupt BLE record.');
    }
    return BleRecord._(
      bytes,
      seq,
      kind,
      mask,
      flags,
      boot,
      d.getUint32(12, Endian.little),
      utc,
      _u64(d, 20),
      mask & 1 != 0 ? m / 100 : null,
      mask & 2 != 0 ? t / 100 : null,
      mask & 4 != 0 ? h / 100 : null,
      mask & 8 != 0 ? lux / 1000 : null,
    );
  }
}

class BleBatch {
  const BleBatch(this.records, this.cursor, this.newest, this.gap, this.more);
  final List<BleRecord> records;
  final int cursor, newest;
  final bool gap, more;
}

/// Bounded assembler for exactly one requested transfer; incomplete/mixed data
/// cannot advance a cursor. Duplicate identical fragments are harmless.
class BleBatchAssembler {
  BleBatchAssembler(this.token);
  final BigInt token;
  final Map<int, Map<int, List<int>>> _parts = {};
  BleBatch? accept(List<int> bytes) {
    if (bytes.length != 20 || bytes[0] != 1) {
      throw const BleProtocolException('Malformed BLE frame.');
    }
    final d = _data(bytes);
    if (bytes[1] == 1) {
      if (d.getUint32(4, Endian.little) !=
          (token & BigInt.from(0xffffffff)).toInt()) {
        return null;
      }
      final seq = d.getUint32(8, Endian.little), part = bytes[2];
      if (seq == 0 ||
          part >= 6 ||
          bytes[3] != 6 ||
          (!_parts.containsKey(seq) && _parts.length == 8)) {
        throw const BleProtocolException('Invalid BLE fragment bounds.');
      }
      final pieces = _parts.putIfAbsent(seq, () => {}),
          value = bytes.sublist(12);
      if (pieces[part] != null && !_same(pieces[part]!, value)) {
        throw const BleProtocolException('Conflicting BLE fragments.');
      }
      pieces[part] = List.of(value);
      return null;
    }
    if (bytes[1] != 2 && bytes[1] != 3) {
      throw const BleProtocolException('Unknown BLE frame.');
    }
    if (_u64(d, 2) != token) return null;
    if (bytes[1] == 3) {
      final code = bytes[10];
      throw BleProtocolException(
        switch (code) {
          2 => 'Device is busy. Wait a moment and retry.',
          3 => 'Device storage failed; the previous reading is retained.',
          4 => 'Incompatible firmware.',
          _ => 'Device rejected the BLE command.',
        },
        code: code,
        retryAfterMs: d.getUint32(12, Endian.little),
      );
    }
    final count = bytes[10],
        cursor = d.getUint32(12, Endian.little),
        newest = d.getUint32(16, Endian.little);
    if (count > 8 ||
        count != _parts.length ||
        bytes[11] & ~3 != 0 ||
        cursor > newest) {
      throw const BleProtocolException('Incomplete BLE batch.');
    }
    final records = <BleRecord>[];
    for (final seq in _parts.keys.toList()..sort()) {
      final parts = _parts[seq]!;
      if (parts.length != 6) {
        throw const BleProtocolException('Missing BLE chunk; retry is safe.');
      }
      final r = BleRecord.decode([for (var p = 0; p < 6; p++) ...parts[p]!]);
      if (r.sequence != seq) {
        throw const BleProtocolException('BLE sequence mismatch.');
      }
      records.add(r);
    }
    if (records.isNotEmpty && records.last.sequence != cursor) {
      throw const BleProtocolException('BLE cursor mismatch.');
    }
    return BleBatch(
      List.unmodifiable(records),
      cursor,
      newest,
      bytes[11] & 1 != 0,
      bytes[11] & 2 != 0,
    );
  }

  static bool _same(List<int> a, List<int> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
}
