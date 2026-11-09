import '../models/device.dart';
import '../models/sensor_reading.dart';
import 'sensor_gateway.dart';
import 'simulation_config.dart';
import 'simulated_environment.dart';
import 'plant_simulation.dart';
export 'sensor_gateway.dart' show SimulationMode;
export 'plant_simulation.dart' show PlantSimulationContext;

class FakeSensorRepository implements PlantSimulationGateway, DeviceGateway {
  FakeSensorRepository({
    Duration? delay,
    Duration? discoveryDelay,
    Duration? connectionDelay,
    Duration? acquisitionDelay,
    this.inventory,
  }) : discoveryDelay =
           discoveryDelay ?? delay ?? SimulationConfig.discoveryDelay,
       connectionDelay =
           connectionDelay ?? delay ?? SimulationConfig.connectionDelay,
       acquisitionDelay =
           acquisitionDelay ?? delay ?? SimulationConfig.acquisitionDelay {
    if ([
      this.discoveryDelay,
      this.connectionDelay,
      this.acquisitionDelay,
    ].any((d) => d.isNegative)) {
      throw ArgumentError('Simulator delays must be nonnegative.');
    }
  }
  final Duration discoveryDelay, connectionDelay, acquisitionDelay;

  /// Kept as an acquisition-delay alias for existing test/review adapters.
  Duration get delay => acquisitionDelay;
  final Future<List<Device>> Function()? inventory;

  static const demoDevice = Device(
    id: 'device-1',
    name: 'ESP32-Sim01',
    isConnected: true,
  );

  @override
  Future<List<Device>> discoverDevices() async {
    await Future<void>.delayed(discoveryDelay);
    return inventory == null ? [demoDevice] : inventory!();
  }

  @override
  Future<Device> connect(Device device, {bool simulateFailure = false}) async {
    await Future<void>.delayed(connectionDelay);
    if (simulateFailure) throw StateError('Could not connect. Try again.');
    return device.withConnection(true); // Candidate only, no saved assignment.
  }

  @override
  Future<SensorReading> acquire(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) async {
    if (plantContext == null) {
      throw ArgumentError(
        'Local acquisition requires committed plant context.',
      );
    }
    await Future<void>.delayed(acquisitionDelay);
    return SimulatedEnvironment.sample(
      device,
      recordedAt,
      previousReading: previousReading,
      simulationMode: simulationMode,
      plantContext: plantContext,
    );
  }
}
