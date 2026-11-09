import '../config/plant_name_config.dart';
import '../config/temperature_display_config.dart';
import '../utils/sensor_units.dart';
import 'plant_avatar_id.dart';
import 'plant_profile.dart';
import 'sensor_reading.dart';
import 'plant_form_draft.dart';

const formMetrics = [
  SensorMetric.soilMoisture,
  SensorMetric.light,
  SensorMetric.temperature,
  SensorMetric.humidity,
];
String rangeFieldKey(SensorMetric metric, int bound) =>
    'range-${metric.name}-$bound';

String scientificHint(PlantAvatarId avatar) => switch (avatar) {
  PlantAvatarId.pothos => 'Epipremnum aureum',
  PlantAvatarId.snakePlant => 'Dracaena trifasciata',
  PlantAvatarId.peaceLily => 'Spathiphyllum',
};
String avatarLabel(PlantAvatarId avatar) => switch (avatar) {
  PlantAvatarId.pothos => 'Pothos',
  PlantAvatarId.snakePlant => 'Snake Plant',
  PlantAvatarId.peaceLily => 'Peace Lily',
};

/// Canonical suggestions stay in Celsius. Only this input adapter converts them.
TargetRange displayHint(PlantAvatarId avatar, SensorMetric metric) {
  final r = avatar.hints[metric]!;
  return metric == SensorMetric.temperature
      ? TargetRange(
          celsiusToFahrenheit(r.minimum),
          celsiusToFahrenheit(r.maximum),
        )
      : r;
}

String inputNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();
String temperatureInputNumber(double value) =>
    value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

/// Keep ordinary Edit fields concise without rounding a valid interval closed.
List<String> temperatureRangeInputNumbers(TargetRange celsius) {
  final values = [
    celsiusToFahrenheit(celsius.minimum),
    celsiusToFahrenheit(celsius.maximum),
  ];
  final rounded = values.map(temperatureInputNumber).toList();
  if (values.any(
    (v) =>
        v < TemperatureDisplayConfig.minimumFahrenheit ||
        v > TemperatureDisplayConfig.maximumFahrenheit,
  )) {
    return values.map(inputNumber).toList();
  }
  return double.parse(rounded[0]) < double.parse(rounded[1])
      ? rounded
      : values.map(inputNumber).toList();
}

/// Raw text and validation are shared by Add/Edit; hints never enter these values.
class PlantFormInput {
  PlantFormInput({
    required this.nickname,
    required this.fullName,
    required this.species,
    required this.bounds,
  });
  final String nickname, fullName, species;
  final Map<SensorMetric, List<String>> bounds;
  bool get missing =>
      nickname.trim().isEmpty ||
      species.trim().isEmpty ||
      formMetrics.any((m) => bounds[m]!.any((s) => s.trim().isEmpty));
  Map<String, String> get errors {
    final errors = <String, String>{};
    if (nickname.trim().isEmpty) {
      errors['nickname-field'] = 'This field is required.';
    }
    if (!PlantNameConfig.accepts(
      fullName.trim(),
      PlantNameConfig.fullNameInputMaxLength,
    )) {
      errors['full-name-field'] = 'Use at most 25 characters.';
    }
    if (species.trim().isEmpty) {
      errors['species-field'] = 'This field is required.';
    }
    for (final m in formMetrics) {
      final values = bounds[m]!;
      for (var b = 0; b < 2; b++) {
        final text = values[b].trim(), key = rangeFieldKey(m, b);
        final value = double.tryParse(text);
        if (text.isEmpty) {
          errors[key] = 'This field is required.';
          continue;
        }
        if (value == null || !value.isFinite) {
          errors[key] = 'Enter a finite number.';
          continue;
        }
        final limits = PlantFormDraft.sensorBounds(m);
        final low = m == SensorMetric.temperature
            ? TemperatureDisplayConfig.minimumFahrenheit
            : limits.$1;
        final high = m == SensorMetric.temperature
            ? TemperatureDisplayConfig.maximumFahrenheit
            : limits.$2;
        if (value < low || value > high) {
          errors[key] = switch (m) {
            SensorMetric.temperature => TemperatureDisplayConfig.rangeError,
            SensorMetric.light => 'Use 0–200,000 lux.',
            _ => 'Use 0–100%.',
          };
        }
      }
      final minimum = double.tryParse(values[0].trim()),
          maximum = double.tryParse(values[1].trim());
      if (minimum != null &&
          maximum != null &&
          minimum.isFinite &&
          maximum.isFinite &&
          minimum >= maximum) {
        errors[rangeFieldKey(m, 1)] = 'Maximum must be greater than minimum.';
      }
    }
    return errors;
  }

  Map<SensorMetric, TargetRange> canonicalRanges({
    TargetRange? originalTemperature,
    List<String>? originalTemperatureText,
  }) => {
    for (final m in formMetrics)
      m: TargetRange(
        _canonicalBound(m, 0, originalTemperature, originalTemperatureText),
        _canonicalBound(m, 1, originalTemperature, originalTemperatureText),
      ),
  };
  double _canonicalBound(
    SensorMetric metric,
    int b,
    TargetRange? original,
    List<String>? originalText,
  ) {
    final value = double.parse(bounds[metric]![b].trim());
    if (metric != SensorMetric.temperature) return value;
    if (original != null &&
        originalText != null &&
        bounds[metric]![b].trim() == originalText[b]) {
      return b == 0 ? original.minimum : original.maximum;
    }
    return fahrenheitToCelsius(value);
  }

  Map<SensorMetric, TargetRange> previewRanges(
    PlantAvatarId avatar, {
    TargetRange? originalTemperature,
    List<String>? originalTemperatureText,
  }) {
    final invalid = errors;
    // Keep supported legacy temperatures truthful while the user corrects them.
    // Missing/nonfinite/reversed input still uses the existing hint fallback.
    TargetRange? legacyTemperature;
    final raw = bounds[SensorMetric.temperature]!;
    final low = double.tryParse(raw[0]), high = double.tryParse(raw[1]);
    if (originalTemperature != null &&
        originalTemperatureText != null &&
        low != null &&
        high != null &&
        low.isFinite &&
        high.isFinite &&
        low < high) {
      final candidate = TargetRange(
        _canonicalBound(
          SensorMetric.temperature,
          0,
          originalTemperature,
          originalTemperatureText,
        ),
        _canonicalBound(
          SensorMetric.temperature,
          1,
          originalTemperature,
          originalTemperatureText,
        ),
      );
      final minimum =
          originalTemperature.minimum < TemperatureDisplayConfig.minimumCelsius
          ? originalTemperature.minimum
          : TemperatureDisplayConfig.minimumCelsius;
      final maximum =
          originalTemperature.maximum > TemperatureDisplayConfig.maximumCelsius
          ? originalTemperature.maximum
          : TemperatureDisplayConfig.maximumCelsius;
      if (candidate.minimum >= minimum && candidate.maximum <= maximum) {
        legacyTemperature = candidate;
      }
    }
    return {
      for (final m in formMetrics)
        m: m == SensorMetric.temperature && legacyTemperature != null
            ? legacyTemperature
            : invalid.containsKey(rangeFieldKey(m, 0)) ||
                  invalid.containsKey(rangeFieldKey(m, 1))
            ? avatar.hints[m]!
            : TargetRange(
                _canonicalBound(
                  m,
                  0,
                  originalTemperature,
                  originalTemperatureText,
                ),
                _canonicalBound(
                  m,
                  1,
                  originalTemperature,
                  originalTemperatureText,
                ),
              ),
    };
  }
}
