import 'package:plant_companion/theme/app_theme.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/config/temperature_display_config.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/services/plant_simulation.dart';
import 'package:plant_companion/services/sensor_gateway.dart';
import 'package:plant_companion/services/simulated_environment.dart';
import 'package:plant_companion/utils/sensor_scale.dart';
import 'package:plant_companion/utils/sensor_units.dart';
import 'package:plant_companion/widgets/reading_card.dart';
import 'package:plant_companion/widgets/sensor_rail.dart';

final scaleAt = DateTime.utc(2026, 11, 7, 12);
PlantSimulationContext scaleContext(String id, TargetRange range) =>
    PlantSimulationContext(
      plantId: id,
      lightRange: range,
      idealRanges: PlantAvatarId.pothos.hints,
    );
SensorReading scaleSample(
  String deviceId,
  int generation,
  PlantSimulationContext context, {
  SensorReading? previous,
  SimulationMode mode = SimulationMode.manualConditionDriven,
}) => SimulatedEnvironment.sample(
  Device(
    id: deviceId,
    name: 'ignored',
    isConnected: true,
    generationSequence: generation,
  ),
  scaleAt,
  plantContext: context,
  previousReading: previous,
  simulationMode: mode,
);
void main() {
  final ideal = TargetRange(fahrenheitToCelsius(65), fahrenheitToCelsius(85));
  test(
    'temperature endpoints/ideal positions never depend on reading or care endpoints',
    () {
      for (final t in [-58.0, -40.0, -20.0, 25.0, 70.0, 115.0, 120.0, 212.0]) {
        final scale = SensorScale.forMetric(
          SensorMetric.temperature,
          ideal,
          fahrenheitToCelsius(t),
          plantId: 'plant-1',
        );
        expect((scale.minimum, scale.maximum), (-40.0, 120.0));
        expect(scale.fraction(65), .65625);
        expect(scale.fraction(85), .78125);
        expect(scale.fraction(t), ((t + 40) / 160).clamp(0, 1));
      }
      final wide = SensorScale.forMetric(
        SensorMetric.temperature,
        const TargetRange(-50, 100),
        100,
        plantId: 'any',
      );
      expect((wide.minimum, wide.maximum), (-40.0, 120.0));
      expect(wide.fraction(-58), 0);
      expect(wide.fraction(212), 1);
    },
  );
  test('temperature endpoint quantization cannot overshoot 120F', () {
    final max = TemperatureDisplayConfig.maximumCelsius;
    expect(
      quantizeSimulatedValue(max, minimum: -40, maximum: max, scale: 10000),
      max,
    );
    expect(
      celsiusToFahrenheit(
        quantizeSimulatedValue(
          max + .0001,
          minimum: -40,
          maximum: max,
          scale: 10000,
        ),
      ),
      lessThanOrEqualTo(120),
    );
    expect(
      quantizeSimulatedValue(
        -40.0001,
        minimum: -40,
        maximum: max,
        scale: 10000,
      ),
      -40,
    );
    expect(PlantFormDraft.sensorBounds(SensorMetric.temperature), (
      -40.0,
      TemperatureDisplayConfig.maximumCelsius,
    ));
  });
  for (final row in [
    (const TargetRange(400, 850), 'plant-1', 1500.0),
    (const TargetRange(20000, 60000), 'bright', 40000 / .30),
    (const TargetRange(0, 200000), 'extreme', 200000.0),
  ]) {
    test(
      '1000 manual samples respect fixed temperature and exact light envelope ${row.$2}',
      () {
        final context = scaleContext(row.$2, row.$1),
            temps = <double>[],
            lights = <double>[];
        expect(context.lightMaximum, row.$3);
        for (var n = 0; n < 1000; n++) {
          final reading = scaleSample('device-${row.$2}', n, context);
          final f = celsiusToFahrenheit(reading.temperature!);
          expect(f, inInclusiveRange(-40, 120));
          expect(reading.light, inInclusiveRange(0, row.$3));
          temps.add((f + 40) / 160);
          lights.add(reading.light! / row.$3);
        }
        for (final values in [temps, lights]) {
          expect(values.reduce((a, b) => a < b ? a : b), lessThan(.01));
          expect(values.reduce((a, b) => a > b ? a : b), greaterThan(.99));
          final bins = List.filled(10, 0);
          for (final v in values) {
            bins[(v * 10).floor().clamp(0, 9)]++;
          }
          // Global deciles are deliberately weighted toward ideal intervals.
          expect(values.toSet().length, greaterThan(500));
        }
      },
    );
  }
  test(
    'light reuses adaptive policy, including tiny and above-domain maxima',
    () {
      final extreme = scaleContext('extreme', const TargetRange(0, 200000));
      expect(
        SensorScale.forMetric(
          SensorMetric.light,
          extreme.lightRange,
          null,
          plantId: extreme.plantId,
        ).maximum,
        200000 / .30,
      );
      expect(extreme.lightMaximum, 200000);
      final tiny = scaleContext('tiny', const TargetRange(.000001, .000002));
      final seen = <double>{};
      for (var n = 0; n < 100; n++) {
        final value = scaleSample('tiny', n, tiny).light!;
        expect(value, inInclusiveRange(0, tiny.lightMaximum));
        seen.add(value);
      }
      expect(seen.length, greaterThan(90));
      final subnormal = scaleContext('smallest', const TargetRange(0, 1e-320));
      expect(scaleSample('smallest', 0, subnormal).light!.isFinite, isTrue);
    },
  );
  test('condition v4 remains reproducible and ignores previous values', () {
    final context = scaleContext('plant-1', const TargetRange(400, 850));
    final old = SensorReading(
      recordedAt: scaleAt,
      sourceDeviceId: 'device-1',
      light: 200000,
      temperature: 100,
      soilMoisture: 100,
      humidity: 0,
    );
    final a = scaleSample('device-1', 0, context),
        b = scaleSample('device-1', 0, context, previous: old);
    expect(a.soilMoisture, 68.21);
    expect(a.humidity, 40.39);
    expect(a.temperature, 27.2698);
    expect(a.light, 635.11);
    for (final m in SensorMetric.values) {
      expect(a.valueFor(m), b.valueFor(m));
    }
    final brighter = scaleSample(
      'device-1',
      0,
      scaleContext('bright', const TargetRange(20000, 60000)),
    );
    expect(brighter.soilMoisture, a.soilMoisture);
    expect(brighter.humidity, a.humidity);
    expect(brighter.temperature, a.temperature);
    expect(brighter.light, greaterThan(a.light! * 50));
  });
  for (final variant in SensorRailVariant.values) {
    for (final metric in SensorMetric.values) {
      testWidgets(
        '$variant $metric ideal stays fixed with original progress-over-green layering',
        (tester) async {
          final range = metric == SensorMetric.temperature
              ? ideal
              : metric == SensorMetric.light
              ? const TargetRange(400, 850)
              : const TargetRange(30, 60);
          final values = metric == SensorMetric.temperature
              ? [-20.0, 70.0, 115.0].map(fahrenheitToCelsius).toList()
              : metric == SensorMetric.light
              ? [0.0, 600.0, 2000.0]
              : [10.0, 45.0, 90.0];
          Rect? original;
          for (final value in values) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: RepaintBoundary(
                      key: const Key('rail-capture'),
                      child: SizedBox(
                        width: 304,
                        height: 40,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: SensorRail(
                            metric: metric,
                            range: range,
                            current: value,
                            plantId: 'plant-1',
                            variant: variant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final band = tester.getRect(
              find.byKey(const ValueKey('rail-ideal')),
            );
            if (original != null) expect(band, original);
            original = band;
            final marker = tester.getRect(
              find.byKey(const ValueKey('rail-marker')),
            );
            var point = Offset(band.left + band.width * .25, band.center.dy);
            if (marker.inflate(1).contains(point)) {
              point = Offset(band.left + band.width * .75, band.center.dy);
            }
            final capture = tester.getRect(
                  find.byKey(const Key('rail-capture')),
                ),
                local = point - capture.topLeft;
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('rail-capture')),
            );
            final bytes = await tester.runAsync(() async {
              final image = await boundary.toImage();
              final b = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              image.dispose();
              return b;
            });
            final index = (local.dy.floor() * 304 + local.dx.floor()) * 4;
            final idealColor = variant == SensorRailVariant.details
                ? const ui.Color(0xFFA0C6A9)
                : const ui.Color(0xFFA3C6A3);
            final fill = tester.getRect(
              find.byKey(const ValueKey('rail-progress')),
            );
            final color = fill.contains(point)
                ? (variant == SensorRailVariant.details
                      ? AppColors.detailSensors
                      : AppColors.homeSensors)[cardMetrics.indexOf(metric)]
                : idealColor;
            final argb = color.toARGB32();
            final expected = [
              (argb >> 16) & 255,
              (argb >> 8) & 255,
              argb & 255,
              (argb >> 24) & 255,
            ];
            expect([
              for (var i = 0; i < 4; i++) bytes!.getUint8(index + i),
            ], expected);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
  for (final row in [
    (65.0, 150.0, 'partly off chart'),
    (130.0, 180.0, 'above chart'),
    (-58.0, -45.0, 'below chart'),
  ]) {
    testWidgets('saved ${row.$1}..${row.$2} ideal remains readable ${row.$3}', (
      tester,
    ) async {
      final range = TargetRange(
        fahrenheitToCelsius(row.$1),
        fahrenheitToCelsius(row.$2),
      );
      final form = PlantFormDraft(
        nickname: 'Test',
        speciesName: 'Test',
        avatar: PlantAvatarId.pothos,
        ranges: {
          ...PlantAvatarId.pothos.hints,
          SensorMetric.temperature: range,
        },
      );
      expect(form.validate, throwsA(isA<PlantValidationError>()));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 394,
                child: ReadingCard(
                  plantId: 'test',
                  metric: SensorMetric.temperature,
                  range: range,
                  value: fahrenheitToCelsius(115),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining(row.$3), findsOneWidget);
      expect(
        metricRange(SensorMetric.temperature, range),
        contains('${row.$1.toInt()}'),
      );
      expect(
        metricRange(SensorMetric.temperature, range),
        contains('${row.$2.toInt()}'),
      );
      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((w) => w.properties.label ?? '');
      expect(labels.any((s) => s.contains(row.$3)), isTrue);
      final idealWidth = tester
          .widget<Positioned>(find.byKey(const ValueKey('rail-ideal')))
          .width!;
      expect(idealWidth, greaterThanOrEqualTo(0));
      if (row.$3 != 'partly off chart') expect(idealWidth, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
