import 'plant_profile.dart';
import 'sensor_reading.dart';

enum DemoScenario { comfortable, thirsty, lowLight, disconnected, staleData }

extension DemoScenarioLabels on DemoScenario {
  String get label => switch (this) {
    DemoScenario.comfortable => 'Comfortable',
    DemoScenario.thirsty => 'Thirsty',
    DemoScenario.lowLight => 'Low light',
    DemoScenario.disconnected => 'Disconnected',
    DemoScenario.staleData => 'Stale data',
  };
}

class Plant {
  const Plant({
    required this.id,
    required this.nickname,
    required this.profile,
    this.deviceId,
    this.readings = const [],
    this.demoScenario = DemoScenario.comfortable,
  });

  final String id;
  final String nickname;
  final PlantProfile profile;
  final String? deviceId;
  final List<SensorReading> readings;
  final DemoScenario demoScenario;

  SensorReading? get latestReading => readings.isEmpty ? null : readings.first;

  Plant withoutDevice() => Plant(
    id: id,
    nickname: nickname,
    profile: profile,
    readings: readings,
    demoScenario: demoScenario,
  );

  Plant withReadings(List<SensorReading> updated, {DemoScenario? scenario}) =>
      Plant(
        id: id,
        nickname: nickname,
        profile: profile,
        deviceId: deviceId,
        readings: List.unmodifiable(updated),
        demoScenario: scenario ?? demoScenario,
      );
}
