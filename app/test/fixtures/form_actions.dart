import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_input.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/utils/sensor_units.dart';

Future<void> enterFormText(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.enterText(finder, text);
  await tester.pump();
}

Future<void> fillCareRanges(
  WidgetTester tester, {
  PlantAvatarId avatar = PlantAvatarId.pothos,
  Map<SensorMetric, TargetRange>? ranges,
}) async {
  for (final m in formMetrics) {
    final r = (ranges ?? avatar.hints)[m]!;
    for (var b = 0; b < 2; b++) {
      var value = b == 0 ? r.minimum : r.maximum;
      if (m == SensorMetric.temperature) value = celsiusToFahrenheit(value);
      await enterFormText(
        tester,
        rangeFieldKey(m, b),
        m == SensorMetric.temperature
            ? temperatureInputNumber(value)
            : inputNumber(value),
      );
    }
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
}

Future<void> fillPlantForm(
  WidgetTester tester, {
  String nickname = 'New Plant',
  String species = 'Custom species',
  String fullName = '',
  PlantAvatarId avatar = PlantAvatarId.pothos,
  Map<SensorMetric, TargetRange>? ranges,
}) async {
  await enterFormText(tester, 'nickname-field', nickname);
  await enterFormText(tester, 'full-name-field', fullName);
  await enterFormText(tester, 'species-field', species);
  await fillCareRanges(tester, avatar: avatar, ranges: ranges);
}
