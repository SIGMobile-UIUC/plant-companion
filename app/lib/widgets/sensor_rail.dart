import 'package:flutter/material.dart';
import '../models/plant_profile.dart';
import '../config/light_display_config.dart';
import '../config/temperature_display_config.dart';
import '../models/sensor_reading.dart';
import '../utils/sensor_scale.dart';
import '../utils/sensor_units.dart';
import '../theme/app_theme.dart';
import 'companion_header.dart';

const cardMetrics = [
  SensorMetric.soilMoisture,
  SensorMetric.light,
  SensorMetric.temperature,
  SensorMetric.humidity,
];
double displayValue(SensorMetric metric, double value) =>
    metric == SensorMetric.temperature ? celsiusToFahrenheit(value) : value;
String displayNumber(double value) =>
    value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
String metricUnit(SensorMetric metric) => switch (metric) {
  SensorMetric.soilMoisture || SensorMetric.humidity => '%',
  SensorMetric.light => ' lux',
  SensorMetric.temperature => '°F',
};
String metricNumber(
  SensorMetric metric,
  double value, {
  bool compactLight = true,
}) => metric == SensorMetric.light
    ? LightDisplayConfig.number(value, compact: compactLight)
    : displayNumber(displayValue(metric, value));
String metricValue(
  SensorMetric metric,
  double? value, {
  bool compactLight = true,
}) => value == null
    ? '—'
    : '${metricNumber(metric, value, compactLight: compactLight)}${metricUnit(metric)}';
String metricRange(
  SensorMetric metric,
  TargetRange range, {
  bool compactLight = true,
  bool includeChartNote = true,
}) {
  final text =
      '${metricNumber(metric, range.minimum, compactLight: compactLight)} – ${metricNumber(metric, range.maximum, compactLight: compactLight)}${metricUnit(metric)}';
  if (metric != SensorMetric.temperature || !includeChartNote) return text;
  final note = range.maximum < TemperatureDisplayConfig.minimumCelsius
      ? 'below chart'
      : range.minimum > TemperatureDisplayConfig.maximumCelsius
      ? 'above chart'
      : range.minimum < TemperatureDisplayConfig.minimumCelsius ||
            range.maximum > TemperatureDisplayConfig.maximumCelsius
      ? 'partly off chart'
      : null;
  return note == null ? text : '$text · $note';
}

String metricTitle(SensorMetric metric) =>
    metric == SensorMetric.soilMoisture ? 'Moisture' : metric.label;

/// One domain drives all fractions; light uses stable identity and saved bounds.
/// Coordinates include six pixels above the rail for the original marker.
enum SensorRailVariant { home, details }

class SensorRail extends StatelessWidget {
  const SensorRail({
    super.key,
    required this.metric,
    required this.range,
    required this.current,
    required this.plantId,
    this.variant = SensorRailVariant.home,
  });
  final SensorMetric metric;
  final TargetRange range;
  final double? current;
  final String plantId;
  final SensorRailVariant variant;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: variant == SensorRailVariant.details ? 22 : 21,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final detail = variant == SensorRailVariant.details;
        final railHeight = detail ? 10.0 : 9.0;
        final separatorWidth = detail ? 4.0 : 2.0;
        final domain = SensorScale.forMetric(
          metric,
          range,
          current,
          plantId: plantId,
        );
        final low =
            width * domain.fraction(displayValue(metric, range.minimum));
        final high =
            width * domain.fraction(displayValue(metric, range.maximum));
        final progress = current == null
            ? null
            : width * domain.fraction(displayValue(metric, current!));
        // Narrow light intervals keep their true positions. Thinner existing
        // strokes (at most half the interval each) avoid covering the whole band.
        final thickness = metric == SensorMetric.light
            ? ((high - low) / 2).clamp(0.0, separatorWidth)
            : separatorWidth;
        final markerWidth = width.clamp(0.0, detail ? 11.0 : 9.0);
        Widget separator(double edge, String key) {
          final (left, strokeWidth) = RailSlots.separator(
            edge,
            width,
            thickness,
            centerOffset: detail || metric == SensorMetric.light ? 0 : .040405,
          );
          return Positioned(
            left: left,
            top: detail ? 2 : 4,
            width: strokeWidth,
            height: detail ? 18 : 13,
            key: ValueKey(key),
            child: const ColoredBox(color: AppColors.separator),
          );
        }

        return ExcludeSemantics(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 6,
                width: width,
                height: railHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(detail ? 6 : 5),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: detail
                              ? const Color(0xFFCDD2C6)
                              : const Color(0xFFD1D4C8),
                        ),
                      ),
                      Positioned(
                        key: const ValueKey('rail-ideal'),
                        left: low,
                        top: 0,
                        width: high - low,
                        height: railHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: detail
                                ? const Color(0xFFA0C6A9)
                                : const Color(0xFFA3C6A3),
                            borderRadius: BorderRadius.circular(
                              detail ? 4.7 : 2,
                            ),
                          ),
                        ),
                      ),
                      // Original styling: progress covers the ideal overlap.
                      if (progress != null)
                        Positioned(
                          left: 0,
                          top: 0,
                          width: progress,
                          height: railHeight,
                          key: const ValueKey('rail-progress'),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color:
                                  (detail
                                  ? AppColors.detailSensors
                                  : AppColors.homeSensors)[cardMetrics.indexOf(
                                    metric,
                                  )],
                              borderRadius: BorderRadius.circular(
                                detail ? 6 : 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              separator(low, 'rail-min-separator'),
              separator(high, 'rail-max-separator'),
              if (progress != null)
                Positioned(
                  left: RailSlots.markerLeft(progress, width, markerWidth),
                  top: 0,
                  width: markerWidth,
                  height: detail ? 22 : 21,
                  key: const ValueKey('rail-marker'),
                  child: Image.asset(
                    '${companionAssets}sensors/current_marker.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
