import 'ble_transport.dart';

BleTransport createTransport() => UnsupportedBleTransport();

class UnsupportedBleTransport implements BleTransport {
  @override
  bool get supported => false;
  @override
  Future<List<BleAdvertisement>> scan() async => [];
  @override
  Future<BleConnection> connect(String platformId) async =>
      throw const BleTransportException(
        'Physical BLE requires the iOS or Android app.',
      );
}
