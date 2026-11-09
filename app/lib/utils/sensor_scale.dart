import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import '../config/light_display_config.dart';
import '../config/temperature_display_config.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';
import 'sensor_units.dart';

class SensorScale {
  const SensorScale(this.minimum, this.maximum);
  final double minimum;
  final double maximum;

  factory SensorScale.forMetric(
    SensorMetric metric,
    TargetRange range,
    double? current, {
    required String plantId,
  }) {
    var low = range.minimum;
    var high = range.maximum;
    if (metric == SensorMetric.temperature) {
      low = celsiusToFahrenheit(low);
      high = celsiusToFahrenheit(high);
      current = current == null ? null : celsiusToFahrenheit(current);
    }
    if (!low.isFinite ||
        !high.isFinite ||
        low >= high ||
        (current != null && !current.isFinite)) {
      throw ArgumentError('Cannot scale invalid measurements.');
    }
    return switch (metric) {
      SensorMetric.soilMoisture ||
      SensorMetric.humidity => const SensorScale(0, 100),
      SensorMetric.light => SensorScale(
        LightDisplayConfig.minimumLux,
        math.max(
          _lightMaximum(plantId, range),
          (range.maximum - range.minimum) /
              LightDisplayConfig.maximumIdealLightFraction,
        ),
      ),
      SensorMetric.temperature => SensorScale(
        TemperatureDisplayConfig.minimumFahrenheit,
        TemperatureDisplayConfig.maximumFahrenheit,
      ),
    };
  }

  double fraction(double value) =>
      ((value - minimum) / (maximum - minimum)).clamp(0.0, 1.0);
}

/// A pure display calculation: only immutable identity and saved care bounds
/// select the maximum. Readings, clocks, process hashes and SQLite are absent.
double _lightMaximum(String plantId, TargetRange range) {
  if (plantId.isEmpty || range.minimum < LightDisplayConfig.minimumLux) {
    throw ArgumentError(
      'Light scaling needs a plant ID and nonnegative range.',
    );
  }
  final lower = range.maximum / LightDisplayConfig.preferredIdealMaximum;
  final upper = range.minimum / LightDisplayConfig.preferredIdealMinimum;
  if (lower >= upper) return lower; // Empty or single-value feasible interval.

  // Canonical IEEE-754 bytes avoid VM/web double-to-string differences. The
  // 31-bit polynomial's intermediates stay below 2^53 on both Dart VM and JS.
  final bounds = ByteData(16)
    ..setFloat64(0, range.minimum, Endian.big)
    ..setFloat64(8, range.maximum, Endian.big);
  var hash = LightDisplayConfig.stableHashSeed;
  for (final byte in [
    ...utf8.encode(plantId),
    0,
    ...bounds.buffer.asUint8List(),
  ]) {
    hash =
        (hash * LightDisplayConfig.stableHashMultiplier + byte) &
        LightDisplayConfig.stableHashMask;
  }

  // Use decimal steps without logarithms near powers of ten. At most ~90
  // two-significant-digit candidates lie in any valid positioning interval.
  var step = 1.0;
  while (step * 10 <= upper) {
    step *= 10;
  }
  while (step > upper) {
    step /= 10;
  }
  for (
    var digit = 1;
    digit < LightDisplayConfig.maximumSignificantDigits;
    digit++
  ) {
    step /= 10;
  }
  if (step > 0) {
    var first = (lower / step).ceil();
    var last = (upper / step).floor();
    // Floating multiplication must not round an endpoint outside the interval.
    if (first * step < lower) first++;
    if (last * step > upper) last--;
    if (first <= last) return (first + hash % (last - first + 1)) * step;
  }
  final unit = hash / (LightDisplayConfig.stableHashMask + 1);
  return (lower + (upper - lower) * unit).clamp(lower, upper);
}

/// Shared visual containment, independent of the numeric domain/fractions.
abstract final class RailSlots {
  static double markerLeft(
    double position,
    double railWidth,
    double markerWidth,
  ) => (position - markerWidth / 2).clamp(
    0.0,
    math.max(0.0, railWidth - markerWidth),
  );

  /// Clip a centered stroke rather than moving its actual boundary position.
  static (double left, double width) separator(
    double edge,
    double railWidth,
    double thickness, {
    double centerOffset = 0,
  }) {
    final left = (edge + centerOffset - thickness / 2).clamp(0.0, railWidth);
    final right = (edge + centerOffset + thickness / 2).clamp(0.0, railWidth);
    return (left, math.max(0.0, right - left));
  }
}
