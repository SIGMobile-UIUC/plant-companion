import 'dart:math' as math;
import '../config/light_display_config.dart';
import '../config/temperature_display_config.dart';
import '../models/device.dart';
import '../models/plant.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';
import '../utils/sensor_units.dart';
import 'plant_condition_calculator.dart';
import 'plant_simulation.dart';
import 'simulation_config.dart';

enum ManualPlantCondition {
  happy,
  moistureTooLow,
  moistureTooHigh,
  lightTooLow,
  lightTooHigh,
  temperatureTooLow,
  temperatureTooHigh,
  humidityTooLow,
  humidityTooHigh;

  int get weight => this == happy ? 2 : 1;
  SensorMetric? get metric => switch (this) {
    happy => null,
    moistureTooLow || moistureTooHigh => SensorMetric.soilMoisture,
    lightTooLow || lightTooHigh => SensorMetric.light,
    temperatureTooLow || temperatureTooHigh => SensorMetric.temperature,
    humidityTooLow || humidityTooHigh => SensorMetric.humidity,
  };
  ReadingStatus get status => switch (this) {
    happy => ReadingStatus.inRange,
    moistureTooLow ||
    lightTooLow ||
    temperatureTooLow ||
    humidityTooLow => ReadingStatus.belowRange,
    _ => ReadingStatus.aboveRange,
  };
}

class NoFeasibleManualCondition implements Exception {
  static const message =
      'Correct the saved ideal ranges to test simulated conditions.';
  const NoFeasibleManualCondition();
  @override
  String toString() => message;
}

/// Ephemeral diagnostic result; the persisted packet contains measurements only.
class ConditionSample {
  const ConditionSample(this.mode, this.reading);
  final ManualPlantCondition mode;
  final SensorReading reading;
}

/// Immutable, synchronous plan for one committed profile. No random state/cache.
class ConditionDrivenSimulation {
  factory ConditionDrivenSimulation(PlantSimulationContext context) {
    final ranges = context.idealRanges;
    if (ranges == null ||
        SensorMetric.values.any(
          (m) =>
              ranges[m] == null ||
              !ranges[m]!.minimum.isFinite ||
              !ranges[m]!.maximum.isFinite ||
              ranges[m]!.minimum > ranges[m]!.maximum,
        )) {
      throw const NoFeasibleManualCondition();
    }
    double lightMaximum;
    try {
      lightMaximum = context.lightMaximum;
    } on ArgumentError {
      throw const NoFeasibleManualCondition();
    }
    final intervals = {
      for (final m in SensorMetric.values)
        m: _MetricIntervals(m, ranges[m]!, lightMaximum),
    };
    final eligible = ManualPlantCondition.values
        .where(
          (mode) => SensorMetric.values.every(
            (m) =>
                intervals[m]!.forStatus(
                  mode.metric == m ? mode.status : ReadingStatus.inRange,
                ) !=
                null,
          ),
        )
        .toList(growable: false);
    if (eligible.isEmpty) throw const NoFeasibleManualCondition();
    return ConditionDrivenSimulation._(
      context,
      intervals,
      List.unmodifiable(eligible),
    );
  }
  ConditionDrivenSimulation._(
    this.context,
    this._intervals,
    this.eligibleModes,
  );
  final PlantSimulationContext context;
  final Map<SensorMetric, _MetricIntervals> _intervals;
  final List<ManualPlantCondition> eligibleModes;
  int get totalWeight => eligibleModes.fold(0, (n, m) => n + m.weight);

  // Same proven exact 31-bit arithmetic, with distinct versioned stream labels.
  static double _unit(String key) {
    const modulus = 2147483647;
    var state = 1;
    for (final unit in key.codeUnits) {
      state = (state * 131 + unit) % modulus;
    }
    if (state == 0) state = 1;
    for (var round = 0; round < 4; round++) {
      state = (state * 48271) % modulus;
      state = state ^ (state >>> 13);
      if (state == 0) state = 1;
    }
    return state / modulus;
  }

  ConditionSample sample(Device device, DateTime recordedAt) {
    final key =
        'condition-v${SimulationConfig.conditionAlgorithmVersion}|${device.id}|${device.generationSequence}';
    var ticket = _unit('$key|mode') * totalWeight;
    var mode = eligibleModes.last;
    for (final candidate in eligibleModes) {
      if (ticket < candidate.weight) {
        mode = candidate;
        break;
      }
      ticket -= candidate.weight;
    }
    final values = <SensorMetric, double>{};
    for (final m in SensorMetric.values) {
      final required = mode.metric == m ? mode.status : ReadingStatus.inRange;
      final interval = _intervals[m]!.forStatus(required)!;
      final index =
          interval.first +
          (_unit('$key|value|${m.name}') * interval.count).floor();
      final value = _intervals[m]!.lattice.at(index);
      if (context.idealRanges![m]!.statusFor(value) != required) {
        throw StateError('Condition interval postcondition failed.');
      }
      values[m] = value;
    }
    final reading = SensorReading(
      recordedAt: recordedAt.toUtc(),
      sourceDeviceId: device.id,
      soilMoisture: values[SensorMetric.soilMoisture],
      light: values[SensorMetric.light],
      temperature: values[SensorMetric.temperature],
      humidity: values[SensorMetric.humidity],
    );
    final actual = PlantConditionCalculator.calculate(
      Plant(
        id: context.plantId,
        nickname: '',
        deviceId: device.id,
        profile: PlantProfile(
          id: 'simulation',
          plantType: '',
          ranges: context.idealRanges!,
        ),
        readings: [reading],
      ),
    );
    if (!actual.isComplete ||
        (mode == ManualPlantCondition.happy
            ? actual.assessment != HealthAssessment.healthy
            : actual.assessment != HealthAssessment.knownIssue ||
                  actual.metric != mode.metric ||
                  actual.direction != mode.status)) {
      throw StateError(
        'Generated packet disagrees with the plant condition calculator.',
      );
    }
    return ConditionSample(mode, reading);
  }
}

class _Span {
  const _Span(this.first, this.last);
  final int first, last;
  int get count => last - first + 1;
}

/// Canonical quantized lattice, plus the permitted clamped upper endpoint.
/// Subnormal lux uses 10,001 monotone domain fractions when scale overflows.
class _Lattice {
  _Lattice(SensorMetric metric, double lightMaximum) {
    minimum = metric == SensorMetric.temperature
        ? TemperatureDisplayConfig.minimumCelsius
        : 0;
    maximum = metric == SensorMetric.temperature
        ? TemperatureDisplayConfig.maximumCelsius
        : metric == SensorMetric.light
        ? lightMaximum
        : 100;
    scale = metric == SensorMetric.light && maximum < 100
        ? 10000 / maximum
        : SimulationConfig.metrics[metric]!.scale;
    fractional = !scale.isFinite;
    if (fractional) {
      firstTick = 0;
      gridCount = 10001;
      last = 10000;
    } else {
      firstTick = (minimum * scale).ceil();
      gridCount = math.max(0, (maximum * scale).floor() - firstTick + 1);
      final end = gridCount == 0
          ? minimum
          : ((firstTick + gridCount - 1) / scale).clamp(minimum, maximum);
      last = gridCount + (end < maximum ? 1 : 0) - 1;
    }
  }
  late final double minimum, maximum, scale;
  late final bool fractional;
  late final int firstTick, gridCount, last;
  double at(int i) => fractional
      ? maximum * (i / 10000)
      : i >= gridCount
      ? maximum
      : ((firstTick + i) / scale).clamp(minimum, maximum).toDouble();
  int firstWhere(bool Function(double) predicate) {
    var low = 0, high = last + 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (predicate(at(mid))) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }
}

class _MetricIntervals {
  _MetricIntervals(this.metric, this.range, double lightMaximum)
    : lattice = _Lattice(metric, lightMaximum) {
    final inStart = lattice.firstWhere(
      (v) => range.statusFor(v) != ReadingStatus.belowRange,
    );
    final aboveStart = lattice.firstWhere(
      (v) => range.statusFor(v) == ReadingStatus.aboveRange,
    );
    ideal = _span(inStart, aboveStart - 1);
    var belowEnd = inStart - 1, highStart = aboveStart;
    if (metric == SensorMetric.temperature) {
      // Exclude boundary-only C/F conversion noise, never weaken real statusFor.
      belowEnd = math.min(
        belowEnd,
        lattice.firstWhere(
              (v) =>
                  celsiusToFahrenheit(v) >=
                  celsiusToFahrenheit(range.minimum) - 1e-9,
            ) -
            1,
      );
      highStart = math.max(
        highStart,
        lattice.firstWhere(
          (v) =>
              celsiusToFahrenheit(v) >
              celsiusToFahrenheit(range.maximum) + 1e-9,
        ),
      );
    }
    // Prefer a visibly distinct displayed result if such lattice points exist.
    final shownMinimum = _shown(range.minimum),
        shownMaximum = _shown(range.maximum);
    final visibleBelow =
        lattice.firstWhere((v) => _shown(v) >= shownMinimum) - 1;
    if (visibleBelow >= 0) belowEnd = math.min(belowEnd, visibleBelow);
    final visibleAbove = lattice.firstWhere((v) => _shown(v) > shownMaximum);
    if (visibleAbove <= lattice.last) {
      highStart = math.max(highStart, visibleAbove);
    }
    below = _span(0, belowEnd);
    above = _span(highStart, lattice.last);
  }
  final SensorMetric metric;
  final TargetRange range;
  final _Lattice lattice;
  late final _Span? ideal, below, above;
  _Span? _span(int low, int high) =>
      low <= high && low >= 0 && high <= lattice.last ? _Span(low, high) : null;
  _Span? forStatus(ReadingStatus status) => switch (status) {
    ReadingStatus.inRange => ideal,
    ReadingStatus.belowRange => below,
    ReadingStatus.aboveRange => above,
    _ => null,
  };
  double _shown(double value) {
    if (metric == SensorMetric.light) {
      final s = LightDisplayConfig.number(value);
      return s.endsWith(LightDisplayConfig.compactSuffix)
          ? double.parse(s.substring(0, s.length - 1)) * 1000
          : double.parse(s);
    }
    return double.parse(
      (metric == SensorMetric.temperature ? celsiusToFahrenheit(value) : value)
          .toStringAsFixed(1),
    );
  }
}
