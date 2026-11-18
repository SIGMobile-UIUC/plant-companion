import 'ble_transport.dart';
import 'ble_transport_stub.dart'
    if (dart.library.io) 'ble_transport_mobile.dart'
    as platform;

BleTransport createBleTransport() => platform.createTransport();
