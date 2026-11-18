import 'dart:typed_data';

class BleAdvertisement {
  const BleAdvertisement(this.platformId, this.name);
  final String platformId, name;
}

class BleTransportException implements Exception {
  const BleTransportException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class BleConnection {
  Future<Uint8List> readInfo();
  Stream<List<int>> get frames;
  Future<void> write(List<int> bytes);
  Future<void> close();
}

abstract interface class BleTransport {
  bool get supported;
  Future<List<BleAdvertisement>> scan();
  Future<BleConnection> connect(String platformId);
}
