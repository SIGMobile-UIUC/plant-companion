// Shared persistent plant fixtures for Home, Details and accessibility tests.
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/plant_repository.dart';
import 'package:plant_companion/utils/sensor_units.dart';
import 'device_connection.dart';

Future<void> populatePlantFixtures(
  PlantRepository repository,
  DateTime at, {
  int count = 3,
  String scenario = 'reference',
}) async {
  if (!['reference', 'long', 'conditions'].contains(scenario)) {
    throw ArgumentError.value(scenario, 'scenario', 'Unknown plant fixture');
  }
  await repository.initialize();
  for (final plant in await repository.loadPlants()) {
    await repository.deletePlant(plant.id);
  }
  for (var i = 0; i < count; i++) {
    final avatar = PlantAvatarId.values[i % 3];
    final ranges = {...avatar.hints};
    final noDevice = scenario == 'conditions' && i == 6;
    final name = scenario == 'long'
        ? 'A very long plant nickname that must wrap without hiding the selected companion $i'
        : i == 0
        ? 'Florence'
        : i == 1
        ? 'Snake Plant'
        : i == 2
        ? 'Peace Lily'
        : 'Companion ${i + 1}';
    final id = await repository.save(
      PlantFormDraft(
        nickname: name,
        speciesName: scenario == 'long'
            ? 'An unusually long scientific species name with enough detail to exercise responsive wrapping'
            : i % 3 == 0
            ? 'Epipremnum aureum'
            : i % 3 == 1
            ? 'Dracaena trifasciata'
            : 'Spathiphyllum wallisii',
        avatar: avatar,
        ranges: ranges,
        createDevice: !noDevice,
      ),
    );
    if (noDevice) continue;
    final device = await connectFixtureDevice(repository, id);
    if (scenario == 'conditions' && i == 9) continue;
    double? moisture = [38.0, 12.0, 52.0][i % 3];
    double? light = [280.0, 560.0, 430.0][i % 3];
    double? temperature = fahrenheitToCelsius([75.0, 72.0, 70.0][i % 3]);
    double? humidity = [42.0, 45.0, 58.0][i % 3];
    if (scenario == 'conditions') {
      moisture = ranges[SensorMetric.soilMoisture]!.midpoint;
      light = ranges[SensorMetric.light]!.midpoint;
      temperature = ranges[SensorMetric.temperature]!.midpoint;
      humidity = ranges[SensorMetric.humidity]!.midpoint;
      if (i == 0) light = ranges[SensorMetric.light]!.minimum - 50;
      if (i == 1) moisture = ranges[SensorMetric.soilMoisture]!.maximum + 10;
      if (i == 2) light = ranges[SensorMetric.light]!.maximum + 100;
      if (i == 3) temperature = ranges[SensorMetric.temperature]!.minimum - 5;
      if (i == 4) humidity = ranges[SensorMetric.humidity]!.maximum + 10;
      if (i == 7) {
        moisture = null;
        temperature = null;
        humidity = null;
      }
      if (i == 8) {
        moisture = null;
        light = ranges[SensorMetric.light]!.minimum - 50;
      }
    }
    await repository.commitReading(
      id,
      device,
      SensorReading(
        recordedAt: i == 2 && scenario == 'reference'
            ? at.subtract(const Duration(days: 2))
            : at,
        soilMoisture: moisture,
        light: light,
        temperature: temperature,
        humidity: humidity,
      ),
    );
    if (i == 2 && scenario == 'reference') {
      await repository.setConnection(device.id, false);
    }
  }
}
