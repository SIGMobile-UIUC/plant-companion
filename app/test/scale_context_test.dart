import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/services/plant_condition_calculator.dart';
import 'package:plant_companion/services/reading_scheduler.dart';
import 'package:plant_companion/services/sensor_gateway.dart';
import 'package:plant_companion/utils/sensor_units.dart';
import 'fixtures/foundation_fixtures.dart';

class ScaleGate extends FakeSensorRepository {
  ScaleGate() : super(delay: Duration.zero);
  final contexts = <PlantSimulationContext>[];
  Completer<void>? started, release;
  bool fail = false;
  @override
  Future<SensorReading> acquire(
    Device d,
    DateTime at, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
    PlantSimulationContext? plantContext,
  }) async {
    contexts.add(plantContext!);
    if (fail) throw StateError('injected');
    final r = await super.acquire(
      d,
      at,
      previousReading: previousReading,
      simulationMode: simulationMode,
      plantContext: plantContext,
    );
    started?.complete();
    started = null;
    if (release != null) await release!.future;
    return r;
  }
}

class HardwareGate implements SensorGateway {
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<SensorReading> acquire(
    Device d,
    DateTime at, {
    SensorReading? previousReading,
    SimulationMode simulationMode = SimulationMode.environment,
  }) async {
    started.complete();
    await release.future;
    return SensorReading(recordedAt: at, light: 310, temperature: 20);
  }
}

class ScaleDb extends AppDatabase {
  ScaleDb(super.executor);
  int queries = 0;
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) {
    queries++;
    return super.rows(sql, args);
  }
}

void main() {
  late MutableClock clock;
  late SqlitePlantRepository repo;
  late ScaleGate gate;
  late ReadingScheduler scheduler;
  setUp(() async {
    clock = MutableClock(DateTime.utc(2026, 11, 7, 12));
    repo = memoryRepository(clock);
    await repo.initialize();
    gate = ScaleGate();
    scheduler = ReadingScheduler(repo, gate, clock: clock);
  });
  tearDown(() async {
    scheduler.dispose();
    await repo.close();
  });
  Future<DeviceReadingContext> context([String id = 'plant-1']) async =>
      (await repo.loadAcquisitionContext(id))!;
  Future<void> edit({
    TargetRange light = const TargetRange(400, 850),
    String nickname = 'Edited',
    TargetRange? temperature,
  }) async {
    await repo.save(
      PlantFormDraft(
        nickname: nickname,
        speciesName: 'Test species',
        avatar: PlantAvatarId.snakePlant,
        deviceId: 'device-1',
        fullName: 'Test full name',
        ranges: {
          ...PlantAvatarId.pothos.hints,
          SensorMetric.light: light,
          SensorMetric.temperature: ?temperature,
        },
      ),
      plantId: 'plant-1',
    );
  }

  test(
    'one context query returns current committed ID, light bounds and profile revision',
    () async {
      final r = SqlitePlantRepository(
        ScaleDb(NativeDatabase.memory()),
        clock: clock,
      );
      try {
        await r.initialize();
        final before = (r.database as ScaleDb).queries;
        final c = (await r.loadAcquisitionContext('plant-1'))!;
        expect((r.database as ScaleDb).queries - before, 1);
        expect(c.plantId, 'plant-1');
        expect(c.profileRevision, 0);
        expect((c.lightRange.minimum, c.lightRange.maximum), (400, 850));
      } finally {
        await r.close();
      }
    },
  );
  test(
    'committed light edit supersedes stale cached/draft bounds without changing old packets',
    () async {
      final before = await repo.database.rows('SELECT * FROM sensor_readings');
      await edit(light: const TargetRange(20000, 60000));
      expect(await repo.database.rows('SELECT * FROM sensor_readings'), before);
      expect(
        await scheduler.refreshAssigned('plant-1', gate),
        RefreshResult.updated,
      );
      expect(gate.contexts.single.plantId, 'plant-1');
      expect(gate.contexts.single.lightMaximum, (40000 / .30));
      expect(
        (await context()).previousReading!.light,
        inInclusiveRange(0, (40000 / .30)),
      );
    },
  );
  test(
    'in-flight profile edit rejects stale simulated packet without generation consumption',
    () async {
      final entered = gate.started = Completer<void>();
      gate.release = Completer<void>();
      final pending = scheduler.refreshAssigned('plant-1', gate);
      await entered.future;
      await edit(light: const TargetRange(20000, 60000));
      gate.release!.complete();
      expect(await pending, RefreshResult.acquisitionFailed);
      expect((await context()).device.generationSequence, 0);
      expect((await repo.loadHistory('plant-1')).length, 1);
      expect(
        await scheduler.refreshAssigned('plant-1', gate),
        RefreshResult.updated,
      );
      expect(gate.contexts.map((c) => c.lightMaximum), [1500, (40000 / .30)]);
      expect((await context()).device.generationSequence, 1);
    },
  );
  test(
    'hardware capability has no plant-care argument or simulation profile guard',
    () async {
      final hardware = HardwareGate();
      scheduler.dispose();
      scheduler = ReadingScheduler(repo, hardware, clock: clock);
      final pending = scheduler.refresh('plant-1');
      await hardware.started.future;
      await edit(light: const TargetRange(20000, 60000));
      hardware.release.complete();
      expect(await pending, isTrue);
      expect((await context()).previousReading!.light, 310);
    },
  );
  test(
    'automatic projects legacy extremes only for next calculation; history and timestamps stay exact',
    () async {
      final c = await context();
      clock.value = clock.now().add(const Duration(seconds: 1));
      await repo.commitReading(
        'plant-1',
        c.device,
        SensorReading(
          recordedAt: clock.now(),
          light: 200000,
          temperature: 100,
          soilMoisture: 38,
          humidity: 42,
        ),
      );
      final old = await repo.database.rows('SELECT * FROM sensor_readings');
      clock.value = c.device.createdAt!.add(const Duration(minutes: 20));
      await scheduler.processDue();
      final first = (await context()).previousReading!;
      expect(first.light, inInclusiveRange(1280, 1500));
      expect(
        first.temperature,
        inInclusiveRange(
          fahrenheitToCelsius(120) - .4001,
          fahrenheitToCelsius(120),
        ),
      );
      final rows = await repo.database.rows('SELECT * FROM sensor_readings');
      for (final r in old) {
        expect(rows.firstWhere((x) => x['id'] == r['id']), r);
      }
      expect((await context()).device.lastAutoSlot, 1);
      expect(first.recordedAt, clock.now());
      clock.value = clock.now().add(const Duration(minutes: 20));
      await scheduler.processDue();
      final second = (await context()).previousReading!;
      expect((second.light! - first.light!).abs(), lessThanOrEqualTo(220.01));
      expect(
        (second.temperature! - first.temperature!).abs(),
        lessThanOrEqualTo(.4001),
      );
      expect((await context()).device.lastAutoSlot, 2);
    },
  );
  test(
    'unrelated names/full name/temperature ideals cannot change light ceiling or rewrite ranges',
    () async {
      final before = await context();
      await edit(
        nickname: 'New nickname',
        temperature: TargetRange(
          fahrenheitToCelsius(30),
          fahrenheitToCelsius(100),
        ),
      );
      final after = await context();
      expect(after.plantId, before.plantId);
      expect((after.lightRange.minimum, after.lightRange.maximum), (400, 850));
      expect(
        PlantSimulationContext(
          plantId: after.plantId,
          lightRange: after.lightRange,
        ).lightMaximum,
        1500,
      );
      final p = (await repo.loadPlants()).single;
      expect(
        p.profile.rangeFor(SensorMetric.temperature).maximum,
        fahrenheitToCelsius(100),
      );
      expect((await repo.loadHistory('plant-1')).length, 1);
    },
  );
  test(
    'conditions use real 115F and genuine ideals rather than chart coordinates',
    () {
      final ranges = {
        ...PlantAvatarId.pothos.hints,
        SensorMetric.soilMoisture: const TargetRange(0, 100),
        SensorMetric.light: const TargetRange(0, 200000),
        SensorMetric.humidity: const TargetRange(0, 100),
      };
      final p = Plant(
        id: 'test',
        nickname: 'Test',
        deviceId: 'device-1',
        profile: PlantProfile(id: 'test', plantType: 'Test', ranges: ranges),
        readings: [
          SensorReading(
            recordedAt: clock.now(),
            soilMoisture: 50,
            light: 500,
            temperature: fahrenheitToCelsius(115),
            humidity: 50,
          ),
        ],
      );
      final condition = PlantConditionCalculator.calculate(p);
      expect(condition.metric, SensorMetric.temperature);
      expect(condition.direction, ReadingStatus.aboveRange);
    },
  );
  test(
    'file-backed v2 restart preserves out-of-axis ideals, light ceiling, sequence and old packets',
    () async {
      final dir = await Directory.systemTemp.createTemp('scale-v2-'),
          file = File('${dir.path}/data.sqlite');
      var disk = SqlitePlantRepository(
        AppDatabase(NativeDatabase(file)),
        clock: clock,
      );
      try {
        await disk.initialize();
        await disk.database.customStatement(
          "UPDATE plant_ranges SET minimum=?,maximum=? WHERE plant_id='plant-1' AND metric='temperature'",
          [fahrenheitToCelsius(65), fahrenheitToCelsius(150)],
        );
        var run = ReadingScheduler(disk, gate, clock: clock);
        await run.refresh('plant-1');
        run.dispose();
        final rows = await disk.database.rows('SELECT * FROM sensor_readings'),
            before = (await disk.loadAcquisitionContext('plant-1'))!;
        await disk.close();
        disk = SqlitePlantRepository(
          AppDatabase(NativeDatabase(file)),
          clock: clock,
        );
        await disk.initialize();
        expect(await disk.database.rows('SELECT * FROM sensor_readings'), rows);
        final after = (await disk.loadAcquisitionContext('plant-1'))!;
        expect(
          after.device.generationSequence,
          before.device.generationSequence,
        );
        expect(after.device.createdAt, before.device.createdAt);
        expect(
          (await disk.loadPlants()).single.profile
              .rangeFor(SensorMetric.temperature)
              .maximum,
          fahrenheitToCelsius(150),
        );
        run = ReadingScheduler(disk, gate, clock: clock);
        await run.refresh('plant-1');
        run.dispose();
        expect(
          (await disk.loadAcquisitionContext(
            'plant-1',
          ))!.device.generationSequence,
          before.device.generationSequence + 1,
        );
      } finally {
        await disk.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
