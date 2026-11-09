import '../models/plant.dart';
import '../models/sensor_reading.dart';
import '../models/plant_profile.dart';

enum HealthAssessment { unassessed, healthy, knownIssue }

class MeasuredCondition {
  const MeasuredCondition(
    this.assessment, {
    this.metric,
    this.direction,
    this.isComplete = false,
  });
  final HealthAssessment assessment;
  final SensorMetric? metric;
  final ReadingStatus? direction;
  final bool isComplete;
}

class PlantConditionCalculator {
  static const priority = [
    SensorMetric.soilMoisture,
    SensorMetric.light,
    SensorMetric.temperature,
    SensorMetric.humidity,
  ];

  static MeasuredCondition calculate(Plant plant) {
    if (plant.deviceId == null || plant.latestReading == null) {
      return const MeasuredCondition(HealthAssessment.unassessed);
    }
    final reading = plant.latestReading!;
    final complete = priority.every((m) => reading.valueFor(m) != null);
    for (final metric in priority) {
      final status = plant.profile
          .rangeFor(metric)
          .statusFor(reading.valueFor(metric));
      if (status == ReadingStatus.belowRange ||
          status == ReadingStatus.aboveRange) {
        return MeasuredCondition(
          HealthAssessment.knownIssue,
          metric: metric,
          direction: status,
          isComplete: complete,
        );
      }
    }
    return MeasuredCondition(
      complete ? HealthAssessment.healthy : HealthAssessment.unassessed,
      isComplete: complete,
    );
  }
}

class ReadingPresentation {
  ReadingPresentation(Plant plant)
    : isDemonstration = plant.deviceId == null,
      values = {
        for (final metric in SensorMetric.values)
          metric: plant.deviceId == null
              ? plant.profile.rangeFor(metric).midpoint
              : plant.latestReading?.valueFor(metric),
      },
      timestamp = plant.deviceId == null
          ? null
          : plant.latestReading?.recordedAt;

  final bool isDemonstration;
  final Map<SensorMetric, double?> values;
  final DateTime? timestamp;
  String? get faceAsset =>
      isDemonstration ? 'assets/plant_companion/faces/sleeping.png' : null;
  String? get bubbleAsset => null;
}
