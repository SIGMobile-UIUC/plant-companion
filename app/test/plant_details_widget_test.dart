import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plant_companion/main.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/models/portrait_geometry.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/navigation/plant_navigation.dart';
import 'package:plant_companion/screens/my_plants_screen.dart';
import 'package:plant_companion/screens/plant_details_screen.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'package:plant_companion/theme/app_theme.dart';
import 'package:plant_companion/utils/sensor_scale.dart';
import 'package:plant_companion/widgets/companion_header.dart';
import 'package:plant_companion/widgets/details_hero.dart';
import 'package:plant_companion/widgets/plant_portrait.dart';
import 'package:plant_companion/widgets/reading_card.dart';
import 'package:plant_companion/widgets/sensor_rail.dart';
import 'fixtures/foundation_fixtures.dart';
import 'home_widget_test.dart' as home;
import 'device_refresh_test.dart' show ControlledRefreshGateway;

Future<PlantStore> details(
  WidgetTester tester, {
  Size size = const Size(430, 925),
  double scale = 1,
  int? count,
  String scenario = 'reference',
  int index = 0,
}) async {
  final store = await home.mount(
    tester,
    size: size,
    count: count,
    scenario: scenario,
  );
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpAndSettle();
  final id = store.plants[index].id;
  // Move long lists before searching for lazily mounted actions.
  if (index > 2) {
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('details-$id')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await home.tap(tester, find.byKey(ValueKey('details-$id')));
  return store;
}

Future<void> packet(
  WidgetTester tester,
  PlantStore store, {
  SensorMetric? issue,
  bool above = false,
  bool partial = false,
}) async {
  await tester.runAsync(() async {
    final plant = store.plants.first;
    final values = {
      for (final m in SensorMetric.values)
        m: partial && m != issue ? null : plant.profile.rangeFor(m).midpoint,
    };
    if (issue != null) {
      final r = plant.profile.rangeFor(issue);
      values[issue] = above ? r.maximum + 1 : r.minimum - 1;
    }
    final device = (await store.persistence.loadAssignedDevices())[plant.id]!;
    await store.persistence.commitReading(
      plant.id,
      device,
      SensorReading(
        recordedAt: store.clock.now(),
        soilMoisture: values[SensorMetric.soilMoisture],
        light: values[SensorMetric.light],
        temperature: values[SensorMetric.temperature],
        humidity: values[SensorMetric.humidity],
      ),
    );
    await store.reload();
  });
  await tester.pumpAndSettle();
}

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

  testWidgets(
    'reference Details geometry, shared v4 scale and measured rail colors; no legacy UI',
    (tester) async {
      final store = await details(tester);
      expect(
        tester.getRect(find.byType(CompanionHeader)),
        const Rect.fromLTWH(0, 0, 430, 68),
      );
      expect(
        tester.getRect(find.byKey(const Key('details-back'))),
        const Rect.fromLTWH(18, 2, 50, 50),
      );
      expect(
        tester.getRect(find.byKey(const Key('refresh-button'))),
        const Rect.fromLTWH(363, 2, 50, 50),
      );
      expect(home.asset('branding/companion_wordmark.png'), findsOneWidget);
      expect(home.asset('branding/plant_companion_full.png'), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('details-hero'))),
        const Rect.fromLTWH(18, 86, 394, 421),
      );
      expect(
        tester.getRect(find.byKey(const Key('details-name-card'))),
        const Rect.fromLTWH(59, 413, 312, 51),
      );
      expect(
        tester.getRect(find.byKey(const Key('details-connection-dot'))),
        const Rect.fromLTWH(45, 104, 9, 9),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('details-nickname'))),
        const Offset(77, 421),
      );
      final portraitRect = tester.getRect(find.byType(PlantPortrait));
      expect(portraitRect.left, closeTo(108.6, 1e-7));
      expect(portraitRect.top, 96);
      expect(portraitRect.width, closeTo(212.8, 1e-7));
      expect(portraitRect.height, closeTo(288.4, 1e-7));
      expect(find.text('Synced 8 min ago'), findsOneWidget);
      expect(find.text('Epipremnum aureum'), findsOneWidget);
      expect(find.byType(ReadingCard), findsNWidgets(4));
      for (final (i, metric) in cardMetrics.indexed) {
        final card = find.byKey(ValueKey('details-reading-${metric.name}'));
        expect(
          tester.getRect(card),
          Rect.fromLTWH(18, 523 + i * 110, 394, 102),
        );
        final rail = find.descendant(
          of: card,
          matching: find.byType(SensorRail),
        );
        expect(tester.getRect(rail), Rect.fromLTWH(90, 595 + i * 110, 304, 22));
        final p = store.plants.first;
        final domain = SensorScale.forMetric(
          metric,
          p.profile.rangeFor(metric),
          p.latestReading!.valueFor(metric),
          plantId: p.id,
        );
        final progress = find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('rail-progress')),
        );
        expect(
          tester.getSize(progress).width,
          closeTo(
            304 *
                domain.fraction(
                  displayValue(metric, p.latestReading!.valueFor(metric)!),
                ),
            1e-8,
          ),
        );
        final fill = tester.widget<DecoratedBox>(
          find.descendant(of: progress, matching: find.byType(DecoratedBox)),
        );
        expect(
          (fill.decoration as BoxDecoration).color,
          AppColors.detailSensors[i],
        );
        expect((fill.decoration as BoxDecoration).gradient, isNull);
      }
      expect(
        tester.getRect(find.byKey(const Key('details-device'))),
        const Rect.fromLTWH(23, 971, 384, 111),
      );
      expect(find.text('ESP32-Sim01 · Change Device'), findsOneWidget);
      for (final text in [
        'Demo conditions',
        'Recent readings',
        'Your little helper',
        'Stale',
        'Battery voltage',
        'Refresh readings',
      ]) {
        expect(find.textContaining(text), findsNothing);
      }
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  for (final avatar in PlantAvatarId.values) {
    testWidgets(
      '${avatar.name}: original detail anchors and healthy heart overflow; homepage has no heart',
      (tester) async {
        final store = await home.mount(tester);
        await tester.runAsync(
          () => store.saveDraft(
            PlantFormDraft(
              nickname: 'Healthy',
              speciesName: 'User species',
              avatar: avatar,
              ranges: avatar.hints,
              deviceId: 'device-1',
            ),
            plantId: 'plant-1',
          ),
        );
        await packet(tester, store);
        expect(home.asset('faces/happy.png'), findsOneWidget);
        expect(home.asset('needs/happy_heart.png'), findsNothing);
        await home.tap(tester, find.byKey(const Key('details-plant-1')));
        expect(home.asset(avatar.asset), findsOneWidget);
        expect(home.asset('faces/happy.png'), findsOneWidget);
        expect(home.asset('needs/happy_heart.png'), findsOneWidget);
        final portrait = tester.getRect(find.byType(PlantPortrait));
        final face = tester.getRect(find.byKey(const ValueKey('plant-face')));
        final bubble = tester.getRect(
          find.byKey(const ValueKey('thought-bubble')),
        );
        final hero = tester.getRect(find.byKey(const Key('details-hero')));
        expect(bubble.right, greaterThan(portrait.right));
        expect(bubble.right, lessThan(hero.right));
        expect(bubble.left - portrait.left, closeTo(174.6, 1e-7));
        expect(
          face.center.dx - portrait.left,
          closeTo(PortraitGeometry(avatar, detail: true).potCenter.dx, .7),
        );
        expect(
          face.center.dy - portrait.top,
          closeTo(PortraitGeometry(avatar, detail: true).potCenter.dy, .7),
        );
        expect(
          find.ancestor(
            of: home.asset('needs/thought_bubble_tight.png'),
            matching: find.byType(ClipRRect),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final metric in cardMetrics) {
    for (final above in [false, true]) {
      testWidgets(
        '${metric.name} ${above ? 'above' : 'below'} uses approved original face and need asset',
        (tester) async {
          final store = await details(tester);
          await packet(tester, store, issue: metric, above: above);
          expect(
            home.asset(
              metric == SensorMetric.light && !above
                  ? 'faces/sleeping.png'
                  : 'faces/sad.png',
            ),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('thought-bubble')), findsOneWidget);
          final need = tester.widget<Image>(
            find.byKey(const ValueKey('need-icon')),
          );
          expect(
            (need.image as AssetImage).assetName,
            '$companionAssets${metric == SensorMetric.temperature && !above ? 'needs/cold_thermometer.png' : sensorAsset(metric)}',
          );
          expect(home.asset('needs/happy_heart.png'), findsNothing);
        },
      );
    }
  }

  for (final index in [7, 8, 9]) {
    testWidgets(
      'partial/missing fixture$index never invents measurements or healthy state',
      (tester) async {
        final store = await details(
          tester,
          count: 10,
          scenario: 'conditions',
          index: index,
        );
        final plant = store.plants[index];
        expect(
          find.text('—'),
          findsNWidgets(
            index == 9
                ? 4
                : index == 8
                ? 1
                : 3,
          ),
        );
        expect(
          find.byKey(const ValueKey('rail-progress')),
          findsNWidgets(
            index == 9
                ? 0
                : index == 8
                ? 3
                : 1,
          ),
        );
        expect(
          find.byKey(const ValueKey('rail-marker')),
          findsNWidgets(
            index == 9
                ? 0
                : index == 8
                ? 3
                : 1,
          ),
        );
        expect(find.byKey(const ValueKey('rail-ideal')), findsNWidgets(4));
        expect(
          find.byKey(const ValueKey('plant-face')),
          index == 8 ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('thought-bubble')),
          index == 8 ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('details-sync')),
          index == 9 ? findsNothing : findsOneWidget,
        );
        if (index != 9) expect(plant.latestReading!.soilMoisture, isNull);
        expect(home.asset('needs/happy_heart.png'), findsNothing);
      },
    );
  }

  testWidgets(
    'no assigned device keeps midpoint-only data, no sync/bubble and disabled keyboard/touch refresh',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final store = await details(tester);
      await tester.runAsync(() => store.unlinkDevice('plant-1'));
      await tester.pumpAndSettle();
      final before = await tester.runAsync(
        () => store.persistence.loadHistory('plant-1'),
      );
      expect(find.text('625 lux'), findsOneWidget);
      expect(find.byKey(const Key('details-sync')), findsNothing);
      expect(home.asset('faces/sleeping.png'), findsOneWidget);
      expect(find.byKey(const ValueKey('thought-bubble')), findsNothing);
      final refresh = find.byKey(const Key('refresh-button'));
      expect(tester.widget<SpriteAction>(refresh).onPressed, isNull);
      final data = tester.getSemantics(refresh).getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      await tester.tap(refresh);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(
          () => store.persistence.loadHistory('plant-1'),
        ))!.map((r) => r.id),
        before!.map((r) => r.id),
      );
      expect(store.plants.first.deviceId, isNull);
      expect(find.text('No device assigned · Change Device'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'pencil opens real Details-origin Edit without recursive Details; Cancel/Back reuses Home',
    (tester) async {
      final store = await details(tester);
      expect(
        PlantRouteIntent(
          PlantDestination.edit,
          PlantRouteOrigin.details,
          plantId: store.plants.first.id,
        ).plantId,
        'plant-1',
      );
      final pencil = find.byKey(const ValueKey('details-edit-plant-1'));
      expect(tester.widget<SpriteAction>(pencil).onPressed, isNotNull);
      await tester.tap(pencil);
      await tester.pumpAndSettle();
      expect(
        find.byType(PlantDetailsScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byKey(const Key('nickname-field')), findsOneWidget);
      await home.tap(tester, find.byKey(const Key('form-back')));
      await home.tap(tester, find.byKey(const Key('details-back')));
      expect(find.byType(MyPlantsScreen, skipOffstage: false), findsOneWidget);
      expect(
        find.byType(PlantDetailsScreen, skipOffstage: false),
        findsNothing,
      );
      expect(find.byKey(const Key('open-menu')), findsOneWidget);
    },
  );

  testWidgets(
    'home scroll position and correct immutable selected ID survive Details/Back',
    (tester) async {
      final store = await home.mount(tester, count: 20);
      final list = find.byKey(const PageStorageKey('home-list'));
      final scrolling = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrolling).position;
      position.jumpTo(1500);
      await tester.pumpAndSettle();
      final id = store.plants[7].id;
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('details-$id')),
        100,
        scrollable: scrolling,
      );
      final before = position.pixels;
      await home.tap(tester, find.byKey(ValueKey('details-$id')));
      expect(
        tester.widget<Text>(find.byKey(const Key('details-nickname'))).data,
        store.findPlant(id)!.nickname,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scrolling).position.pixels, before);
      expect(find.byType(MyPlantsScreen, skipOffstage: false), findsOneWidget);
    },
  );

  testWidgets(
    'missing ID does not push; deletion while Details is open unwinds without throwing',
    (tester) async {
      final store = await details(tester);
      await tester.runAsync(() => store.deletePlant('plant-1'));
      await tester.pumpAndSettle();
      expect(find.byType(PlantDetailsScreen), findsNothing);
      expect(find.byType(MyPlantsScreen), findsOneWidget);
      await openPlantRoute(
        tester.element(find.byType(MyPlantsScreen)),
        const PlantRouteIntent(
          PlantDestination.details,
          PlantRouteOrigin.home,
          plantId: 'missing',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlantDetailsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full lux precision reflows without changing data or shared v4 scale; scroll survives reload',
    (tester) async {
      final store = await details(tester);
      final first = store.plants.first;
      await tester.runAsync(() async {
        await store.persistence.commitReading(
          first.id,
          (await store.persistence.loadAssignedDevices())[first.id]!,
          SensorReading(recordedAt: store.clock.now(), light: 100250.25),
        );
        await store.reload();
      });
      await tester.pumpAndSettle();
      expect(find.text('100250.25 lux'), findsOneWidget);
      expect(find.text('100k lux'), findsNothing);
      final light = find.byWidgetPredicate(
        (w) => w is SensorRail && w.metric == SensorMetric.light,
      );
      expect(tester.widget<SensorRail>(light).plantId, first.id);
      final ideal = find.descendant(
        of: light,
        matching: find.byKey(const ValueKey('rail-ideal')),
      );
      final before = tester.getSize(ideal);
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(ValueKey('details-scroll-${first.id}')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      scroll.jumpTo(150);
      await tester.pumpAndSettle();
      await tester.runAsync(store.reload);
      await tester.pumpAndSettle();
      expect(scroll.pixels, 150);
      expect(tester.getSize(ideal), before);
      expect(store.plants.first.latestReading!.light, 100250.25);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'minute ticker updates only sync label; old data never gets a Stale badge or disconnection',
    (tester) async {
      final store = await details(tester);
      final at = store.plants.first.latestReading!.recordedAt;
      (store.clock as MutableClock).value = store.clock.now().add(
        const Duration(minutes: 1),
      );
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('Synced 9 min ago'), findsOneWidget);
      expect(store.plants.first.latestReading!.recordedAt, at);
      (store.clock as MutableClock).value = store.clock.now().add(
        const Duration(days: 2),
      );
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stale'), findsNothing);
      expect(store.deviceFor(store.plants.first)!.isConnected, isTrue);
      expect(store.plants.first.latestReading!.recordedAt, at);
    },
  );

  for (final connectionFailure in [true, false]) {
    testWidgets(
      '${connectionFailure ? 'connection' : 'acquisition'} failure gives truthful inline live feedback without modal/snackbar',
      (tester) async {
        tester.view.physicalSize = const Size(430, 925);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final clock = MutableClock(DateTime.utc(2026, 11, 6));
        final repo = memoryRepository(clock);
        await tester.runAsync(() async {
          await repo.initialize();
          await repo.setConnection('device-1', false);
        });
        final gateway = ControlledRefreshGateway()
          ..failConnection = connectionFailure
          ..failAcquisition = !connectionFailure;
        final store = PlantStore(
          persistence: repo,
          repository: gateway,
          clock: clock,
        );
        await tester.runAsync(() => store.initialized);
        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => store,
            child: const PlantCompanionApp(),
          ),
        );
        await tester.pumpAndSettle();
        await home.tap(tester, find.byKey(const Key('details-plant-1')));
        final old = store.plants.first.latestReading!;
        await home.tap(tester, find.byKey(const Key('refresh-button')));
        final error = tester.widget<Text>(
          find.byKey(const Key('details-refresh-error')),
        );
        expect(
          error.data,
          connectionFailure
              ? 'Could not reconnect. Try again.'
              : 'Could not refresh readings. Try again.',
        );
        expect(error.style!.color, AppColors.terracotta);
        expect(
          store.deviceFor(store.plants.first)!.isConnected,
          !connectionFailure,
        );
        expect(store.plants.first.latestReading!.id, old.id);
        expect(store.plants.first.latestReading!.recordedAt, old.recordedAt);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        gateway.failConnection = false;
        gateway.failAcquisition = false;
        await home.tap(tester, find.byKey(const Key('refresh-button')));
        expect(find.byKey(const Key('details-refresh-error')), findsNothing);
        expect(store.deviceFor(store.plants.first)!.isConnected, isTrue);
      },
    );
  }

  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(390, 844),
    const Size(430, 925),
    const Size(480, 960),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
        '${size.width}×${size.height} text$scale: fixed header, reachable device and no overflow',
        (tester) async {
          final store = await details(tester, size: size, scale: scale);
          await tester.runAsync(
            () => store.saveDraft(
              PlantFormDraft(
                nickname:
                    'A long nickname 👩🏽‍🌾 combining é and extra words',
                speciesName:
                    'An unusually long scientific identity entered by the user',
                avatar: store.plants.first.avatar,
                ranges: store.plants.first.profile.ranges,
                deviceId: 'device-1',
              ),
              plantId: 'plant-1',
            ),
          );
          await tester.pumpAndSettle();
          final header = tester.getRect(find.byType(CompanionHeader));
          expect(header.width, lessThanOrEqualTo(480));
          await tester.ensureVisible(find.byKey(const Key('details-device')));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(CompanionHeader)), header);
          expect(
            tester.getRect(find.byKey(const Key('details-device'))).bottom,
            lessThanOrEqualTo(size.height + 1),
          );
          expect(
            tester.getRect(find.byType(DetailsHero)).width,
            lessThanOrEqualTo(444),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
