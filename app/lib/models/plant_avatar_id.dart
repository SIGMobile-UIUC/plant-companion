import 'plant_profile.dart';
import 'sensor_reading.dart';

enum PlantAvatarId {
  pothos('plants/pothos.png'),
  snakePlant('plants/snake_plant.png'),
  peaceLily('plants/peace_lily.png');

  const PlantAvatarId(this.asset);
  final String asset;
  String get assetPath => 'assets/plant_companion/$asset';

  Map<SensorMetric, TargetRange> get hints => switch (this) {
    pothos => {
      SensorMetric.soilMoisture: const TargetRange(30, 60),
      SensorMetric.light: const TargetRange(400, 850),
      SensorMetric.temperature: const TargetRange(
        18.333333333333332,
        29.444444444444443,
      ),
      SensorMetric.humidity: const TargetRange(40, 70),
    },
    snakePlant => {
      SensorMetric.soilMoisture: const TargetRange(20, 50),
      SensorMetric.light: const TargetRange(500, 900),
      SensorMetric.temperature: const TargetRange(
        18.333333333333332,
        29.444444444444443,
      ),
      SensorMetric.humidity: const TargetRange(30, 60),
    },
    peaceLily => {
      SensorMetric.soilMoisture: const TargetRange(40, 70),
      SensorMetric.light: const TargetRange(300, 800),
      SensorMetric.temperature: const TargetRange(
        18.333333333333332,
        26.666666666666668,
      ),
      SensorMetric.humidity: const TargetRange(50, 75),
    },
  };
}
