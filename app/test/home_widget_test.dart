import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plant_companion/main.dart';
import 'package:plant_companion/models/plant.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/theme/app_theme.dart';
import 'package:plant_companion/navigation/plant_navigation.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'package:plant_companion/widgets/plant_card.dart';
import 'package:plant_companion/widgets/plant_portrait.dart';
import 'package:plant_companion/widgets/sensor_rail.dart';
import 'package:plant_companion/utils/compact_sync_time.dart';
import 'fixtures/foundation_fixtures.dart';
import 'fixtures/plant_fixtures.dart';

Future<PlantStore> mount(
  WidgetTester tester, {
  Size size = const Size(430, 925),
  int? count,
  String scenario = 'reference',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final clock = MutableClock(DateTime.utc(2026, 11, 5, 12));
  final repository = memoryRepository(clock);
  await tester.runAsync(() async {
    await repository.initialize();
    if (count != null) {
      await populatePlantFixtures(
        repository,
        clock.now(),
        count: count,
        scenario: scenario,
      );
    }
  });
  clock.value = clock.now().add(const Duration(minutes: 8));
  final store = PlantStore(
    persistence: repository,
    clock: clock,
    repository: FakeSensorRepository(delay: Duration.zero),
  );
  await tester.runAsync(() => store.initialized);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => store,
      child: const PlantCompanionApp(),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Finder asset(String suffix) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName.endsWith(suffix),
);
Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf'));
    final pixel = FontLoader('Pixelify Sans')
      ..addFont(
        rootBundle.load('assets/fonts/PixelifySans/PixelifySans-Variable.ttf'),
      );
    await Future.wait([inter.load(), pixel.load()]);
  });
  testWidgets('reference Florence geometry and data-driven rail fractions', (
    tester,
  ) async {
    final store = await mount(tester);
    expect(store.plants, hasLength(1));
    final card = find.byType(PlantCard);
    expect(tester.getRect(card), const Rect.fromLTWH(18, 135, 394, 224));
    expect(
      tester.getRect(find.byType(PlantPortrait)),
      const Rect.fromLTWH(28, 144, 152, 206),
    );
    expect(asset('faces/sleeping.png'), findsOneWidget);
    expect(asset('needs/thought_bubble_tight.png'), findsOneWidget);
    expect(
      tester.getRect(asset('faces/sleeping.png')),
      const Rect.fromLTWH(75, 312, 58, 24),
    );
    final rails = find.byType(SensorRail);
    const widths = [72.2, 190 * 280 / 1500, 190 * 115 / 160, 79.8];
    for (var i = 0; i < 4; i++) {
      expect(tester.getSize(rails.at(i)), const Size(190, 21));
      final progress = find.descendant(
        of: rails.at(i),
        matching: find.byKey(const ValueKey('rail-progress')),
      );
      expect(tester.getSize(progress).width, closeTo(widths[i], 1e-8));
    }
    expect(
      find.text('8 min ago'),
      findsNothing,
    ); // Two lines belong to one timestamp node.
    expect(find.text('Last synced\n8 min ago'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await populatePlantFixtures(
        store.persistence,
        store.clock.now(),
        count: 3,
      );
      await store.reload();
    });
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(
        tester.getRect(find.byType(PlantCard).at(i)),
        Rect.fromLTWH(18, [135.0, 371.0, 607.0][i], 394, 224),
      );
    }
  });

  testWidgets(
    'compact two-column cards keep portraits clear of identity and sensor icons',
    (tester) async {
      await mount(tester, size: const Size(390, 844));
      final portrait = tester.getRect(find.byType(PlantPortrait));
      expect(
        portrait.right,
        lessThan(tester.getRect(find.text('Florence')).left),
      );
      expect(
        portrait.right,
        lessThan(tester.getRect(asset('sensors/soil_moisture.png')).left),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native safe insets are consumed once without a fake status region',
    (tester) async {
      tester.view.padding = const FakeViewPadding(
        left: 20,
        top: 24,
        right: 10,
        bottom: 34,
      );
      tester.view.viewPadding = const FakeViewPadding(
        left: 20,
        top: 24,
        right: 10,
        bottom: 34,
      );
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await mount(tester);
      expect(
        tester.getTopLeft(find.byKey(const Key('open-menu'))),
        const Offset(38, 26),
      );
      final card = tester.getRect(find.byType(PlantCard));
      expect(card.left, 38);
      expect(card.top, 159);
      expect(card.width, 364);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'intermediate text enlargement grows reserved slots while card stays compact',
    (tester) async {
      await mount(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PlantCard)).height, 224);
      expect(
        tester.getSize(find.byKey(const ValueKey('sync-plant-1'))).height,
        greaterThan(20),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'card body is inert and only the 48px action opens the correct ID',
    (tester) async {
      final store = await mount(tester);
      await tester.tapAt(const Offset(90, 220));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('details-nickname')), findsNothing);
      final action = find.byKey(const ValueKey('details-plant-1'));
      expect(tester.getSize(action), const Size(48, 48));
      await tap(tester, action);
      final context = tester.element(find.byKey(const Key('details-nickname')));
      final intent =
          ModalRoute.of(context)!.settings.arguments! as PlantRouteIntent;
      expect(intent.plantId, store.plants.single.id);
      expect(intent.destination, PlantDestination.details);
      expect(intent.origin, PlantRouteOrigin.home);
    },
  );

  testWidgets(
    'live timestamp tick preserves the actual packet without acquiring or reloading',
    (tester) async {
      final store = await mount(tester);
      final before = store.plants.single.latestReading!;
      (store.clock as MutableClock).value = store.clock.now().add(
        const Duration(minutes: 1),
      );
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(find.text('Last synced\n9 min ago'), findsOneWidget);
      expect(store.plants.single.latestReading!.id, before.id);
      expect(store.plants.single.latestReading!.recordedAt, before.recordedAt);
      expect(
        await tester.runAsync(() => store.persistence.loadHistory('plant-1')),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'unassigned sensor uses midpoints, sleeping/no bubble and no sync while retaining history',
    (tester) async {
      final store = await mount(tester);
      await tester.runAsync(() => store.unlinkDevice('plant-1'));
      await tester.pumpAndSettle();
      expect(asset('faces/sleeping.png'), findsOneWidget);
      expect(asset('needs/thought_bubble_tight.png'), findsNothing);
      expect(find.text('No device'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-plant-1')), findsNothing);
      expect(
        await tester.runAsync(() => store.persistence.loadHistory('plant-1')),
        hasLength(1),
      );
    },
  );

  testWidgets(
    '0, 1, 3, 10 and 20 plants react and scroll without moving the header',
    (tester) async {
      final store = await mount(tester);
      for (final count in [0, 1, 3, 10, 20]) {
        await tester.runAsync(() async {
          await populatePlantFixtures(
            store.persistence,
            store.clock.now(),
            count: count,
          );
          await store.reload();
        });
        await tester.pumpAndSettle();
        expect(store.plants, hasLength(count));
        final before = tester.getRect(find.byKey(const Key('open-menu')));
        if (count == 0) {
          expect(find.byType(PlantCard), findsNothing);
          expect(find.byKey(const Key('add-plant-button')), findsOneWidget);
          await tester.runAsync(() => store.persistence.initialize());
          expect(
            await tester.runAsync(() => store.persistence.loadPlants()),
            isEmpty,
          );
        } else {
          final last = find.byKey(ValueKey('details-${store.plants.last.id}'));
          await tester.scrollUntilVisible(last, 400, maxScrolls: 50);
          expect(last.hitTestable(), findsOneWidget);
        }
        expect(tester.getRect(find.byKey(const Key('open-menu'))), before);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'drawer remains live, disables inactive rows, closes, and selects ID/edit origin',
    (tester) async {
      final store = await mount(tester);
      final semantics = tester.ensureSemantics();
      try {
        await tap(tester, find.byKey(const Key('open-menu')));
        final close = tester.getSemantics(find.bySemanticsLabel('Close menu'));
        expect(close.rect.size, const Size(50, 50));
        expect(close.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        final edit = tester.getSemantics(
          find.bySemanticsLabel('Edit Plants. Rename & customize'),
        );
        expect(edit.rect.size, const Size(288, 93));
        expect(edit.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        final disabled = tester.getSemantics(
          find.bySemanticsLabel('Notifications. Manage alerts'),
        );
        expect(
          disabled.getSemanticsData().flagsCollection.isEnabled,
          Tristate.isFalse,
        );
        expect(
          disabled.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
        );
        await tester.tap(find.text('Notifications'));
        await tester.pumpAndSettle();
        expect(find.text('MENU'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        await tester.runAsync(
          () => store.saveDraft(
            draft('Live change', deviceId: 'device-1'),
            plantId: 'plant-1',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Live change'), findsOneWidget);
        expect(find.text('MENU'), findsOneWidget);
        await tap(tester, find.byKey(const Key('close-menu')));
        expect(find.text('MENU'), findsNothing);
        await tap(tester, find.byKey(const Key('open-menu')));
        await tap(tester, find.byKey(const Key('edit-plants')));
        expect(find.text('CHOOSE A PLANT TO EDIT'), findsOneWidget);
        expect(find.byKey(const Key('add-plant-button')), findsNothing);
        await tester.tapAt(const Offset(90, 220));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('details-nickname')), findsNothing);
        final pencil = find.byKey(const ValueKey('edit-plant-1'));
        expect(tester.getSize(pencil), const Size(48, 48));
        await tap(tester, pencil);
        final intent =
            ModalRoute.of(
                  tester.element(find.byKey(const Key('nickname-field'))),
                )!.settings.arguments!
                as PlantRouteIntent;
        expect(intent.destination, PlantDestination.edit);
        expect(intent.origin, PlantRouteOrigin.selection);
        expect(intent.plantId, 'plant-1');
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('nickname-field')))
              .controller!
              .text,
          'Live change',
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tap(tester, find.byKey(const Key('selection-back')));
        expect(find.byKey(const Key('open-menu')), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'keyboard Tab and Enter/Space activate actions and Escape closes the drawer',
    (tester) async {
      await mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('MENU'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('MENU'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nickname-field')), findsOneWidget);
    },
  );

  for (final size in const [
    Size(320, 640),
    Size(360, 800),
    Size(390, 844),
    Size(430, 925),
    Size(480, 960),
    Size(768, 1024),
    Size(1440, 900),
    Size(800, 360),
  ]) {
    testWidgets(
      'responsive ${size.width}x${size.height}: long text, 1/1.3/2 scaling and short drawer',
      (tester) async {
        final store = await mount(
          tester,
          size: size,
          count: 3,
          scenario: 'long',
        );
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final factor in [1.0, 1.3, 2.0]) {
          tester.platformDispatcher.textScaleFactorTestValue = factor;
          await tester.pumpAndSettle();
          final last = find.byKey(ValueKey('details-${store.plants.last.id}'));
          await tester.scrollUntilVisible(last, 450, maxScrolls: 60);
          await tester.pumpAndSettle();
          expect(
            last.hitTestable(),
            findsOneWidget,
            reason:
                'scale=$factor; action=${tester.getRect(last)}; viewport=$size',
          );
          expect(tester.getSize(last), const Size(48, 48));
          expect(tester.takeException(), isNull);
          await tap(tester, find.byKey(const Key('open-menu')));
          await tester.ensureVisible(find.text('About'));
          await tester.pumpAndSettle();
          expect(find.text('About').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tap(tester, find.byKey(const Key('close-menu')));
        }
      },
    );
  }

  testWidgets(
    'adaptive-light and missing rail geometry preserves cream separators and original marker',
    (tester) async {
      Future<void> rail(double? current) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 190,
                child: SensorRail(
                  plantId: 'fixture',
                  metric: SensorMetric.light,
                  range: const TargetRange(1600, 2400),
                  current: current,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await rail(2000);
      expect(
        tester.getSize(find.byKey(const ValueKey('rail-progress'))).width,
        closeTo(190 * 2000 / 6000, 1e-8),
      );
      expect(asset('sensors/current_marker.png'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == AppColors.separator,
        ),
        findsNWidgets(2),
      );
      await rail(null);
      expect(find.byKey(const ValueKey('rail-progress')), findsNothing);
      expect(find.byKey(const ValueKey('rail-marker')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == AppColors.separator,
        ),
        findsNWidgets(2),
      );
    },
  );

  test(
    'every above-range mood uses sad plus the correct original sensor asset, before rounding',
    () {
      final ranges = PlantAvatarId.pothos.hints;
      for (final metric in cardMetrics) {
        final values = {for (final m in cardMetrics) m: ranges[m]!.midpoint};
        values[metric] = ranges[metric]!.maximum + .00001;
        final plant = Plant(
          id: 'test',
          nickname: 'Selected plant',
          deviceId: 'device',
          profile: PlantProfile(
            id: 'test',
            plantType: 'Independent species',
            ranges: ranges,
          ),
          readings: [
            SensorReading(
              recordedAt: DateTime.utc(2026),
              soilMoisture: values[SensorMetric.soilMoisture],
              light: values[SensorMetric.light],
              temperature: values[SensorMetric.temperature],
              humidity: values[SensorMetric.humidity],
            ),
          ],
        );
        final appearance = PlantAppearance(plant);
        expect(appearance.face, 'faces/sad.png');
        expect(
          appearance.need,
          {
            SensorMetric.soilMoisture: 'sensors/soil_moisture.png',
            SensorMetric.light: 'sensors/light.png',
            SensorMetric.temperature: 'sensors/temperature.png',
            SensorMetric.humidity: 'sensors/humidity.png',
          }[metric],
        );
        expect(appearance.description, contains('above'));
      }
    },
  );

  test(
    'relative/absolute time uses persisted time with an exact 24-hour boundary',
    () {
      final at = DateTime.utc(2026, 11, 5, 12);
      expect(compactSyncTime(at, at), 'Just now');
      expect(
        compactSyncTime(at, at.add(const Duration(minutes: 1))),
        '1 min ago',
      );
      expect(
        compactSyncTime(at, at.add(const Duration(hours: 23, minutes: 59))),
        '23 hours ago',
      );
      expect(
        compactSyncTime(at, at.add(const Duration(hours: 24))),
        isNot(contains('ago')),
      );
    },
  );
}
