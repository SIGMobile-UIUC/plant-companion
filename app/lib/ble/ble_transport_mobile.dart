import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_protocol.dart';
import 'ble_transport.dart';
import 'ble_transport_stub.dart' as stub;

BleTransport createTransport() => Platform.isAndroid || Platform.isIOS
    ? MobileBleTransport()
    : stub.createTransport();

class MobileBleTransport implements BleTransport {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  @override
  bool get supported => true;
  Future<void> _ready() async {
    if (Platform.isAndroid) {
      final sdk = await const MethodChannel(
        'plant_companion/platform',
      ).invokeMethod<int>('androidSdk');
      final permissions = (sdk ?? 31) >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse];
      final statuses = await permissions.request();
      if (statuses.values.any((s) => !s.isGranted)) {
        throw const BleTransportException(
          'Bluetooth permission denied. Enable it in Settings, then retry.',
        );
      }
    }
    final status = await _ble.statusStream
        .firstWhere((s) => s != BleStatus.unknown)
        .timeout(const Duration(seconds: 8));
    if (status != BleStatus.ready) {
      throw BleTransportException(switch (status) {
        BleStatus.poweredOff => 'Bluetooth is off. Turn it on, then retry.',
        BleStatus.unauthorized =>
          'Bluetooth permission denied. Enable it in Settings.',
        BleStatus.locationServicesDisabled =>
          'Enable Location Services for Bluetooth scanning on this Android version.',
        _ => 'Bluetooth is unavailable on this device.',
      });
    }
  }

  @override
  Future<List<BleAdvertisement>> scan() async {
    await _ready();
    final found = <String, BleAdvertisement>{};
    Object? failure;
    final sub = _ble
        .scanForDevices(
          withServices: [Uuid.parse(bleServiceUuid)],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (d) => found[d.id] = BleAdvertisement(
            d.id,
            d.name.isEmpty ? 'Plant Companion BLE' : d.name,
          ),
          onError: (Object e) {
            failure = e;
          },
        );
    try {
      await Future<void>.delayed(const Duration(seconds: 4));
    } finally {
      await sub.cancel();
    }
    if (failure != null) {
      throw BleTransportException('BLE scan failed: $failure');
    }
    return found.values.take(12).toList();
  }

  @override
  Future<BleConnection> connect(String platformId) async {
    await _ready();
    final connection = _MobileConnection(_ble, platformId);
    await connection.open();
    return connection;
  }
}

class _MobileConnection implements BleConnection {
  _MobileConnection(this.ble, this.id);
  final FlutterReactiveBle ble;
  final String id;
  final _frames = StreamController<List<int>>.broadcast();
  StreamSubscription<ConnectionStateUpdate>? _link;
  StreamSubscription<List<int>>? _data;
  bool _closed = false;
  QualifiedCharacteristic _char(String uuid) => QualifiedCharacteristic(
    deviceId: id,
    serviceId: Uuid.parse(bleServiceUuid),
    characteristicId: Uuid.parse(uuid),
  );
  Future<void> open() async {
    final ready = Completer<void>();
    _link = ble
        .connectToAdvertisingDevice(
          id: id,
          withServices: [Uuid.parse(bleServiceUuid)],
          prescanDuration: const Duration(seconds: 3),
          connectionTimeout: const Duration(seconds: 8),
        )
        .listen(
          (s) {
            if (s.connectionState == DeviceConnectionState.connected &&
                !ready.isCompleted) {
              ready.complete();
            }
            if (s.connectionState == DeviceConnectionState.disconnected &&
                !_closed) {
              final e = const BleTransportException(
                'Device disconnected. Move closer and retry.',
              );
              if (!ready.isCompleted) {
                ready.completeError(e);
              } else {
                _frames.addError(e);
              }
            }
          },
          onError: (Object e) {
            if (!ready.isCompleted) {
              ready.completeError(e);
            } else if (!_closed) {
              _frames.addError(e);
            }
          },
        );
    try {
      await ready.future.timeout(const Duration(seconds: 14));
    } catch (_) {
      await close();
      rethrow;
    }
  }

  @override
  Stream<List<int>> get frames {
    _data ??= ble
        .subscribeToCharacteristic(_char(bleDataUuid))
        .listen(_frames.add, onError: _frames.addError);
    return _frames.stream;
  }

  @override
  Future<Uint8List> readInfo() async =>
      Uint8List.fromList(await ble.readCharacteristic(_char(bleInfoUuid)));
  @override
  Future<void> write(List<int> bytes) =>
      ble.writeCharacteristicWithResponse(_char(bleControlUuid), value: bytes);
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _data?.cancel();
    await _link?.cancel();
    await _frames.close();
  }
}
