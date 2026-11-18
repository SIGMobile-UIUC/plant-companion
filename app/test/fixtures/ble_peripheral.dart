import 'dart:async';
import 'dart:typed_data';
import 'package:plant_companion/ble/ble_protocol.dart';
import 'package:plant_companion/ble/ble_transport.dart';

Uint8List wireRecord({
  required int sequence,
  int kind = 2,
  int boot = 1,
  int uptime = 0,
  int utc = 0,
  BigInt? token,
  int mask = 15,
}) {
  final b = Uint8List(48), d = ByteData.sublistView(b);
  b[0] = 1;
  b[1] = kind;
  b[2] = kind == 4 ? 0 : mask;
  b[3] = 1;
  d.setUint32(4, sequence, Endian.little);
  d.setUint32(8, boot, Endian.little);
  d.setUint32(12, uptime, Endian.little);
  d.setUint32(16, utc, Endian.little);
  putToken(d, 20, token ?? BigInt.zero);
  d.setUint16(28, b[2] & 1 != 0 ? 5050 : 65535, Endian.little);
  d.setInt16(30, b[2] & 2 != 0 ? 2356 : -32768, Endian.little);
  d.setUint16(32, b[2] & 4 != 0 ? 4567 : 65535, Endian.little);
  d.setUint16(34, 1100, Endian.little);
  d.setUint32(36, b[2] & 8 != 0 ? 123456 : 0xffffffff, Endian.little);
  d.setUint32(44, bleCrc32(b.sublist(0, 44)), Endian.little);
  return b;
}

void putToken(ByteData d, int offset, BigInt token) {
  d.setUint32(offset, (token & BigInt.from(0xffffffff)).toInt(), Endian.little);
  d.setUint32(offset + 4, (token >> 32).toInt(), Endian.little);
}

BigInt readToken(ByteData d, int offset) =>
    BigInt.from(d.getUint32(offset, Endian.little)) |
    (BigInt.from(d.getUint32(offset + 4, Endian.little)) << 32);
List<Uint8List> wireBatch(
  List<Uint8List> records,
  BigInt token, {
  required int cursor,
  required int newest,
  bool gap = false,
  bool more = false,
}) {
  final frames = <Uint8List>[];
  for (final r in records) {
    final seq = ByteData.sublistView(r).getUint32(4, Endian.little);
    for (var part = 0; part < 6; part++) {
      final b = Uint8List(20), d = ByteData.sublistView(b);
      b[0] = 1;
      b[1] = 1;
      b[2] = part;
      b[3] = 6;
      d.setUint32(4, (token & BigInt.from(0xffffffff)).toInt(), Endian.little);
      d.setUint32(8, seq, Endian.little);
      b.setRange(12, 20, r.sublist(part * 8, part * 8 + 8));
      frames.add(b);
    }
  }
  final b = Uint8List(20), d = ByteData.sublistView(b);
  b[0] = 1;
  b[1] = 2;
  putToken(d, 2, token);
  b[10] = records.length;
  b[11] = (gap ? 1 : 0) | (more ? 2 : 0);
  d.setUint32(
    12,
    records.isEmpty
        ? cursor
        : ByteData.sublistView(records.last).getUint32(4, Endian.little),
    Endian.little,
  );
  d.setUint32(16, newest, Endian.little);
  frames.add(b);
  return frames;
}

/// Byte-level peripheral, not a mocked domain gateway. Uses the documented
/// GATT info/control/data format and retains records across phone connections.
class TestBlePeripheral implements BleTransport {
  final List<Uint8List> records = [];
  final List<BleOp> commands = [];
  final List<BigInt> freshTokens = [];
  int stream = 17,
      boot = 1,
      seconds = 5,
      nextDeadline = 1200,
      acks = 0,
      connections = 0;
  bool failAck = false,
      interruptHistory = false,
      wrongFresh = false,
      unavailable = false;
  final String id = 'ble:010203040506';
  int sequence = 0;
  void sample({int kind = 2, int mask = 15, BigInt? token}) {
    records.add(
      wireRecord(
        sequence: ++sequence,
        kind: kind,
        boot: boot,
        uptime: seconds,
        utc: anchorUtc == null ? 0 : anchorUtc! + seconds,
        token: token,
        mask: mask,
      ),
    );
  }

  int? anchorUtc;
  void advance(int delta) {
    seconds += delta;
    if (seconds >= nextDeadline) {
      nextDeadline = ((seconds ~/ 1200) + 1) * 1200;
      sample();
    }
  }

  void reboot() {
    boot++;
    seconds = 0;
    nextDeadline = 1200;
    anchorUtc = null;
    sample(kind: 1);
  }

  @override
  bool get supported => true;
  @override
  Future<List<BleAdvertisement>> scan() async => unavailable
      ? []
      : [const BleAdvertisement('phone-hint', 'PlantComp-040506')];
  @override
  Future<BleConnection> connect(String platformId) async {
    if (unavailable || platformId != 'phone-hint') {
      throw const BleTransportException('Not found.');
    }
    connections++;
    return _TestConnection(this);
  }
}

class _TestConnection implements BleConnection {
  _TestConnection(this.p);
  final TestBlePeripheral p;
  final c = StreamController<List<int>>.broadcast();
  @override
  Stream<List<int>> get frames => c.stream;
  @override
  Future<Uint8List> readInfo() async {
    final b = Uint8List(20), d = ByteData.sublistView(b);
    b[0] = 1;
    b[1] = 15;
    b.setRange(2, 8, [1, 2, 3, 4, 5, 6]);
    d.setUint32(8, p.stream, Endian.little);
    d.setUint32(
      12,
      p.records.isEmpty ? 0 : BleRecord.decode(p.records.first).sequence,
      Endian.little,
    );
    d.setUint32(16, p.sequence, Endian.little);
    return b;
  }

  @override
  Future<void> write(List<int> bytes) async {
    final d = ByteData.sublistView(Uint8List.fromList(bytes)),
        op = BleOp.values[bytes[1]],
        token = readToken(d, 2),
        cursor = d.getUint32(10, Endian.little);
    // Re-encode validates the actual command CRC, bounds and 64-bit token.
    final encoded = bleCommand(
      op,
      token,
      a: cursor,
      b: d.getUint32(14, Endian.little),
    );
    if (encoded.toString() != bytes.toString()) {
      throw StateError('Invalid command bytes.');
    }
    if (!c.hasListener) {
      throw StateError(
        'Control command sent before notification subscription.',
      );
    }
    p.commands.add(op);
    if (op == BleOp.ack) {
      p.acks++;
      if (p.failAck) {
        p.failAck = false;
        throw const BleTransportException('ACK lost.');
      }
      return;
    }
    var rows = <Uint8List>[];
    if (op == BleOp.time) {
      if (p.anchorUtc == null) {
        p.anchorUtc = cursor - p.seconds;
        p.sample(kind: 4, token: token);
      }
      rows = [p.records.lastWhere((r) => r[1] == 4)];
    } else if (op == BleOp.latest) {
      final available = p.records.where((r) => r[1] != 4);
      if (available.isNotEmpty) rows = [available.last];
    } else if (op == BleOp.history) {
      rows = p.records
          .where((r) => BleRecord.decode(r).sequence > cursor)
          .take(8)
          .toList();
    } else if (op == BleOp.fresh) {
      p.freshTokens.add(token);
      final previous = p.records.where(
        (r) => r[1] == 3 && BleRecord.decode(r).request == token,
      );
      if (previous.isEmpty) {
        p.sample(kind: 3, token: p.wrongFresh ? token + BigInt.one : token);
        rows = [p.records.last];
      } else {
        rows = [previous.first];
      }
    }
    final frames = wireBatch(
      rows,
      token,
      cursor: op == BleOp.history ? cursor : 0,
      newest: p.sequence,
      gap:
          op == BleOp.history &&
          p.records.isNotEmpty &&
          BleRecord.decode(p.records.first).sequence > cursor + 1,
      more:
          op == BleOp.history &&
          rows.isNotEmpty &&
          BleRecord.decode(rows.last).sequence < p.sequence,
    );
    if (op == BleOp.history && p.interruptHistory) {
      p.interruptHistory = false;
      frames.removeAt(1);
    }
    for (final f in frames) {
      c.add(f);
    }
  }

  @override
  Future<void> close() => c.close();
}
