import 'sensor_reading.dart';
import 'plant_profile.dart';

class Device {
  const Device({
    required this.id,
    required this.name,
    required this.isConnected,
    this.createdAt,
    this.displayOrdinal = 0,
    this.revision = 0,
    this.lastAutoSlot = 0,
    this.generationSequence = 0,
    this.batteryVoltage,
  });

  /// Immutable identity. Never bind ownership/history to the mutable name.
  final String id;
  final String name;
  final bool isConnected;
  final DateTime? createdAt;
  final int displayOrdinal;
  final int revision;
  final int lastAutoSlot;
  final int generationSequence;
  final double? batteryVoltage;

  Device withConnection(bool connected) => Device(
    id: id,
    name: name,
    isConnected: connected,
    createdAt: createdAt,
    displayOrdinal: displayOrdinal,
    revision: revision,
    lastAutoSlot: lastAutoSlot,
    generationSequence: generationSequence,
    batteryVoltage: batteryVoltage,
  );

  static String displayName(int ordinal) =>
      'ESP32-Sim${ordinal.toString().padLeft(2, '0')}';
}

/// One SQLite snapshot of ownership/sequence and the last committed source
/// packet, including its previous owner when a device was reassigned.
class DeviceReadingContext {
  DeviceReadingContext(
    this.device,
    this.previousReading, {
    required this.plantId,
    required this.profileRevision,
    required Map<SensorMetric, TargetRange> idealRanges,
  }) : idealRanges = Map.unmodifiable(idealRanges);
  final Device device;
  final SensorReading? previousReading;
  final String plantId;
  final int profileRevision;
  final Map<SensorMetric, TargetRange> idealRanges;
  TargetRange get lightRange => idealRanges[SensorMetric.light]!;
  DeviceReadingContext withDevice(Device updated) => DeviceReadingContext(
    updated,
    previousReading,
    plantId: plantId,
    profileRevision: profileRevision,
    idealRanges: idealRanges,
  );
}
