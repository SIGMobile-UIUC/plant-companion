import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/plant_form_input.dart';
import 'package:plant_companion/models/sensor_reading.dart';
import 'package:plant_companion/screens/my_plants_screen.dart';
import 'package:plant_companion/screens/plant_form_screen.dart';
import 'package:plant_companion/screens/plant_details_screen.dart';
import 'package:plant_companion/services/plant_preview.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'package:plant_companion/theme/app_theme.dart';
import 'package:plant_companion/widgets/plant_form_sections.dart';
import 'package:plant_companion/widgets/companion_device_section.dart';
import 'package:plant_companion/widgets/focus_visibility.dart';
import 'fixtures/foundation_fixtures.dart';
import 'fixtures/form_actions.dart';
import 'device_refresh_test.dart' show ControlledRefreshGateway;
import 'plant_mutation_store_test.dart' show MutationFaultRepository;

class DRouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
}

class DWidgetFixture {
  DWidgetFixture(this.store, this.repo, this.gateway, this.routes);
  final PlantStore store;
  final MutationFaultRepository repo;
  final ControlledRefreshGateway gateway;
  final DRouteObserver routes;
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    await tester.pump();
  }
}

Future<DWidgetFixture> mountD(
  WidgetTester tester, {
  Size size = const Size(430, 925),
  double scale = 1,
  bool reducedMotion = false,
  bool empty = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final clock = MutableClock(DateTime.utc(2026, 11, 6, 12)),
      repo = MutationFaultRepository(
        MutableClock(DateTime.utc(2026, 11, 6, 12)),
      ),
      gateway = ControlledRefreshGateway();
  await tester.runAsync(() async {
    await repo.initialize();
    if (empty) await repo.deletePlant('plant-1');
  });
  final store = PlantStore(
    persistence: repo,
    repository: gateway,
    clock: clock,
  );
  await tester.runAsync(() => store.initialized);
  final observer = DRouteObserver();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: buildAppTheme(),
        navigatorObservers: [observer],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          child: FocusVisibility(child: child!),
        ),
        home: const MyPlantsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return DWidgetFixture(store, repo, gateway, observer);
}

Future<void> dTap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 65));
  });
  await tester.pumpAndSettle();
}

Future<void> openAddD(WidgetTester tester) =>
    dTap(tester, find.byKey(const Key('add-plant-button')));
Future<void> openEditD(WidgetTester tester) async {
  await dTap(tester, find.byKey(const Key('details-plant-1')));
  await dTap(tester, find.byKey(const Key('details-edit-plant-1')));
}

String? fieldHint(WidgetTester tester, String key) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(TextField),
      ),
    )
    .decoration
    ?.hintText;

void main() {
  testWidgets('name inputs expose their labels to assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final f = await mountD(tester);
    try {
      await openAddD(tester);
      for (final label in [
        'Nickname',
        'Full Name (optional)',
        'Scientific Name',
      ]) {
        expect(find.bySemanticsLabel(label), findsWidgets);
      }
    } finally {
      await f.close(tester);
      semantics.dispose();
    }
  });
  testWidgets(
    'Add starts empty with Pothos, original art and Fahrenheit-only gray hints',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        expect(find.text('Add a Plant'), findsOneWidget);
        for (final key in [
          'nickname-field',
          'full-name-field',
          'species-field',
          for (final m in formMetrics) ...[
            rangeFieldKey(m, 0),
            rangeFieldKey(m, 1),
          ],
        ]) {
          expect(
            tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text,
            isEmpty,
          );
        }
        expect(
          tester
              .widget<PlantAvatarSelector>(find.byType(PlantAvatarSelector))
              .value,
          PlantAvatarId.pothos,
        );
        expect(fieldHint(tester, 'range-temperature-0'), '65');
        expect(fieldHint(tester, 'range-temperature-1'), '85');
        expect(find.text('MIN'), findsNWidgets(4));
        expect(find.text('MAX'), findsNWidgets(4));
        expect(find.text('Face + bubble update'), findsNothing);
        expect(find.byKey(const Key('form-validation-summary')), findsNothing);
        final large = tester.widget<LargeMoodPreview>(
          find.byType(LargeMoodPreview),
        );
        expect(large.data.largeAppearance.need, 'needs/happy_heart.png');
        expect(large.data.cardAppearance.need, isNull);
        expect(await tester.runAsync(() => f.repo.loadDevices()), hasLength(1));
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'invalid Save shows red summary/all inline errors and focuses first input without saving hints',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(find.text('This field is required.'), findsNWidgets(10));
        expect(
          find.text('Please fill in all required fields.'),
          findsOneWidget,
        );
        final summary = tester.widget<Text>(
          find.byKey(const Key('form-validation-summary')),
        );
        expect(summary.style!.color, AppColors.terracotta);
        expect(summary.style!.fontSize, 13);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'nickname-field',
        );
        expect(f.store.plants.length, 1);
        await fillPlantForm(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('form-validation-summary')), findsNothing);
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(f.store.plants.length, 2);
        expect(f.routes.routes.length, 1);
        expect(f.store.plants.last.latestReading, isNull);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'avatar changes art/hints only, retaining typed scientific identity and range text',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        await enterFormText(tester, 'species-field', 'Majikium flowerium');
        await enterFormText(tester, 'range-light-0', '123.45');
        await dTap(tester, find.byKey(const Key('avatar-peaceLily')));
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('species-field')))
              .controller!
              .text,
          'Majikium flowerium',
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('range-light-0')))
              .controller!
              .text,
          '123.45',
        );
        expect(fieldHint(tester, 'range-temperature-1'), '80');
        expect(
          tester.widget<LargeMoodPreview>(find.byType(LargeMoodPreview)).avatar,
          PlantAvatarId.peaceLily,
        );
        await dTap(tester, find.byKey(const Key('form-back')));
        expect(f.store.plants.length, 1);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'nickname warning remains valid; Full Name stores completely and Details truncates/falls back',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        const full = 'Bartholomew Cornelius III';
        await fillPlantForm(
          tester,
          nickname: 'A companion with a very long nickname',
          fullName: full,
        );
        expect(
          find.text('Long names may be shortened on plant cards.'),
          findsOneWidget,
        );
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(f.store.plants.last.fullName, full);
        await dTap(
          tester,
          find.byKey(Key('details-${f.store.plants.last.id}')),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('details-nickname'))).data,
          'Bartholomew Cor…',
        );
        await dTap(
          tester,
          find.byKey(Key('details-edit-${f.store.plants.last.id}')),
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('full-name-field')))
              .controller!
              .text,
          full,
        );
        await enterFormText(tester, 'full-name-field', '');
        await dTap(tester, find.byKey(const Key('save-changes-button')));
        expect(f.store.plants.last.fullName, isNull);
        expect(
          tester.widget<Text>(find.byKey(const Key('details-nickname'))).data,
          f.store.plants.last.nickname,
        );
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    '26 graphemes are rejected and all entered Full Name characters remain for correction',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        final value = List.filled(26, '👩🏽‍🌾').join();
        await fillPlantForm(tester, fullName: value);
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(find.text('Use at most 25 characters.'), findsOneWidget);
        expect(
          find.text('Please correct the highlighted fields.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('full-name-field')))
              .controller!
              .text,
          value,
        );
        expect(f.store.plants.length, 1);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'Edit uses saved values, actual low-light mood; Cancel and unrelated store notifications preserve draft',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openEditD(tester);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('nickname-field')))
              .controller!
              .text,
          'Florence',
        );
        expect(
          tester
              .widget<LargeMoodPreview>(find.byType(LargeMoodPreview))
              .data
              .mood,
          PreviewMood.lightBelow,
        );
        await enterFormText(tester, 'nickname-field', 'Unsaved nickname');
        await tester.runAsync(() => f.store.reload());
        await tester.pump();
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('nickname-field')))
              .controller!
              .text,
          'Unsaved nickname',
        );
        await dTap(tester, find.byKey(const Key('form-back')));
        expect(find.byType(PlantDetailsScreen), findsOneWidget);
        expect(f.store.plants.first.nickname, 'Florence');
        expect(f.routes.routes.length, 2);
        expect(
          await tester.runAsync(() => f.repo.loadHistory('plant-1')),
          hasLength(1),
        );
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'explicit preview override survives genuine incoming packets and never persists preview data',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openEditD(tester);
        await dTap(tester, find.byKey(const Key('mood-selector')));
        await dTap(tester, find.text('Healthy').last);
        expect(
          tester
              .widget<LargeMoodPreview>(find.byType(LargeMoodPreview))
              .data
              .mood,
          PreviewMood.healthy,
        );
        await tester.runAsync(() => f.store.refresh('plant-1'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<LargeMoodPreview>(find.byType(LargeMoodPreview))
              .data
              .mood,
          PreviewMood.healthy,
        );
        expect(f.store.plants.first.latestReading!.light, 635.11);
        expect(
          await tester.runAsync(() => f.repo.loadHistory('plant-1')),
          hasLength(2),
        );
        await dTap(tester, find.byKey(const Key('form-back')));
        expect(f.store.plants.first.latestReading!.light, 635.11);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'unassessed Edit has no automatic face until an explicit preview is selected',
    (tester) async {
      final f = await mountD(tester);
      try {
        await tester.runAsync(
          () => f.repo.database.customStatement('DELETE FROM sensor_readings'),
        );
        await tester.runAsync(() => f.store.reload());
        await openEditD(tester);
        final data = tester
            .widget<LargeMoodPreview>(find.byType(LargeMoodPreview))
            .data;
        expect(data.mood, isNull);
        expect(data.largeAppearance.face, isNull);
        expect(find.text('Choose a preview'), findsOneWidget);
        expect(f.store.plants.first.latestReading, isNull);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'expanded inventory disables other-owned device, creates multiple candidates but saves only selected',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        await dTap(tester, find.byKey(const Key('scan-devices-button')));
        expect(find.text('Assigned to Florence'), findsOneWidget);
        expect(find.byKey(const Key('connect-device-1')), findsNothing);
        await dTap(tester, find.byKey(const Key('create-device-button')));
        await dTap(tester, find.byKey(const Key('create-device-button')));
        final draft = tester
            .widget<CompanionDeviceSection>(find.byType(CompanionDeviceSection))
            .draft;
        expect(draft.candidates.length, 2);
        expect(await tester.runAsync(() => f.repo.loadDevices()), hasLength(1));
        await dTap(
          tester,
          find.byKey(Key('connect-${draft.candidates.first.candidate.id}')),
        );
        await fillPlantForm(tester);
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(f.store.plants.length, 2);
        expect(f.store.devices.length, 2);
        expect(f.store.devices.last.id, 'device-2');
        expect(f.store.devices.last.isConnected, isTrue);
        expect(f.store.plants.last.latestReading!.sourceDeviceId, 'device-2');
        expect(f.routes.routes.length, 1);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'cancel during candidate connection discards late result and consumes no durable IDs',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        await dTap(tester, find.byKey(const Key('scan-devices-button')));
        await dTap(tester, find.byKey(const Key('create-device-button')));
        final draft = tester
                .widget<CompanionDeviceSection>(
                  find.byType(CompanionDeviceSection),
                )
                .draft,
            candidate = draft.candidates.single;
        f.gateway.connection = Completer<Device>();
        await dTap(
          tester,
          find.byKey(Key('connect-${candidate.candidate.id}')),
        );
        await dTap(tester, find.byKey(const Key('form-back')));
        await tester.runAsync(() async {
          f.gateway.connection!.complete(
            candidate.candidate.withConnection(true),
          );
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();
        expect(f.store.plants.length, 1);
        expect(await tester.runAsync(() => f.repo.loadDevices()), hasLength(1));
        expect(
          (await tester.runAsync(
            () => f.repo.database.rows(
              "SELECT next_value FROM id_counters WHERE kind='device'",
            ),
          ))!.single['next_value'],
          2,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'failed Save keeps selected candidate/entries and creates no persistent device',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        await fillPlantForm(tester);
        await dTap(tester, find.byKey(const Key('scan-devices-button')));
        await dTap(tester, find.byKey(const Key('create-device-button')));
        final draft = tester
            .widget<CompanionDeviceSection>(find.byType(CompanionDeviceSection))
            .draft;
        await dTap(
          tester,
          find.byKey(Key('connect-${draft.candidates.single.candidate.id}')),
        );
        await tester.runAsync(
          () => f.repo.database.customStatement(
            "CREATE TRIGGER reject_save BEFORE INSERT ON plant_ranges BEGIN SELECT RAISE(ABORT,'test'); END",
          ),
        );
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(
          find.text(
            'Could not save to local storage. Your entries were kept. Try again.',
          ),
          findsOneWidget,
        );
        expect(find.byType(PlantFormScreen), findsOneWidget);
        expect(draft.createsDevice, isTrue);
        expect(await tester.runAsync(() => f.repo.loadDevices()), hasLength(1));
        await tester.runAsync(
          () => f.repo.database.customStatement('DROP TRIGGER reject_save'),
        );
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(f.store.plants.last.id, 'plant-2');
        expect(f.store.devices.last.id, 'device-2');
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'Edit conflict keeps draft and explicit Reload Current Data refreshes the captured revision',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openEditD(tester);
        await enterFormText(tester, 'nickname-field', 'My unsaved edit');
        await tester.runAsync(
          () => f.repo.save(
            draft('External', deviceId: 'device-1'),
            plantId: 'plant-1',
          ),
        );
        await dTap(tester, find.byKey(const Key('save-changes-button')));
        expect(find.byKey(const Key('reload-current-data')), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('nickname-field')))
              .controller!
              .text,
          'My unsaved edit',
        );
        await dTap(tester, find.byKey(const Key('reload-current-data')));
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('nickname-field')))
              .controller!
              .text,
          'External',
        );
        await dTap(tester, find.byKey(const Key('save-changes-button')));
        expect(find.byType(PlantDetailsScreen), findsOneWidget);
        expect(f.gateway.acquisitions, 0);
        expect(f.routes.routes.length, 2);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'Change Device opens same plant Edit, expanded and scrolled to inline controls',
    (tester) async {
      final f = await mountD(tester);
      try {
        await dTap(tester, find.byKey(const Key('details-plant-1')));
        await dTap(tester, find.text('ESP32-Sim01 · Change Device'));
        expect(find.byType(PlantFormScreen), findsOneWidget);
        expect(f.routes.routes.length, 3);
        final section = tester.widget<CompanionDeviceSection>(
          find.byType(CompanionDeviceSection),
        );
        expect(section.draft.expanded, isTrue);
        expect(section.draft.plantId, 'plant-1');
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        final rect = tester.getRect(
          find.byKey(const Key('companion-device-section')),
        );
        expect(rect.top, lessThan(925));
        expect(rect.bottom, greaterThan(112));
        await dTap(tester, find.byKey(const Key('form-back')));
        expect(find.byType(PlantDetailsScreen), findsOneWidget);
        expect(f.routes.routes.length, 2);
      } finally {
        await f.close(tester);
      }
    },
  );
  for (final failure in ['reload', 'scheduler']) {
    testWidgets(
      'one-tap Delete plus $failure failure unwinds safely with truthful committed notice',
      (tester) async {
        final f = await mountD(tester);
        try {
          await openEditD(tester);
          if (failure == 'reload') {
            f.repo.loadsAfterDelete = 2;
          } else {
            await tester.runAsync(() => f.store.scheduler.resume());
            f.repo.failSchedulerAfterDelete = true;
          }
          await dTap(tester, find.byKey(const Key('delete-plant-button')));
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(PlantFormScreen), findsNothing);
          expect(find.byType(PlantDetailsScreen), findsNothing);
          expect(f.routes.routes.length, 1);
          expect(find.text('No plants yet.'), findsOneWidget);
          expect(find.byKey(const Key('post-commit-notice')), findsOneWidget);
          expect(
            tester
                .widget<Text>(find.byKey(const Key('post-commit-notice')))
                .data,
            startsWith('Plant deleted.'),
          );
          expect(await tester.runAsync(() => f.repo.loadPlants()), isEmpty);
          expect(await tester.runAsync(() => f.repo.loadDevices()), isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await f.close(tester);
        }
      },
    );
  }
  testWidgets(
    'uncertain Add disables changes and checks same durable operation without duplicate creation',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        await fillPlantForm(tester);
        f.repo.loseSaveAck = true;
        f.repo.receiptLookupFailures = 1;
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(find.text('Check Save Result'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('nickname-field')))
              .enabled,
          isFalse,
        );
        expect(await tester.runAsync(() => f.repo.loadPlants()), hasLength(2));
        await dTap(tester, find.byKey(const Key('check-commit-result')));
        expect(f.routes.routes.length, 1);
        expect(f.store.plants.length, 2);
      } finally {
        await f.close(tester);
      }
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'forward route slides from right and respects reduced motion: $reduced',
      (tester) async {
        final f = await mountD(tester, reducedMotion: reduced);
        try {
          await tester.tap(find.byKey(const Key('add-plant-button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 55));
          final x = tester
              .getTopLeft(find.byKey(const Key('form-progress')))
              .dx;
          expect(x, reduced ? closeTo(24, .01) : greaterThan(24));
          expect(
            find.ancestor(
              of: find.byType(PlantFormScreen),
              matching: find.byType(ScaleTransition),
            ),
            findsNothing,
          );
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(find.byKey(const Key('form-progress'))).dx,
            24,
          );
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(f.routes.routes.length, 1);
        } finally {
          await f.close(tester);
        }
      },
    );
  }
  testWidgets(
    'selection Edit Save returns to existing Home while Cancel returns to selection',
    (tester) async {
      final f = await mountD(tester);
      try {
        await tester.tap(find.byKey(const Key('open-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('edit-plants')));
        await tester.pumpAndSettle();
        expect(find.text('CHOOSE A PLANT TO EDIT'), findsOneWidget);
        expect(f.store.plants.single.id, 'plant-1');
        await dTap(tester, find.byKey(const Key('edit-plant-1')));
        await enterFormText(tester, 'nickname-field', 'Cancelled');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('CHOOSE A PLANT TO EDIT'), findsOneWidget);
        expect(f.store.plants.first.nickname, 'Florence');
        await dTap(tester, find.byKey(const Key('edit-plant-1')));
        await enterFormText(tester, 'nickname-field', 'Saved from selection');
        await dTap(tester, find.byKey(const Key('save-changes-button')));
        expect(f.routes.routes.length, 1);
        expect(f.store.plants.first.nickname, 'Saved from selection');
        expect(find.byKey(const Key('open-menu')), findsOneWidget);
        expect(f.gateway.acquisitions, 0);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'Delete ignores draft candidate and deletes actual saved assignment in one tap',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openEditD(tester);
        await dTap(tester, find.byKey(const Key('scan-devices-button')));
        await dTap(tester, find.byKey(const Key('create-device-button')));
        final deviceDraft = tester
            .widget<CompanionDeviceSection>(find.byType(CompanionDeviceSection))
            .draft;
        await dTap(
          tester,
          find.byKey(
            Key('connect-${deviceDraft.candidates.single.candidate.id}'),
          ),
        );
        await dTap(tester, find.byKey(const Key('delete-plant-button')));
        expect(f.routes.routes.length, 1);
        expect(f.store.plants, isEmpty);
        expect(await tester.runAsync(() => f.repo.loadDevices()), isEmpty);
        final counters = await tester.runAsync(
          () => f.repo.database.rows(
            "SELECT next_value FROM id_counters WHERE kind='device'",
          ),
        );
        expect(counters!.single['next_value'], 2);
        await tester.runAsync(() => f.repo.initialize());
        expect(await tester.runAsync(() => f.repo.loadPlants()), isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'post-save acquisition failure navigates successfully with secondary notice and no fake sync',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        await fillPlantForm(tester);
        await dTap(tester, find.byKey(const Key('scan-devices-button')));
        await dTap(tester, find.byKey(const Key('create-device-button')));
        final deviceDraft = tester
            .widget<CompanionDeviceSection>(find.byType(CompanionDeviceSection))
            .draft;
        await dTap(
          tester,
          find.byKey(
            Key('connect-${deviceDraft.candidates.single.candidate.id}'),
          ),
        );
        f.gateway.failAcquisition = true;
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(f.routes.routes.length, 1);
        expect(f.store.plants.last.latestReading, isNull);
        expect(f.store.deviceFor(f.store.plants.last)!.isConnected, isTrue);
        expect(
          tester.widget<Text>(find.byKey(const Key('post-commit-notice'))).data,
          startsWith('Plant saved. Could not acquire readings.'),
        );
        expect(find.byKey(const Key('save-plant-button')), findsNothing);
        expect(f.store.plants.first.latestReading!.light, 280);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'post-save reload failure does not leave a duplicate-Add retry control',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openAddD(tester);
        await fillPlantForm(tester);
        f.repo.loadsAfterSave = 2;
        await dTap(tester, find.byKey(const Key('save-plant-button')));
        expect(f.routes.routes.length, 1);
        expect(
          tester.widget<Text>(find.byKey(const Key('post-commit-notice'))).data,
          startsWith('Plant saved.'),
        );
        expect(await tester.runAsync(() => f.repo.loadPlants()), hasLength(2));
        expect(find.byKey(const Key('save-plant-button')), findsNothing);
        await tester.runAsync(() => f.store.reload());
        await tester.pumpAndSettle();
        expect(f.store.plants.length, 2);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'lower field focus and validation stay above keyboard; Save remains reachable',
    (tester) async {
      final f = await mountD(tester, size: const Size(390, 844));
      try {
        await openAddD(tester);
        await fillPlantForm(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await dTap(tester, find.byKey(const Key('range-humidity-1')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'range-humidity-1',
        );
        expect(
          tester.getRect(find.byKey(const Key('range-humidity-1'))).bottom,
          lessThanOrEqualTo(544),
        );
        final back = tester.getRect(find.byKey(const Key('form-back')));
        await tester.ensureVisible(find.byKey(const Key('save-plant-button')));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('save-plant-button'))).bottom,
          lessThanOrEqualTo(544),
        );
        expect(tester.getRect(find.byKey(const Key('form-back'))), back);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets('progress tracks actual extent when inline inventory expands', (
    tester,
  ) async {
    final f = await mountD(tester);
    final semantics = tester.ensureSemantics();
    try {
      await openAddD(tester);
      await tester.ensureVisible(find.byKey(const Key('save-plant-button')));
      await tester.pumpAndSettle();
      final label = find.bySemanticsLabel('Form scroll progress');
      expect(tester.getSemantics(label).getSemanticsData().value, '100%');
      await dTap(tester, find.byKey(const Key('scan-devices-button')));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(label).getSemanticsData().value,
        isNot('100%'),
      );
      await tester.ensureVisible(find.byKey(const Key('save-plant-button')));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(label).getSemanticsData().value, '100%');
    } finally {
      semantics.dispose();
      await f.close(tester);
    }
  });
  testWidgets(
    'no-op Edit preserves exact Celsius ranges despite rounded Fahrenheit display',
    (tester) async {
      final f = await mountD(tester);
      try {
        const low = 18.1234567890123, high = 29.9876543210987;
        await tester.runAsync(
          () => f.repo.database.customStatement(
            "UPDATE plant_ranges SET minimum=?,maximum=? WHERE plant_id='plant-1' AND metric='temperature'",
            [low, high],
          ),
        );
        await tester.runAsync(() => f.store.reload());
        await openEditD(tester);
        await dTap(tester, find.byKey(const Key('save-changes-button')));
        final range = f.store.plants.first.profile.rangeFor(
          SensorMetric.temperature,
        );
        expect(range.minimum, low);
        expect(range.maximum, high);
        expect(f.gateway.acquisitions, 0);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'narrow valid temperature ranges retain distinct Fahrenheit inputs and allow exact no-op Save',
    (tester) async {
      final f = await mountD(tester);
      try {
        const low = 18.34, high = 18.35;
        await tester.runAsync(
          () => f.repo.database.customStatement(
            "UPDATE plant_ranges SET minimum=?,maximum=? WHERE plant_id='plant-1' AND metric='temperature'",
            [low, high],
          ),
        );
        await tester.runAsync(() => f.store.reload());
        await openEditD(tester);
        final minimum = tester
            .widget<TextFormField>(find.byKey(const Key('range-temperature-0')))
            .controller!
            .text;
        final maximum = tester
            .widget<TextFormField>(find.byKey(const Key('range-temperature-1')))
            .controller!
            .text;
        expect(double.parse(minimum), lessThan(double.parse(maximum)));
        await dTap(tester, find.byKey(const Key('save-changes-button')));
        expect(find.byKey(const Key('save-changes-button')), findsNothing);
        final range = f.store.plants.first.profile.rangeFor(
          SensorMetric.temperature,
        );
        expect(range.minimum, low);
        expect(range.maximum, high);
        expect(f.gateway.acquisitions, 0);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'deleted plant conflict retains draft and cannot recreate target; explicit reload safely leaves',
    (tester) async {
      final f = await mountD(tester);
      try {
        await openEditD(tester);
        await enterFormText(
          tester,
          'nickname-field',
          'Draft survives conflict',
        );
        await tester.runAsync(() => f.repo.deletePlant('plant-1'));
        await dTap(tester, find.byKey(const Key('save-changes-button')));
        expect(find.byKey(const Key('reload-current-data')), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('nickname-field')))
              .controller!
              .text,
          'Draft survives conflict',
        );
        expect(
          find.byType(PlantDetailsScreen, skipOffstage: false),
          findsNothing,
        );
        await dTap(tester, find.byKey(const Key('reload-current-data')));
        expect(f.routes.routes.length, 1);
        expect(f.store.plants, isEmpty);
        expect(await tester.runAsync(() => f.repo.loadPlants()), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await f.close(tester);
      }
    },
  );
  for (final size in [const Size(320, 640), const Size(1440, 900)]) {
    testWidgets(
      'Edit Delete/Save controls grow without clipping at text2: $size',
      (tester) async {
        final f = await mountD(tester, size: size, scale: 2);
        try {
          await openEditD(tester);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.ensureVisible(
            find.byKey(const Key('save-changes-button')),
          );
          await tester.pumpAndSettle();
          final remove = tester.getRect(
                find.byKey(const Key('delete-plant-button')),
              ),
              save = tester.getRect(
                find.byKey(const Key('save-changes-button')),
              );
          expect(remove.right, lessThanOrEqualTo(save.left));
          expect(remove.top, save.top);
          expect(remove.bottom, lessThanOrEqualTo(size.height));
          expect(save.bottom, lessThanOrEqualTo(size.height));
          expect(tester.takeException(), isNull);
        } finally {
          await f.close(tester);
        }
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
        'form ${size.width}×${size.height} text$scale: fixed shell, long text and reachable Save',
        (tester) async {
          final f = await mountD(tester, size: size, scale: scale);
          try {
            await openAddD(tester);
            await enterFormText(
              tester,
              'nickname-field',
              'A long companion nickname 👩🏽‍🌾 é with many words',
            );
            await enterFormText(
              tester,
              'species-field',
              'An unusually long custom scientific identity',
            );
            final header = tester.getRect(find.byKey(const Key('form-back'))),
                progress = tester.getRect(
                  find.byKey(const Key('form-progress')),
                );
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pump(const Duration(milliseconds: 250));
            await tester.ensureVisible(
              find.byKey(const Key('save-plant-button')),
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(find.byKey(const Key('form-back'))), header);
            expect(
              tester.getRect(find.byKey(const Key('form-progress'))),
              progress,
            );
            expect(
              tester.getRect(find.byKey(const Key('save-plant-button'))).bottom,
              lessThanOrEqualTo(size.height),
            );
            expect(tester.takeException(), isNull);
          } finally {
            await f.close(tester);
          }
        },
      );
    }
  }
}
