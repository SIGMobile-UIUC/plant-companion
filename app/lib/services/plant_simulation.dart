import 'dart:math' as math;
import '../models/device.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';
import '../utils/sensor_scale.dart';
import 'sensor_gateway.dart';
import 'simulation_config.dart';

/// Local simulator policy only. A hardware SensorGateway needs no care ranges.
class PlantSimulationContext {
  PlantSimulationContext({
    required this.plantId,
    required this.lightRange,
    Map<SensorMetric, TargetRange>? idealRanges,
  }) : idealRanges = idealRanges == null
           ? null
           : Map.unmodifiable({...idealRanges, SensorMetric.light: lightRange});
  final String plantId;
  final TargetRange lightRange;

  /// Required for conditional manual packets; environmental tests may use light only.
  final Map<SensorMetric, TargetRange>? idealRanges;
  double get lightMaximum => math.min(
    SensorScale.forMetric(
      SensorMetric.light,
      lightRange,
      null,
      plantId: plantId,
    ).maximum,
    SimulationConfig.metrics[SensorMetric.light]!.maximum,
  );
}

/// Optional capability used inside the existing serialized acquisition path.
abstract interface class PlantSimulationGateway implements SensorGateway {
  @override
  Future<SensorReading> acquire(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  });
}
