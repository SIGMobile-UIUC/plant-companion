import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plant_companion/models/plant_form_draft.dart';
import 'package:plant_companion/services/fake_sensor_repository.dart';
import 'package:plant_companion/screens/my_plants_screen.dart';
import 'package:plant_companion/state/plant_store.dart';
import 'package:plant_companion/theme/app_theme.dart';
import 'package:plant_companion/widgets/plant_card.dart';
import 'fixtures/foundation_fixtures.dart';

void main() {
  test(
    'published list snapshots are immutable, reused and replaced after mutations',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 11, 9)),
          repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 9))),
          store = PlantStore(
            persistence: repo,
            clock: clock,
            repository: FakeSensorRepository(delay: Duration.zero),
          );
      try {
        await store.initialized;
        final plants = store.plants, devices = store.devices;
        expect(identical(plants, store.plants), true);
        expect(identical(devices, store.devices), true);
        expect(() => plants.clear(), throwsUnsupportedError);
        expect(() => devices.clear(), throwsUnsupportedError);
        final id = await store.saveDraft(draft('Other'));
        expect(plants.length, 1);
        expect(store.plants.length, 2);
        expect(identical(plants, store.plants), false);
        final current = store.plantById('plant-1');
        await store.saveDraft(
          PlantFormDraft(
            nickname: 'Renamed',
            speciesName: current.speciesName,
            avatar: current.avatar,
            ranges: current.profile.ranges,
            deviceId: current.deviceId,
          ),
          plantId: current.id,
        );
        expect(plants.single.nickname, 'Florence');
        expect(store.plantById('plant-1').nickname, 'Renamed');
        await store.refresh('plant-1');
        expect(identical(store.plants, store.plants), true);
        expect(devices.single.generationSequence, 0);
        expect(store.devices.single.generationSequence, greaterThan(0));
        await store.deletePlant(id);
        expect(store.plants.length, 1);
        expect(plants.single.nickname, 'Florence');
      } finally {
        store.dispose();
      }
    },
  );
  test(
    'batched pruning preserves each latest-relative cutoff, inclusive boundary, old sources and empty plants',
    () async {
      final clock = MutableClock(DateTime.utc(2026, 11, 9)),
          repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 9)));
      try {
        await repo.initialize();
        final ids = [
          'plant-1',
          await repo.save(draft('Ancient')),
          await repo.save(draft('Empty')),
        ];
        await repo.database.customStatement('DELETE FROM sensor_readings');
        final expected = <String>[];
        for (var p = 0; p < 2; p++) {
          final latest = DateTime.utc(
            p == 0 ? 2026 : 2001,
            1,
            1,
          ).millisecondsSinceEpoch;
          final offsets = [
            -9 * 86400000,
            -7 * 86400000 - 1,
            -7 * 86400000,
            -7 * 86400000 + 1,
            -1,
            0,
          ];
          for (var j = 0; j < offsets.length; j++) {
            final id = 'retention-$p-$j';
            await repo.database.customStatement(
              'INSERT INTO sensor_readings(id,plant_id,source_device_id,recorded_at_ms,soil_moisture,origin) VALUES (?,?,?,?,?,?)',
              [
                id,
                ids[p],
                j.isEven ? 'deleted-source' : 'current-source',
                latest + offsets[j],
                null,
                'manual',
              ],
            );
            if (offsets[j] >= -7 * 86400000) expected.add(id);
          }
        }
        clock.value = DateTime.utc(2100);
        await repo.pruneHistory();
        final rows = await repo.database.rows(
          'SELECT id FROM sensor_readings ORDER BY id',
        );
        expect(rows.map((r) => r['id']).toList(), expected..sort());
        expect(await repo.loadHistory(ids.last), isEmpty);
        await repo.initialize();
        expect(
          (await repo.database.rows(
            'SELECT id FROM sensor_readings ORDER BY id',
          )).map((r) => r['id']).toList(),
          expected,
        );
      } finally {
        await repo.close();
      }
    },
  );
  testWidgets(
    '100-plant compact list uses fixed extent and preserves accessible fallback',
    (tester) async {
      tester.view.physicalSize = const Size(430, 925);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = MutableClock(DateTime.utc(2026, 11, 9)),
          repo = memoryRepository(MutableClock(DateTime.utc(2026, 11, 9))),
          store = PlantStore(
            persistence: repo,
            clock: clock,
            repository: FakeSensorRepository(delay: Duration.zero),
          );
      await tester.runAsync(() async {
        await store.initialized;
        for (var i = 1; i < 100; i++) {
          await repo.save(draft('Plant $i'));
        }
        await store.reload();
      });
      Widget app(double scale) => ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const MyPlantsScreen(),
        ),
      );
      await tester.pumpWidget(app(1));
      await tester.pump(const Duration(milliseconds: 500));
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.itemExtent, 236);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(find.byType(PlantCard).evaluate().length, lessThan(12));
      expect(
        find.byKey(const ValueKey('plant-card-plant-100')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<ListView>(find.byType(ListView)).itemExtent, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
