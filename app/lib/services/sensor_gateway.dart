import '../models/device.dart';
import '../models/sensor_reading.dart';

/// Sampling policy is independent of persisted manual/connection/automatic origin.
enum SimulationMode { environment, manualConditionDriven }

abstract interface class SensorGateway {
  Future<SensorReading> acquire(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
  });
}

abstract interface class DeviceGateway {
  Future<List<Device>> discoverDevices();
  Future<Device> connect(Device device, {bool simulateFailure = false});
}
