// Test-only web entrypoint. Exercises the production SQLite browser executor,
// without adding app screens or using the user's normal browser profile.
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/widgets.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/persistence/database_connection.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';

@JS('globalThis.plantCompanionSmokeResult')
external set smokeResult(String value);

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final stage = Uri.base.queryParameters['stage'] ?? 'verify';
  final repository = SqlitePlantRepository(openAppDatabase());
  try {
    await repository.initialize();
    if (stage == 'create') {
      check(
        (await repository.loadPlants()).length == 1,
        'Expected isolated fresh database',
      );
      final id = await repository.save(
        PlantFormDraft(
          nickname: 'Browser created',
          speciesName: 'Browser test species',
          avatar: PlantAvatarId.pothos,
          ranges: PlantAvatarId.pothos.hints,
          createDevice: true,
        ),
      );
      final disconnected = (await repository.loadAssignedDevices())[id]!;
      check(
        !disconnected.isConnected,
        'Draft creation must not imply connection',
      );
      final device = await repository.reconnectAssigned(id, disconnected);
      check(device != null && device.isConnected, 'Explicit connection failed');
      check(
        await repository.commitReading(
          id,
          device!,
          SensorReading(recordedAt: DateTime.now().toUtc(), light: 731),
        ),
        'Test packet did not commit',
      );
    } else if (stage == 'edit') {
      final plant = (await repository.loadPlants()).last;
      check(
        plant.nickname == 'Browser created',
        'Created plant did not survive navigation',
      );
      await repository.save(
        PlantFormDraft(
          nickname: 'Browser edited',
          speciesName: 'Browser edited species',
          avatar: PlantAvatarId.snakePlant,
          ranges: PlantAvatarId.snakePlant.hints,
          deviceId: plant.deviceId,
        ),
        plantId: plant.id,
      );
    } else {
      check(stage == 'verify', 'Unknown smoke stage');
    }
    final plants = await repository.loadPlants();
    check(plants.length == 2, 'Plant count changed');
    final plant = plants.last;
    if (stage != 'create') {
      check(plant.nickname == 'Browser edited', 'Edited nickname missing');
      check(
        plant.speciesName == 'Browser edited species',
        'Edited species missing',
      );
      check(plant.avatar == PlantAvatarId.snakePlant, 'Edited avatar missing');
      check(
        plant.profile.ranges[SensorMetric.light]!.minimum ==
            PlantAvatarId.snakePlant.hints[SensorMetric.light]!.minimum,
        'Edited range missing',
      );
    }
    check(plant.latestReading?.light == 731, 'Persisted packet missing');
    final history = await repository.loadHistory(plant.id);
    check(history.length == 1, 'History changed across reopen');
    final device = (await repository.loadAssignedDevices())[plant.id]!;
    check(
      device.id == 'device-2' && device.displayOrdinal == 2,
      'Assignment changed',
    );
    final result = {
      'ok': true,
      'stage': stage,
      'plantId': plant.id,
      'nickname': plant.nickname,
      'deviceId': device.id,
      'packetId': history.single.id,
      'recordedAt': history.single.recordedAt.toIso8601String(),
      'historyCount': history.length,
    };
    await repository.close();
    smokeResult = jsonEncode(result);
  } catch (error, stack) {
    await repository.close();
    smokeResult = jsonEncode({
      'ok': false,
      'stage': stage,
      'error': '$error',
      'stack': '$stack',
    });
  }
}
