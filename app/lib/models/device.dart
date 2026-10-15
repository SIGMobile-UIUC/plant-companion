class Device {
  const Device({
    required this.id,
    required this.name,
    required this.isConnected,
    this.batteryVoltage,
  });

  final String id;
  final String name;
  final bool isConnected;
  final double? batteryVoltage;

  Device withConnection(bool connected) => Device(
    id: id,
    name: name,
    isConnected: connected,
    batteryVoltage: batteryVoltage,
  );
}
