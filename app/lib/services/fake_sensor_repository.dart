import '../models/device.dart';
import '../models/plant.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';

class FakeSensorRepository {
  FakeSensorRepository({this.delay = const Duration(milliseconds: 850)});

  final Duration delay;
  int _sequence = 0;

  static const demoDevice = Device(
    id: 'esp32-demo-01',
    name: 'ESP32 · Sprout 01',
    isConnected: true,
    batteryVoltage: 3.87,
  );

  Future<List<Device>> discoverDevices() async {
    await Future<void>.delayed(delay);
    return [demoDevice.withConnection(false)];
  }

  Future<Device> connect(Device device, {bool simulateFailure = false}) async {
    await Future<void>.delayed(delay);
    if (simulateFailure) {
      throw StateError(
        'Demo connection failed. Try again or save without a device.',
      );
    }
    return device.withConnection(true);
  }

  Future<SensorReading> read(
    PlantProfile profile,
    DemoScenario scenario,
  ) async {
    await Future<void>.delayed(delay);
    return makeReading(profile, scenario, DateTime.now());
  }

  SensorReading makeReading(
    PlantProfile profile,
    DemoScenario scenario,
    DateTime timestamp,
  ) {
    // A deterministic small variation makes refresh visible and tests repeatable.
    final variation = (_sequence++ % 5 - 2) / 20;
    double comfortableValue(SensorMetric metric) {
      final range = profile.rangeFor(metric);
      return range.midpoint + (range.maximum - range.minimum) * variation;
    }

    return SensorReading(
      recordedAt: timestamp,
      soilMoisture: scenario == DemoScenario.thirsty
          ? profile.rangeFor(SensorMetric.soilMoisture).minimum * .35
          : comfortableValue(SensorMetric.soilMoisture),
      temperature: comfortableValue(SensorMetric.temperature),
      humidity: comfortableValue(SensorMetric.humidity),
      light: scenario == DemoScenario.lowLight
          ? profile.rangeFor(SensorMetric.light).minimum * .16
          : comfortableValue(SensorMetric.light),
    );
  }
}
