import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/theme/app_theme.dart';
import 'package:plant_companion/widgets/plant_card.dart';
import 'package:plant_companion/widgets/plant_portrait.dart';
import 'package:plant_companion/widgets/sensor_rail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf')))
        .load();
    await (FontLoader('Pixelify Sans')..addFont(
          rootBundle.load(
            'assets/fonts/PixelifySans/PixelifySans-Variable.ttf',
          ),
        ))
        .load();
  });
  for (final width in [320.0, 360.0, 430.0, 1024.0]) {
    for (final scale in [1.0, 1.1, 1.3, 2.0]) {
      testWidgets(
        'natural name group at width $width text $scale; other slots fixed',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Size? cardSize;
          double? originalGap;
          Map<String, Rect>? fixedSlots;
          final groupByName = <String, (Rect, Rect)>{};
          for (var state = 0; state < 8; state++) {
            final nick = state < 4
                ? 'Florence'
                : 'Longnickname Longnickname Longnickname';
            final p = Plant(
              id: 'test',
              nickname: nick,
              speciesName: state % 2 == 0
                  ? 'Epipremnum aureum'
                  : 'Scientific name whose full spelling must remain available',
              deviceId: state == 3 ? null : 'device',
              profile: PlantProfile(
                id: 'p',
                plantType: 'Test',
                ranges: PlantAvatarId.pothos.hints,
              ),
              readings: state % 3 == 0
                  ? []
                  : [
                      SensorReading(
                        recordedAt: DateTime.utc(2026),
                        soilMoisture: state * 10,
                        light: state * 13771.1,
                        temperature: state * 5,
                        humidity: state * 12,
                      ),
                    ],
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: buildAppTheme(),
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: PlantCard(
                        plant: p,
                        device: p.deviceId == null
                            ? null
                            : Device(
                                id: 'device',
                                name: 'Device',
                                isConnected: state % 2 == 0,
                              ),
                        now: DateTime.utc(2026),
                        onAction: () {},
                        edit: state == 6,
                        preview: state == 7,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final card = tester.getRect(find.byType(PlantCard));
            cardSize ??= card.size;
            expect(card.size, cardSize);
            if (width == 430 && scale <= 1.1) {
              expect(card.size, const Size(394, 224));
            }
            final title = tester.getRect(
                  find.byKey(const ValueKey('card-title')),
                ),
                species = tester.getRect(
                  find.byKey(const ValueKey('card-species')),
                );
            final gap = species.top - title.bottom;
            final compact = PlantCard.usesCompactLayout(
              width - 36,
              TextScaler.linear(scale),
            );
            expect(gap, inInclusiveRange(1, (compact ? 4 * scale : 3) + 1e-6));
            originalGap ??= gap;
            expect(gap, closeTo(originalGap, 1e-7));
            if (width == 430 && scale == 1) expect(gap, 4);
            expect(species.left, title.left);
            final label = tester.widget<Text>(
              find.byKey(const ValueKey('card-title')),
            );
            final painter = TextPainter(
              text: TextSpan(text: label.data, style: label.style),
              maxLines: 2,
              ellipsis: '…',
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout(maxWidth: title.width);
            expect(title.height, closeTo(painter.height, 1e-6));
            if (width == 430 && scale == 1) {
              expect(painter.computeLineMetrics().length, state < 4 ? 1 : 2);
            }
            painter.dispose();
            final group = (
              title.shift(-card.topLeft),
              species.shift(-card.topLeft),
            );
            groupByName.putIfAbsent(nick, () => group);
            expect(group, groupByName[nick]);
            final slots = {
              'badge': tester
                  .getRect(find.byType(ConnectionBadge))
                  .shift(-card.topLeft),
              'portrait': tester
                  .getRect(find.byType(PlantPortrait))
                  .shift(-card.topLeft),
              for (final m in cardMetrics)
                m.name: tester
                    .getRect(
                      find.byWidgetPredicate(
                        (w) => w is SensorRail && w.metric == m,
                      ),
                    )
                    .shift(-card.topLeft),
            };
            fixedSlots ??= slots;
            expect(slots, fixedSlots);
            if (compact) {
              expect(
                title.right + 8,
                lessThanOrEqualTo(card.left + slots['badge']!.left + 1e-6),
                reason: 'A second nickname line must not enter the badge slot',
              );
              expect(species.right, title.right);
            } else {
              final action = tester.getRect(
                find.byKey(ValueKey('${state == 6 ? 'edit' : 'details'}-test')),
              );
              final portrait = tester.getRect(find.byType(PlantPortrait));
              expect(
                action.left,
                greaterThanOrEqualTo(portrait.right + 8),
                reason: 'The narrow action must not cover the need bubble',
              );
            }
            expect(
              tester
                  .widget<Text>(find.byKey(const ValueKey('card-title')))
                  .maxLines,
              2,
            );
            expect(
              tester
                  .widget<Text>(find.byKey(const ValueKey('card-species')))
                  .overflow,
              TextOverflow.ellipsis,
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
