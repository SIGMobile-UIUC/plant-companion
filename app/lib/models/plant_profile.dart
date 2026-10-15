import 'sensor_reading.dart';

enum ReadingStatus { unavailable, belowRange, inRange, aboveRange }

class TargetRange {
  const TargetRange(this.minimum, this.maximum);

  final double minimum;
  final double maximum;

  double get midpoint => (minimum + maximum) / 2;

  ReadingStatus statusFor(double? value) {
    if (value == null) return ReadingStatus.unavailable;
    if (value < minimum) return ReadingStatus.belowRange;
    if (value > maximum) return ReadingStatus.aboveRange;
    return ReadingStatus.inRange;
  }

  String format(SensorMetric metric) =>
      '${metric.format(minimum)}–${metric.format(maximum)} ${metric.unit}';
}

class PlantProfile {
  const PlantProfile({
    required this.id,
    required this.plantType,
    required this.ranges,
  });

  final String id;
  final String plantType;
  final Map<SensorMetric, TargetRange> ranges;

  TargetRange rangeFor(SensorMetric metric) => ranges[metric]!;

  // These deliberately shared defaults are teaching examples, not species advice.
  static const demonstrationRanges = {
    SensorMetric.soilMoisture: TargetRange(35, 70),
    SensorMetric.temperature: TargetRange(18, 28),
    SensorMetric.humidity: TargetRange(40, 70),
    SensorMetric.light: TargetRange(500, 2000),
  };

  static const samples = [
    PlantProfile(
      id: 'monstera',
      plantType: 'Monstera',
      ranges: demonstrationRanges,
    ),
    PlantProfile(
      id: 'pothos',
      plantType: 'Pothos',
      ranges: demonstrationRanges,
    ),
    PlantProfile(
      id: 'snake',
      plantType: 'Snake plant',
      ranges: demonstrationRanges,
    ),
    PlantProfile(
      id: 'custom',
      plantType: 'Custom',
      ranges: demonstrationRanges,
    ),
  ];
}
