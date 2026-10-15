import 'package:flutter/material.dart';
import '../models/device.dart';
import '../models/plant.dart';
import '../models/sensor_reading.dart';

class PlantCondition {
  const PlantCondition(
    this.label,
    this.explanation,
    this.icon, {
    this.attention = false,
  });
  final String label;
  final String explanation;
  final IconData icon;
  final bool attention;

  factory PlantCondition.forPlant(
    Plant plant,
    Device? device, {
    required bool isStale,
  }) {
    if (device == null) {
      return PlantCondition(
        'No device',
        plant.latestReading == null
            ? 'This plant has no device. Readings are unavailable.'
            : 'Device unlinked. These are saved readings, not live measurements.',
        Icons.sensors_off,
      );
    }
    if (isStale) {
      return const PlantCondition(
        'Stale data',
        'The last reading is over 30 minutes old. Its timestamp is preserved.',
        Icons.history,
        attention: true,
      );
    }
    if (!device.isConnected) {
      return const PlantCondition(
        'Disconnected',
        'The device is disconnected. Saved readings can still be recent.',
        Icons.bluetooth_disabled,
        attention: true,
      );
    }
    if (plant.latestReading == null) {
      return const PlantCondition(
        'Awaiting a reading',
        'Refresh to get the first simulated reading.',
        Icons.hourglass_empty,
      );
    }
    final soil = plant.latestReading!.soilMoisture;
    if (soil != null &&
        soil < plant.profile.rangeFor(SensorMetric.soilMoisture).minimum) {
      return const PlantCondition(
        'Thirsty',
        'Soil is below your selected range.',
        Icons.water_drop_outlined,
        attention: true,
      );
    }
    if (plant.demoScenario == DemoScenario.lowLight) {
      return const PlantCondition(
        'Low-light demo',
        'A dim-light scene for the avatar. One reading or nighttime darkness does not prove insufficient light.',
        Icons.bedtime_outlined,
        attention: true,
      );
    }
    if (plant.demoScenario == DemoScenario.thirsty) {
      return const PlantCondition(
        'Thirsty demo',
        'A dry-soil avatar example. Your custom target range includes the minimum index, so this value is still in range.',
        Icons.water_drop_outlined,
        attention: true,
      );
    }
    return const PlantCondition(
      'Comfortable',
      'Available readings are within your selected demo ranges.',
      Icons.check_circle_outline,
    );
  }
}
