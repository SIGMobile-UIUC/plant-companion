import 'package:flutter/material.dart';
import '../models/plant.dart';
import '../models/plant_avatar_id.dart';
import '../models/portrait_geometry.dart';
import '../models/sensor_reading.dart';
import '../models/plant_profile.dart';
import '../services/plant_condition_calculator.dart';
import '../theme/app_theme.dart';
import 'companion_header.dart';

class PlantAppearance {
  PlantAppearance.preview({
    this.face,
    this.need,
    this.excess = false,
    required this.description,
  });
  PlantAppearance(Plant plant, {bool detail = false}) {
    final condition = PlantConditionCalculator.calculate(plant);
    if (plant.deviceId == null) {
      face = 'faces/sleeping.png';
      description =
          '${plant.nickname}: no assigned sensor; demonstration values, health unassessed.';
    } else if (condition.assessment == HealthAssessment.healthy) {
      face = 'faces/happy.png';
      if (detail) need = 'needs/happy_heart.png';
      description =
          '${plant.nickname}: all readings are within their ideal ranges.';
    } else if (condition.assessment == HealthAssessment.knownIssue) {
      final metric = condition.metric!;
      final below = condition.direction == ReadingStatus.belowRange;
      face = metric == SensorMetric.light && below
          ? 'faces/sleeping.png'
          : 'faces/sad.png';
      need = conditionNeedAsset(metric, below: below);
      excess = excessNeed(metric, below: below);
      description =
          '${plant.nickname}: ${metric.label.toLowerCase()} is ${below ? 'below' : 'above'} the ideal range.${condition.isComplete ? '' : ' Some readings are unavailable.'}';
    } else {
      description =
          '${plant.nickname}: readings unavailable or incomplete; health unassessed.';
    }
  }
  String? face;
  String? need;
  bool excess = false;
  late String description;
}

// Presentation only: measurement priority and direction come from the calculator.
String conditionNeedAsset(SensorMetric metric, {required bool below}) =>
    metric == SensorMetric.temperature && below
    ? 'needs/cold_thermometer.png'
    : sensorAsset(metric);

bool excessNeed(SensorMetric metric, {required bool below}) =>
    !below && metric != SensorMetric.temperature;

String sensorAsset(SensorMetric metric) => switch (metric) {
  SensorMetric.soilMoisture => 'sensors/soil_moisture.png',
  SensorMetric.light => 'sensors/light.png',
  SensorMetric.temperature => 'sensors/temperature.png',
  SensorMetric.humidity => 'sensors/humidity.png',
};

/// Original independent layers in measured pot-relative coordinates.
class PlantPortrait extends StatelessWidget {
  const PlantPortrait({
    super.key,
    required this.avatar,
    required this.appearance,
    this.width = 152,
    this.detail = false,
  });
  final PlantAvatarId avatar;
  final PlantAppearance appearance;
  final double width;
  final bool detail;
  @override
  Widget build(BuildContext context) {
    final geometry = PortraitGeometry(
      avatar,
      detail: detail,
      scale: width / (detail ? 212.8 : 152),
    );
    Widget layer(Rect rect, String asset, String name) => Positioned.fromRect(
      rect: rect,
      child: Image.asset(
        '$companionAssets$asset',
        key: ValueKey(name),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
      ),
    );
    final layers = Stack(
      clipBehavior: Clip.none,
      children: [
        layer(geometry.plant, avatar.asset, 'plant-sprite'),
        if (appearance.face != null)
          layer(geometry.face, appearance.face!, 'plant-face'),
        if (appearance.need != null) ...[
          layer(
            geometry.bubble,
            'needs/thought_bubble_tight.png',
            'thought-bubble',
          ),
          layer(
            appearance.need == 'needs/happy_heart.png'
                ? geometry.heartIcon
                : geometry.sensorIcon,
            appearance.need!,
            'need-icon',
          ),
          if (appearance.excess)
            layer(geometry.slashIcon, 'needs/excess_slash.png', 'need-slash'),
        ],
      ],
    );
    return Semantics(
      image: true,
      label: appearance.description,
      child: ExcludeSemantics(
        child: SizedBox(
          width: geometry.size.width,
          height: geometry.size.height,
          // Details is transparent over the rounded hero. Do not put the
          // overflowing bubble (or plant slot) under the homepage panel clip.
          child: detail
              ? layers
              : ClipRRect(
                  borderRadius: BorderRadius.circular(17 * width / 152),
                  child: ColoredBox(color: AppColors.sage, child: layers),
                ),
        ),
      ),
    );
  }
}
