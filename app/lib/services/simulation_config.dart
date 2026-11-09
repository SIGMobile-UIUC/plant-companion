import '../models/sensor_reading.dart';

/// Local simulator parameters, not hardware calibration or plant care targets.
class SimulationConfig {
  static const discoveryDelay = Duration(milliseconds: 60);
  static const connectionDelay = Duration(milliseconds: 35);
  static const acquisitionDelay = Duration(milliseconds: 20);
  static const algorithmVersion = 1;
  static const conditionAlgorithmVersion = 4;
  static const manualAlgorithmVersion =
      3; // Historical independent T/light policy.
  static const preservedManualAlgorithmVersion =
      2; // Historical independent moisture/humidity policy.
  static const lightSmoothingReferenceMaximum = 1500.0;
  static const metrics = {
    SensorMetric.soilMoisture: MetricSimulation(
      0,
      100,
      35,
      65,
      .04,
      1.6,
      2.5,
      100,
    ),
    SensorMetric.light: MetricSimulation(
      0,
      200000,
      250,
      1450,
      .05,
      150,
      220,
      100,
    ),
    SensorMetric.temperature: MetricSimulation(
      -50,
      100,
      19,
      27,
      .05,
      .15,
      .4,
      10000,
    ),
    SensorMetric.humidity: MetricSimulation(0, 100, 35, 65, .05, 1.9, 3, 100),
  };
}

class MetricSimulation {
  const MetricSimulation(
    this.minimum,
    this.maximum,
    this.baselineMinimum,
    this.baselineMaximum,
    this.reversion,
    this.innovation,
    this.maximumChange,
    this.scale,
  );
  final double minimum,
      maximum,
      baselineMinimum,
      baselineMaximum,
      reversion,
      innovation,
      maximumChange,
      scale;
}
