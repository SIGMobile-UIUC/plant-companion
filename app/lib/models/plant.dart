import 'plant_profile.dart';
import 'sensor_reading.dart';
import 'plant_avatar_id.dart';

class Plant {
  const Plant({
    required this.id,
    required this.nickname,
    required this.profile,
    String? speciesName,
    this.avatar = PlantAvatarId.pothos,
    this.deviceId,
    this.readings = const [],
    this.createdAt,
    this.updatedAt,
    this.displayOrder = 0,
    this.fullName,
    this.profileRevision = 0,
  }) : _speciesName = speciesName;

  final String id;
  final String nickname;
  final PlantProfile profile;
  final String? _speciesName;
  String get speciesName => _speciesName ?? profile.plantType;
  final PlantAvatarId avatar;
  final String? deviceId;

  /// List snapshots carry only the latest packet. Retrieve retained history
  /// explicitly through PlantRepository.loadHistory when a caller needs it.
  final List<SensorReading> readings;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int displayOrder;
  final String? fullName;
  final int profileRevision;

  SensorReading? get latestReading => readings.isEmpty ? null : readings.first;

  Plant withoutDevice() => _copy(deviceId: null, readings: readings);
  Plant withReadings(List<SensorReading> updated) =>
      _copy(deviceId: deviceId, readings: updated);

  Plant _copy({
    required String? deviceId,
    required List<SensorReading> readings,
  }) => Plant(
    id: id,
    nickname: nickname,
    profile: profile,
    speciesName: speciesName,
    avatar: avatar,
    deviceId: deviceId,
    readings: List.unmodifiable(readings),
    createdAt: createdAt,
    updatedAt: updatedAt,
    displayOrder: displayOrder,
    fullName: fullName,
    profileRevision: profileRevision,
  );
}
