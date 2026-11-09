import '../models/device.dart';
import '../models/sensor_reading.dart';
import '../config/temperature_display_config.dart';
import 'condition_driven_simulation.dart';
import 'plant_simulation.dart';
import 'simulation_config.dart';
import 'sensor_gateway.dart';

/// Rounding cannot extend a sampling envelope, including repeating C/F bounds.
double quantizeSimulatedValue(
  double value, {
  required double minimum,
  required double maximum,
  required double scale,
}) {
  final bounded = value.clamp(minimum, maximum).toDouble();
  if (!scale.isFinite) return bounded;
  return ((bounded * scale).roundToDouble() / scale)
      .clamp(minimum, maximum)
      .toDouble();
}

/// Pure versioned environmental process. Only repository commit advances sequence.
/// UTF-16 polynomial hash + four xor-shift/Park–Miller mixing rounds. Integer
/// products stay below 2^53 so VM and JavaScript use identical exact arithmetic.
/// Environmental randomness ignores labels/time; only its light bounds use care.
/// Explicit manual calls delegate to the separate condition-first policy.
class SimulatedEnvironment {
  static const _modulus = 2147483647;
  static double _unit(String key) {
    var state = 1;
    for (final unit in key.codeUnits) {
      state = (state * 131 + unit) % _modulus;
    }
    if (state == 0) state = 1;
    for (var round = 0; round < 4; round++) {
      state = (state * 48271) % _modulus;
      state = state ^ (state >>> 13);
      if (state == 0) state = 1;
    }
    return state / _modulus;
  }

  static SensorReading sample(
    Device device,
    DateTime recordedAt, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    required PlantSimulationContext plantContext,
  }) {
    if (simulationMode == SimulationMode.manualConditionDriven) {
      return ConditionDrivenSimulation(
        plantContext,
      ).sample(device, recordedAt).reading;
    }
    final lightMaximum = plantContext.lightMaximum;
    double value(SensorMetric metric) {
      final c = SimulationConfig.metrics[metric]!;
      final minimum = metric == SensorMetric.temperature
          ? TemperatureDisplayConfig.minimumCelsius
          : c.minimum;
      final maximum = metric == SensorMetric.light
          ? lightMaximum
          : metric == SensorMetric.temperature
          ? TemperatureDisplayConfig.maximumCelsius
          : c.maximum;
      // Clamp after quantization: rounding the repeating 120 F Celsius endpoint
      // to four decimals alone could otherwise produce 120.00002 F.
      final scale = metric == SensorMetric.light && maximum < 100
          ? 10000 / maximum
          : c.scale;
      double quantize(double v) => quantizeSimulatedValue(
        v,
        minimum: minimum,
        maximum: maximum,
        scale: scale,
      );
      final key =
          'environment-v${SimulationConfig.algorithmVersion}|${device.id}|${metric.name}';
      final factor = metric == SensorMetric.light
          ? (lightMaximum / SimulationConfig.lightSmoothingReferenceMaximum)
                .clamp(0.0, 1.0)
          : 1.0;
      final baseline =
          ((c.baselineMinimum +
                      _unit('$key|baseline') *
                          (c.baselineMaximum - c.baselineMinimum)) *
                  factor)
              .clamp(minimum, maximum)
              .toDouble();
      final prior = previousReading?.sourceDeviceId == device.id
          ? previousReading?.valueFor(metric)
          : null;
      final project =
          metric == SensorMetric.light || metric == SensorMetric.temperature;
      final previous = project && prior != null && prior.isFinite
          ? prior.clamp(minimum, maximum).toDouble()
          : prior != null &&
                prior.isFinite &&
                prior >= c.minimum &&
                prior <= c.maximum
          ? prior
          : baseline;
      // Independent triangular innovations plus gentle mean reversion. A hard
      // per-acquisition delta cap avoids jumping from an old genuine packet.
      final noise =
          _unit('$key|${device.generationSequence}|a') +
          _unit('$key|${device.generationSequence}|b') -
          1;
      final delta =
          ((baseline - previous) * c.reversion + noise * c.innovation * factor)
              .clamp(-c.maximumChange * factor, c.maximumChange * factor);
      return quantize(previous + delta);
    }

    return SensorReading(
      recordedAt: recordedAt.toUtc(),
      sourceDeviceId: device.id,
      soilMoisture: value(SensorMetric.soilMoisture),
      light: value(SensorMetric.light),
      temperature: value(SensorMetric.temperature),
      humidity: value(SensorMetric.humidity),
    );
  }
}
