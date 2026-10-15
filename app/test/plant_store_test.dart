import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/state/plant_store.dart';

void main() {
  late PlantStore store;
  setUp(() {
    store = PlantStore(repository: FakeSensorRepository(delay: Duration.zero));
  });
  tearDown(() {
    store.dispose();
  });

  test(
    'a disconnected device preserves a recent reading and timestamp',
    () async {
      final saved = store.plants.first.latestReading!;
      store.setDemoScenario('plant-1', DemoScenario.disconnected);
      expect(store.deviceFor(store.plants.first)!.isConnected, isFalse);
      expect(store.isStale(store.plants.first), isFalse);
      expect(store.plants.first.latestReading, same(saved));
      await store.refresh('plant-1');
      expect(store.plants.first.latestReading, same(saved));
    },
  );

  test(
    'stale data and repeat refresh preserve the original packet timestamp',
    () async {
      store.setDemoScenario('plant-1', DemoScenario.staleData);
      final saved = store.plants.first.latestReading!;
      expect(store.isStale(store.plants.first), isTrue);
      expect(store.deviceFor(store.plants.first)!.isConnected, isTrue);
      await store.refresh('plant-1');
      await store.refresh('plant-1');
      store.setDemoScenario('plant-1', DemoScenario.staleData);
      expect(store.plants.first.latestReading, same(saved));
      store.setDemoScenario('plant-1', DemoScenario.comfortable);
      expect(store.isStale(store.plants.first), isFalse);
    },
  );

  test('device uniqueness is enforced by shared state', () {
    expect(
      () => store.addPlant(
        nickname: 'Other',
        profile: PlantProfile.samples.first,
        device: FakeSensorRepository.demoDevice,
      ),
      throwsStateError,
    );
    expect(store.plants, hasLength(1));
    store.unlinkDevice('plant-1');
    store.addPlant(
      nickname: 'Other',
      profile: PlantProfile.samples.first,
      device: FakeSensorRepository.demoDevice,
    );
    expect(store.plants.last.deviceId, FakeSensorRepository.demoDevice.id);
    expect(store.plants.first.deviceId, isNull);
    expect(store.plants.first.readings, hasLength(3));
  });

  test('unlinked plants have unavailable readings rather than zero values', () {
    store.addPlant(nickname: 'Other', profile: PlantProfile.samples.first);
    expect(store.plants.last.latestReading, isNull);
    expect(
      PlantProfile.demonstrationRanges[SensorMetric.soilMoisture]!.statusFor(
        null,
      ),
      ReadingStatus.unavailable,
    );
  });

  test('dry and dim scenes respect custom demonstration ranges', () {
    final profile = PlantProfile(
      id: 'custom',
      plantType: 'Test plant',
      ranges: {
        ...PlantProfile.demonstrationRanges,
        SensorMetric.soilMoisture: const TargetRange(5, 15),
        SensorMetric.light: const TargetRange(1000, 2000),
      },
    );
    final dry = store.repository.makeReading(
      profile,
      DemoScenario.thirsty,
      DateTime.now(),
    );
    final dim = store.repository.makeReading(
      profile,
      DemoScenario.lowLight,
      DateTime.now(),
    );
    expect(dry.soilMoisture, inInclusiveRange(0, 4.99));
    expect(dim.light, inInclusiveRange(0, 999));
  });

  test(
    'low-light demo changes the reading without mislabeling soil as a percent',
    () {
      store.setDemoScenario('plant-1', DemoScenario.lowLight);
      expect(store.plants.first.latestReading!.light, 80);
      expect(SensorMetric.soilMoisture.unit, 'index / 100');
    },
  );
}
