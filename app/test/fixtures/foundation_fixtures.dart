import 'package:drift/native.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/persistence/app_database.dart';
import 'package:plant_companion/persistence/sqlite_plant_repository.dart';
import 'package:plant_companion/services/clock.dart';
export 'device_connection.dart' show connectFixtureDevice;

class MutableClock implements Clock {
  MutableClock(this.value);
  DateTime value;
  @override
  DateTime now() => value.toUtc();
}

SqlitePlantRepository memoryRepository(MutableClock clock) =>
    SqlitePlantRepository(AppDatabase(NativeDatabase.memory()), clock: clock);

PlantFormDraft draft(
  String name, {
  bool createDevice = false,
  bool connectDevice = false,
  String? deviceId,
}) => PlantFormDraft(
  nickname: name,
  speciesName: 'Majikium flowerium',
  avatar: PlantAvatarId.pothos,
  ranges: PlantAvatarId.pothos.hints,
  createDevice: createDevice,
  connectDevice: connectDevice,
  deviceId: deviceId,
);
