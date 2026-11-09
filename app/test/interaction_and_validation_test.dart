import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/config/plant_name_config.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/services/plant_repository.dart';
import 'package:plant_companion/widgets/companion_header.dart';
import 'package:plant_companion/widgets/focus_visibility.dart';
import 'package:plant_companion/widgets/plant_card.dart';
import 'package:plant_companion/widgets/plant_portrait.dart';
import 'package:plant_companion/main.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'package:provider/provider.dart';
import 'fixtures/foundation_fixtures.dart';
import 'package:plant_companion/models/plant_commit.dart';
import 'home_widget_test.dart' as home;
import 'app_flow_test.dart' as legacy;

double opacity(WidgetTester tester) => FocusVisibility.opacityOf(
  tester.element(find.byType(CompanionSurface).first),
);

class RejectingStore extends PlantStore {
  RejectingStore({required super.persistence});
  Object? rejection;
  @override
  Future<PlantCommitResult> saveForm(
    PlantFormDraft draft, {
    String? plantId,
    required String operationId,
  }) async {
    if (rejection case final error?) {
      return PlantCommitResult(
        error is DeviceAssignmentConflict
            ? PlantCommitStatus.conflict
            : PlantCommitStatus.notCommitted,
        error: error,
      );
    }
    return super.saveForm(draft, plantId: plantId, operationId: operationId);
  }
}

void main() {
  setUpAll(() async {
    await Future.wait([
      (FontLoader('Inter')
            ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf')))
          .load(),
      (FontLoader('Pixelify Sans')..addFont(
            rootBundle.load(
              'assets/fonts/PixelifySans/PixelifySans-Variable.ttf',
            ),
          ))
          .load(),
    ]);
  });

  test(
    'central naming boundaries preserve whole graphemes and stored values',
    () {
      const cluster = '👩🏽‍🌾';
      const accent = 'e\u0301';
      expect(PlantNameConfig.length('$cluster$accent'), 2);
      expect(PlantNameConfig.warnsForNickname(cluster * 10), isFalse);
      expect(PlantNameConfig.warnsForNickname(cluster * 11), isTrue);
      expect(
        PlantNameConfig.accepts(
          cluster * 25,
          PlantNameConfig.fullNameInputMaxLength,
        ),
        isTrue,
      );
      expect(
        PlantNameConfig.accepts(
          cluster * 26,
          PlantNameConfig.fullNameInputMaxLength,
        ),
        isFalse,
      );
      expect(
        PlantNameConfig.truncate(
          accent * 15,
          PlantNameConfig.fullNameDisplayTruncationLength,
        ),
        accent * 15,
      );
      expect(
        PlantNameConfig.truncate(
          cluster * 16,
          PlantNameConfig.fullNameDisplayTruncationLength,
        ),
        '${cluster * 15}…',
      );
      expect(
        PlantNameConfig.accepts(
          cluster * 100,
          PlantNameConfig.nicknameInputMaxLength,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'focus starts hidden, traversal resets timer, fades and preserves activation',
    (tester) async {
      await home.mount(tester);
      expect(opacity(tester), 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(opacity(tester), 1);
      final menu = tester.widget<SpriteAction>(
        find.byKey(const Key('open-menu')),
      );
      expect(menu.focusNode!.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(menu.focusNode!.hasFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 600));
      expect(opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 90));
      expect(opacity(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(tester), 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nickname-field')), findsOneWidget);
    },
  );

  testWidgets(
    'arrows reveal focus; pointer and drawer cycles do not leave rings; disposal cleans timers',
    (tester) async {
      await home.mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(opacity(tester), 1);
      await home.tap(tester, find.byKey(const Key('open-menu')));
      expect(opacity(tester), 0);
      await tester.tapAt(const Offset(420, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('close-menu')), findsOneWidget);
      expect(find.byKey(const Key('nickname-field')), findsNothing);
      await home.tap(tester, find.byKey(const Key('close-menu')));
      expect(opacity(tester), 0);
      await home.tap(tester, find.byKey(const Key('open-menu')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('close-menu')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('assistive mode retains focus and reduced motion skips fading', (
    tester,
  ) async {
    await home.mount(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(tester), 1);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(FocusVisibility.delay);
    expect(opacity(tester), 0);
  });

  for (final size in const [
    Size(360, 800),
    Size(390, 844),
    Size(430, 925),
    Size(768, 1024),
    Size(1440, 900),
    Size(1024, 768),
    Size(1600, 2560),
    Size(2560, 1600),
  ]) {
    testWidgets('X shares Add slot at $size; scrim blocks; Back closes', (
      tester,
    ) async {
      await home.mount(tester, size: size);
      final add = tester.getRect(find.byKey(const Key('add-plant-button')));
      await home.tap(tester, find.byKey(const Key('open-menu')));
      expect(tester.getRect(find.byKey(const Key('close-menu'))), add);
      await tester.tapAt(Offset(add.center.dx, 250));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('close-menu')), findsOneWidget);
      expect(find.byKey(const Key('nickname-field')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('close-menu')), findsNothing);
    });
  }

  testWidgets('native safe inset shifts Add and X together', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 36, left: 12, right: 12);
    tester.view.viewPadding = const FakeViewPadding(
      top: 36,
      left: 12,
      right: 12,
    );
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await home.mount(tester);
    final rect = tester.getRect(find.byKey(const Key('add-plant-button')));
    await home.tap(tester, find.byKey(const Key('open-menu')));
    expect(tester.getRect(find.byKey(const Key('close-menu'))), rect);
  });

  for (final count in [10, 11, 15, 25, 40]) {
    testWidgets(
      '$count-character nicknames use bounded two-line compact cards at slight scaling',
      (tester) async {
        final store = await home.mount(tester, size: const Size(390, 844));
        final name = 'N' * count;
        await tester.runAsync(
          () => store.saveDraft(
            draft(name, deviceId: 'device-1'),
            plantId: 'plant-1',
          ),
        );
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final size in const [
          Size(360, 800),
          Size(390, 844),
          Size(430, 925),
          Size(1440, 900),
        ]) {
          tester.view.physicalSize = size;
          for (final scale in [1.0, 1.1, 1.3, 2.0]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await tester.pumpAndSettle();
            final height = tester.getSize(find.byType(PlantCard)).height;
            expect(height.isFinite, isTrue);
            if (scale <= 1.1 && size.width == 360) {
              expect(height, lessThan(450));
            }
            if (size.width >= 390 && scale <= 1.1) {
              expect(height, lessThan(300));
            }
            expect(tester.takeException(), isNull);
          }
        }
        final text = tester.widget<Text>(find.text(name));
        expect(text.maxLines, PlantNameConfig.nicknameMaxDisplayLines);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(store.plantById('plant-1').nickname, name);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Enter activates a focused action after fading and cleanup removes the keyboard handler',
    (tester) async {
      await home.mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(FocusVisibility.delay);
      await tester.pump(FocusVisibility.fade);
      expect(opacity(tester), 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('close-menu')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'connection states share badge coordinates with or without actual sync',
    (tester) async {
      final store = await home.mount(tester);
      Future<Rect> slot() async {
        await tester.pumpAndSettle();
        final card = tester.getRect(find.byType(PlantCard));
        return tester
            .getRect(find.byKey(const ValueKey('connection-plant-1')))
            .shift(-card.topLeft);
      }

      var connected = await slot();
      final plant = store.plants.single;
      await tester.runAsync(
        () => store.saveDraft(
          PlantFormDraft(
            nickname: plant.nickname,
            speciesName:
                'A long scientific identity that must not move the connection slot',
            avatar: plant.avatar,
            ranges: plant.profile.ranges,
            deviceId: plant.deviceId,
          ),
          plantId: plant.id,
        ),
      );
      expect(await slot(), connected);
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      connected = await slot();
      final time = store.plants.single.latestReading!.recordedAt;
      await tester.runAsync(() async {
        await store.persistence.setConnection('device-1', false);
        await store.reload();
      });
      expect(await slot(), connected);
      expect(store.plants.single.latestReading!.recordedAt, time);
      await tester.runAsync(() => store.unlinkDevice('plant-1'));
      expect(await slot(), connected);
      expect(home.asset('faces/sleeping.png'), findsOneWidget);
      expect(home.asset('needs/thought_bubble_tight.png'), findsNothing);
      expect(find.byKey(const ValueKey('sync-plant-1')), findsNothing);
      expect(tester.getSize(find.byType(PlantPortrait)), const Size(152, 206));
    },
  );

  testWidgets(
    'empty home and selection remain safe and adding without a device succeeds',
    (tester) async {
      final store = await legacy.mountApp(tester, seedDemo: false);
      expect(find.text('No plants yet.'), findsOneWidget);
      expect(find.text('Tap + to add one.'), findsOneWidget);
      await home.tap(tester, find.byKey(const Key('open-menu')));
      await home.tap(tester, find.byKey(const Key('edit-plants')));
      expect(find.byType(PlantCard), findsNothing);
      await home.tap(tester, find.byKey(const Key('selection-back')));
      await tester.runAsync(() => store.reload());
      await tester.pumpAndSettle();
      expect(store.plants, isEmpty);
      await legacy.openAddPlant(tester);
      await tester.enterText(find.byKey(const Key('nickname-field')), 'N' * 45);
      await legacy.chooseProfile(tester, 'Snake Plant');
      await legacy.tapVisible(
        tester,
        find.byKey(const Key('save-plant-button')),
      );
      expect(store.plants.single.nickname, 'N' * 45);
      expect(store.plants.single.speciesName, 'Dracaena trifasciata');
      expect(store.plants.single.avatar, PlantAvatarId.snakePlant);
      expect(store.plants.single.deviceId, isNull);
      expect(find.text('No plants yet.'), findsNothing);
    },
  );

  testWidgets(
    'absurd light range is rejected accurately and custom species/value remain intact',
    (tester) async {
      final store = await legacy.mountApp(tester);
      await legacy.openAddPlant(tester);
      await tester.enterText(find.byKey(const Key('nickname-field')), 'Custom');
      await legacy.chooseProfile(tester, 'Custom');
      await tester.enterText(
        find.byKey(const Key('species-field')),
        'User scientific identity',
      );
      await tester.enterText(
        find.byKey(const Key('range-light-1')),
        '200000000',
      );
      await legacy.tapVisible(
        tester,
        find.byKey(const Key('save-plant-button')),
      );
      expect(find.text('Use 0–200,000 lux.'), findsOneWidget);
      expect(find.textContaining('just assigned'), findsNothing);
      expect(store.plants, hasLength(1));
      expect(find.textContaining('kept in memory'), findsNothing);
      await tester.enterText(find.byKey(const Key('range-light-1')), '12000');
      await legacy.tapVisible(
        tester,
        find.byKey(const Key('save-plant-button')),
      );
      expect(store.plants.last.speciesName, 'User scientific identity');
      expect(
        store.plants.last.profile
            .rangeFor(
              PlantAvatarId.pothos.hints.keys
                  .where((m) => m.name == 'light')
                  .single,
            )
            .maximum,
        12000,
      );
    },
  );

  test(
    'actual SQLite save failure retains its cause and is not a device conflict',
    () async {
      final repository = memoryRepository(MutableClock(DateTime.now().toUtc()));
      await repository.initialize();
      await repository.database.customStatement(
        "CREATE TRIGGER reject_new_plant BEFORE INSERT ON plants BEGIN SELECT RAISE(ABORT, 'storage probe'); END",
      );
      await expectLater(
        repository.save(draft('Storage')),
        throwsA(
          isA<PlantPersistenceFailure>().having(
            (e) => e.cause.toString(),
            'cause',
            contains('storage probe'),
          ),
        ),
      );
      expect(await repository.loadPlants(), hasLength(1));
      await repository.close();
    },
  );

  for (final (error, message) in [
    (DeviceAssignmentConflict(), 'This device is now assigned'),
    (
      PlantPersistenceFailure(Exception('disk unavailable')),
      'Could not save to local storage.',
    ),
    (StateError('unexpected probe'), 'Unexpected error while saving.'),
  ]) {
    testWidgets(
      'shared form save classifies ${error.runtimeType} and preserves entries for retry',
      (tester) async {
        final persistence = memoryRepository(
          MutableClock(DateTime.now().toUtc()),
        );
        final store = RejectingStore(persistence: persistence)
          ..rejection = error;
        await tester.runAsync(() => store.initialized);
        await tester.pumpWidget(
          ChangeNotifierProvider<PlantStore>(
            create: (_) => store,
            child: const PlantCompanionApp(),
          ),
        );
        await tester.pumpAndSettle();
        await legacy.openAddPlant(tester);
        await tester.enterText(
          find.byKey(const Key('nickname-field')),
          'Preserve this',
        );
        await legacy.chooseProfile(tester, 'Pothos');
        await legacy.tapVisible(
          tester,
          find.byKey(const Key('save-plant-button')),
        );
        expect(find.textContaining(message), findsOneWidget);
        if (error is! DeviceAssignmentConflict) {
          expect(find.textContaining('just assigned'), findsNothing);
        }
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('nickname-field')))
              .controller!
              .text,
          'Preserve this',
        );
        expect(store.plants, hasLength(1));
        store.rejection = null;
        await legacy.tapVisible(
          tester,
          find.byKey(const Key('save-plant-button')),
        );
        expect(store.plants, hasLength(2));
      },
    );
  }

  test(
    'assignment failure has a distinct type preserving legacy StateError contract',
    () async {
      final repository = memoryRepository(MutableClock(DateTime.now().toUtc()));
      await repository.initialize();
      await expectLater(
        repository.save(draft('Conflict', deviceId: 'device-1')),
        throwsA(isA<DeviceAssignmentConflict>()),
      );
      await repository.close();
    },
  );
}
