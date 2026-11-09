// Isolated test/review setup only. Never imported by production entrypoints.
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/services/plant_repository.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';

/// Establish a real simulated gateway connection, without inserting a packet.
Future<Device> connectFixtureDevice(
  PlantRepository repo,
  String plantId,
) async {
  final device = (await repo.loadAssignedDevices())[plantId]!;
  if (device.isConnected) return device;
  final candidate = await FakeSensorRepository(
    delay: Duration.zero,
  ).connect(device);
  if (candidate.id != device.id || !candidate.isConnected) {
    throw StateError('Fixture connection failed.');
  }
  return (await repo.reconnectAssigned(plantId, device)) ??
      (throw StateError('Fixture assignment changed.'));
}
