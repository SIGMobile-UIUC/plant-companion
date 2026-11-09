import 'plant_avatar_id.dart';
import 'plant_profile.dart';
import 'sensor_reading.dart';
import 'plant_commit.dart';
import '../config/plant_name_config.dart';
import '../config/temperature_display_config.dart';

const _unchangedFullName = Object();

enum PlantValidationKind { required, invalidRange, outOfBounds }

class PlantValidationError extends ArgumentError {
  PlantValidationError(this.kind, String message) : super(message);
  final PlantValidationKind kind;
}

/// No device identity or number is allocated until the save transaction.
/// An abandoned instance has no persistent side effects.
class PlantFormDraft {
  PlantFormDraft({
    required this.nickname,
    required this.speciesName,
    required this.avatar,
    required Map<SensorMetric, TargetRange> ranges,
    this.deviceId,
    this.createDevice = false,
    this.connectDevice = false,
    Object? fullName = _unchangedFullName,
    this.editToken,
  }) : ranges = Map.unmodifiable(ranges),
       updatesFullName = !identical(fullName, _unchangedFullName),
       fullName = identical(fullName, _unchangedFullName)
           ? null
           : fullName as String?;

  final String nickname;
  final String speciesName;
  final PlantAvatarId avatar;
  final Map<SensorMetric, TargetRange> ranges;
  final String? deviceId;
  final bool createDevice;
  final bool connectDevice;

  /// Omission preserves an existing value; an explicit null clears it.
  final String? fullName;
  final bool updatesFullName;
  final PlantEditToken? editToken;

  static (double, double) sensorBounds(SensorMetric metric) => switch (metric) {
    SensorMetric.soilMoisture || SensorMetric.humidity => (0.0, 100.0),
    SensorMetric.light => (0.0, 200000.0),
    SensorMetric.temperature => (
      TemperatureDisplayConfig.minimumCelsius,
      TemperatureDisplayConfig.maximumCelsius,
    ),
  };

  void validate() {
    if (!PlantNameConfig.accepts(
      fullName?.trim() ?? '',
      PlantNameConfig.fullNameInputMaxLength,
    )) {
      throw PlantValidationError(
        PlantValidationKind.outOfBounds,
        'Use at most 25 characters for Full Name.',
      );
    }
    if (nickname.trim().isEmpty || speciesName.trim().isEmpty) {
      throw PlantValidationError(
        PlantValidationKind.required,
        'Please fill in all required fields.',
      );
    }
    if (createDevice && deviceId != null) {
      throw ArgumentError('Choose an existing or a pending device, not both.');
    }
    for (final metric in SensorMetric.values) {
      final range = ranges[metric];
      if (range == null ||
          !range.minimum.isFinite ||
          !range.maximum.isFinite ||
          range.minimum >= range.maximum) {
        throw PlantValidationError(
          PlantValidationKind.invalidRange,
          'Each metric needs a finite minimum below its maximum.',
        );
      }
      final bounds = sensorBounds(metric);
      final tolerance = metric == SensorMetric.temperature
          ? TemperatureDisplayConfig.canonicalTolerance
          : 0.0;
      if (range.minimum < bounds.$1 - tolerance ||
          range.maximum > bounds.$2 + tolerance) {
        throw PlantValidationError(
          PlantValidationKind.outOfBounds,
          metric == SensorMetric.temperature
              ? TemperatureDisplayConfig.rangeError
              : 'Range outside supported sensor bounds.',
        );
      }
    }
  }

  Map<String, Object?> toJson() => {
    'nickname': nickname,
    'species': speciesName,
    'avatar': avatar.name,
    'ranges': {
      for (final m in SensorMetric.values)
        m.name: [ranges[m]?.minimum, ranges[m]?.maximum],
    },
    'deviceId': deviceId,
    'createDevice': createDevice,
    'connectDevice': connectDevice,
    'updatesFullName': updatesFullName,
    'fullName': fullName,
    'editToken': editToken?.toJson(),
  };
}
