enum SensorMetric { soilMoisture, temperature, humidity, light }

extension SensorMetricLabels on SensorMetric {
  String get label => switch (this) {
    SensorMetric.soilMoisture => 'Soil moisture',
    SensorMetric.temperature => 'Temperature',
    SensorMetric.humidity => 'Humidity',
    SensorMetric.light => 'Light',
  };

  String get unit => switch (this) {
    SensorMetric.soilMoisture => 'index / 100',
    SensorMetric.temperature => '°C',
    SensorMetric.humidity => '% RH',
    SensorMetric.light => 'lux',
  };

  String format(double value) => this == SensorMetric.temperature
      ? value.toStringAsFixed(1)
      : value.toStringAsFixed(0);
}

class SensorReading {
  const SensorReading({
    required this.recordedAt,
    this.soilMoisture,
    this.temperature,
    this.humidity,
    this.light,
  });

  final DateTime recordedAt;
  final double? soilMoisture;
  final double? temperature;
  final double? humidity;
  final double? light;

  double? valueFor(SensorMetric metric) => switch (metric) {
    SensorMetric.soilMoisture => soilMoisture,
    SensorMetric.temperature => temperature,
    SensorMetric.humidity => humidity,
    SensorMetric.light => light,
  };
}
