import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plant_companion/main.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'package:plant_companion/widgets/companion_header.dart';
import 'package:plant_companion/widgets/plant_card.dart';
import 'fixtures/foundation_fixtures.dart';
import 'fixtures/form_actions.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_input.dart';
import 'package:plant_companion/models/device.dart';

class AppFlowGateway extends FakeSensorRepository {
  AppFlowGateway() : super(delay: const Duration(milliseconds: 50));
  bool failNext = false;
  @override
  Future<Device> connect(Device device, {bool simulateFailure = false}) {
    final fail = failNext;
    failNext = false;
    return super.connect(device, simulateFailure: fail || simulateFailure);
  }
}

Future<PlantStore> mountApp(
  WidgetTester tester, {
  bool seedDemo = true,
  FakeSensorRepository? gateway,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final persistence = memoryRepository(MutableClock(DateTime.now().toUtc()));
  await tester.runAsync(() async {
    await persistence.initialize();
    if (!seedDemo) await persistence.deletePlant('plant-1');
  });
  final store = PlantStore(
    persistence: persistence,
    repository:
        gateway ??
        FakeSensorRepository(
          delay: Duration.zero,
          inventory: persistence.loadDevices,
        ),
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

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 160));
  });
  await tester.pumpAndSettle();
}

Future<void> openAddPlant(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('add-plant-button')));
}

// Compatibility test helper: manually enters inputs; no production preset UI.
Future<void> chooseProfile(WidgetTester tester, String label) async {
  final avatar = label == 'Snake Plant'
      ? PlantAvatarId.snakePlant
      : label == 'Peace Lily'
      ? PlantAvatarId.peaceLily
      : PlantAvatarId.pothos;
  await tapVisible(tester, find.byKey(Key('avatar-${avatar.name}')));
  await enterFormText(
    tester,
    'species-field',
    label == 'Custom' ? 'Custom species' : scientificHint(avatar),
  );
  await fillCareRanges(tester, avatar: avatar);
}

void main() {
  testWidgets(
    'required fields show understandable errors and do not add a plant',
    (tester) async {
      final store = await mountApp(tester);
      await openAddPlant(tester);
      await tapVisible(tester, find.byKey(const Key('save-plant-button')));
      expect(find.text('This field is required.'), findsNWidgets(10));
      expect(find.text('Please fill in all required fields.'), findsOneWidget);
      expect(store.plants, hasLength(1));
    },
  );

  testWidgets('adding a plant without a device updates My Plants', (
    tester,
  ) async {
    final store = await mountApp(tester);
    await openAddPlant(tester);
    await tester.enterText(find.byKey(const Key('nickname-field')), 'Fernanda');
    await chooseProfile(tester, 'Pothos');
    await tapVisible(tester, find.byKey(const Key('save-plant-button')));
    expect(find.byKey(const Key('open-menu')), findsOneWidget);
    expect(find.text('Fernanda'), findsOneWidget);
    expect(store.plants, hasLength(2));
    expect(store.plants.last.deviceId, isNull);
    expect(store.plants.last.latestReading, isNull);
  });

  testWidgets(
    'each card navigates to the correct plant, including the newly added one',
    (tester) async {
      final store = await mountApp(tester);
      store.addPlant(nickname: 'Sunny', profile: PlantProfile.samples[2]);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('details-plant-2')));
      expect(find.byKey(const Key('details-nickname')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('details-nickname'))).data,
        'Sunny',
      );
      expect(find.text('Unavailable'), findsNothing);
      expect(find.text('1250 lux'), findsOneWidget);
      expect(store.plants.last.latestReading, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('details-plant-1')));
      expect(
        tester.widget<Text>(find.byKey(const Key('details-nickname'))).data,
        'Florence',
      );
    },
  );

  testWidgets(
    'header refresh updates persisted history and the shared homepage without demo controls',
    (tester) async {
      final store = await mountApp(tester);
      await tapVisible(tester, find.byKey(const Key('details-plant-1')));
      final originalTimestamp = store.plants.first.latestReading!.recordedAt;
      await tester.ensureVisible(find.byKey(const Key('refresh-button')));
      await tester.tap(find.byKey(const Key('refresh-button')));
      await tester.pump();
      expect(
        tester
            .widget<SpriteAction>(find.byKey(const Key('refresh-button')))
            .onPressed,
        isNull,
      );
      await tester.pumpAndSettle();
      expect(store.plants.first.readings, hasLength(1));
      final history = await tester.runAsync(
        () => store.persistence.loadHistory('plant-1'),
      );
      expect(history, hasLength(2));
      expect(
        store.plants.first.latestReading!.recordedAt.isAfter(originalTimestamp),
        isTrue,
      );
      expect(find.byKey(const Key('demo-menu-button')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('635.1 lux'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName.endsWith('faces/sad.png'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('assigned device is explained and a plant can still be saved', (
    tester,
  ) async {
    final store = await mountApp(tester);
    await openAddPlant(tester);
    await tester.enterText(find.byKey(const Key('nickname-field')), 'Sprout');
    await chooseProfile(tester, 'Peace Lily');
    await tapVisible(tester, find.byKey(const Key('scan-devices-button')));
    expect(find.text('Assigned to Florence'), findsOneWidget);
    expect(find.byKey(const Key('connect-device-1')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('save-plant-button')));
    expect(store.plants.last.deviceId, isNull);
  });

  testWidgets(
    'search, failed connection, retry and save with a unique device work',
    (tester) async {
      final gateway = AppFlowGateway(),
          store = await mountApp(tester, gateway: gateway);
      await tester.runAsync(() => store.unlinkDevice('plant-1'));
      await openAddPlant(tester);
      await tester.enterText(
        find.byKey(const Key('nickname-field')),
        'Connected sprout',
      );
      await chooseProfile(tester, 'Pothos');
      await tester.ensureVisible(find.byKey(const Key('scan-devices-button')));
      await tester.tap(find.byKey(const Key('scan-devices-button')));
      await tester.pump();
      expect(find.text('Searching…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      gateway.failNext = true;
      await tester.ensureVisible(find.byKey(const Key('connect-device-1')));
      await tester.tap(find.byKey(const Key('connect-device-1')));
      await tester.pump();
      expect(find.text('Connecting…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not connect. Save disconnected or try again.'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('connect-device-1')));
      expect(find.text('Selected for save'), findsWidgets);
      await tapVisible(tester, find.byKey(const Key('save-plant-button')));
      expect(store.plants.last.deviceId, FakeSensorRepository.demoDevice.id);
      expect(
        store.ownerOfDevice(FakeSensorRepository.demoDevice.id)!.nickname,
        'Connected sprout',
      );
    },
  );

  testWidgets('empty state has a working Add Plant action', (tester) async {
    final store = await mountApp(tester, seedDemo: false);
    expect(find.byType(PlantCard), findsNothing);
    expect(find.byKey(const Key('add-plant-button')), findsOneWidget);
    await openAddPlant(tester);
    await tester.enterText(
      find.byKey(const Key('nickname-field')),
      'First leaf',
    );
    await chooseProfile(tester, 'Peace Lily');
    await tapVisible(tester, find.byKey(const Key('save-plant-button')));
    expect(store.plants, hasLength(1));
    expect(find.text('First leaf'), findsOneWidget);
  });

  testWidgets('custom profile validates and saves configured target ranges', (
    tester,
  ) async {
    final store = await mountApp(tester);
    await openAddPlant(tester);
    await tester.enterText(find.byKey(const Key('nickname-field')), 'Mystery');
    await chooseProfile(tester, 'Custom');
    await tester.enterText(
      find.byKey(const Key('species-field')),
      'Mystery plant',
    );
    await tester.enterText(
      find.byKey(const Key('range-soilMoisture-0')),
      '101',
    );
    await tapVisible(tester, find.byKey(const Key('save-plant-button')));
    expect(find.text('Use 0–100%.'), findsOneWidget);
    expect(store.plants, hasLength(1));
    await tester.enterText(find.byKey(const Key('range-soilMoisture-0')), '25');
    await tapVisible(tester, find.byKey(const Key('save-plant-button')));
    expect(store.plants.last.profile.plantType, 'Mystery plant');
  });

  testWidgets('small screen and doubled text do not overflow in main screens', (
    tester,
  ) async {
    await mountApp(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.byKey(const Key('details-plant-1')));
    await tapVisible(tester, find.byKey(const Key('refresh-button')));
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await openAddPlant(tester);
    await chooseProfile(tester, 'Custom');
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-plant-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
