import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plant_companion/main.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/state/plant_store.dart';

Future<PlantStore> mountApp(WidgetTester tester, {bool seedDemo = true}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = PlantStore(
    repository: FakeSensorRepository(delay: const Duration(milliseconds: 50)),
    seedDemo: seedDemo,
  );
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
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openAddPlant(WidgetTester tester) async {
  await tapVisible(tester, find.text('Add Plant'));
}

Future<void> chooseProfile(WidgetTester tester, String label) async {
  await tapVisible(tester, find.byKey(const Key('plant-type-field')));
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'required fields show understandable errors and do not add a plant',
    (tester) async {
      final store = await mountApp(tester);
      await openAddPlant(tester);
      await tapVisible(tester, find.byKey(const Key('save-plant-button')));
      expect(find.text('Give your plant a nickname.'), findsOneWidget);
      expect(find.text('Choose a plant type.'), findsOneWidget);
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
    expect(find.text('My Plants'), findsOneWidget);
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
      await tapVisible(tester, find.byKey(const Key('plant-card-plant-2')));
      expect(find.byKey(const Key('details-nickname')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('details-nickname'))).data,
        'Sunny',
      );
      expect(find.text('Unavailable'), findsNWidgets(8));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('plant-card-plant-1')));
      expect(
        tester.widget<Text>(find.byKey(const Key('details-nickname'))).data,
        'Moss',
      );
    },
  );

  testWidgets(
    'refresh updates history and demo condition updates the shared list',
    (tester) async {
      final store = await mountApp(tester);
      await tapVisible(tester, find.byKey(const Key('plant-card-plant-1')));
      final originalTimestamp = store.plants.first.latestReading!.recordedAt;
      await tester.ensureVisible(find.byKey(const Key('refresh-button')));
      await tester.tap(find.byKey(const Key('refresh-button')));
      await tester.pump();
      expect(find.text('Refreshing…'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(store.plants.first.readings, hasLength(4));
      expect(
        store.plants.first.latestReading!.recordedAt.isAfter(originalTimestamp),
        isTrue,
      );
      await tapVisible(tester, find.byKey(const Key('demo-menu-button')));
      await tapVisible(tester, find.byKey(const Key('demo-thirsty')));
      expect(find.text('Soil is below your selected range.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Thirsty'), findsOneWidget);
    },
  );

  testWidgets('assigned device is explained and a plant can still be saved', (
    tester,
  ) async {
    final store = await mountApp(tester);
    await openAddPlant(tester);
    await tester.enterText(find.byKey(const Key('nickname-field')), 'Sprout');
    await chooseProfile(tester, 'Monstera');
    await tapVisible(tester, find.byKey(const Key('search-device')));
    expect(find.text('Already assigned'), findsOneWidget);
    expect(find.byKey(const Key('connect-device')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('save-plant-button')));
    expect(store.plants.last.deviceId, isNull);
  });

  testWidgets(
    'search, failed connection, retry and save with a unique device work',
    (tester) async {
      final store = await mountApp(tester);
      store.unlinkDevice('plant-1');
      await tester.pumpAndSettle();
      await openAddPlant(tester);
      await tester.enterText(
        find.byKey(const Key('nickname-field')),
        'Connected sprout',
      );
      await chooseProfile(tester, 'Pothos');
      await tester.ensureVisible(find.byKey(const Key('search-device')));
      await tester.tap(find.byKey(const Key('search-device')));
      await tester.pump();
      expect(find.text('Searching for a simulated ESP32…'), findsOneWidget);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('fail-next-connection')));
      await tester.ensureVisible(find.byKey(const Key('connect-device')));
      await tester.tap(find.byKey(const Key('connect-device')));
      await tester.pump();
      expect(find.text('Connecting to simulated ESP32…'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Connection failed'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('retry-connection')));
      expect(find.text('Connected · simulated'), findsOneWidget);
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
    expect(find.text('Your garden starts here'), findsOneWidget);
    await openAddPlant(tester);
    await tester.enterText(
      find.byKey(const Key('nickname-field')),
      'First leaf',
    );
    await chooseProfile(tester, 'Monstera');
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
      find.byKey(const Key('custom-type-field')),
      'Mystery plant',
    );
    await tester.enterText(
      find.byKey(const Key('range-soilMoisture-0')),
      '101',
    );
    await tapVisible(tester, find.byKey(const Key('save-plant-button')));
    expect(find.text('Use 0 to 100.'), findsOneWidget);
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
    await tapVisible(tester, find.byKey(const Key('plant-card-plant-1')));
    await tapVisible(tester, find.byKey(const Key('refresh-button')));
    expect(tester.takeException(), isNull);
    await tester.pageBack();
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
