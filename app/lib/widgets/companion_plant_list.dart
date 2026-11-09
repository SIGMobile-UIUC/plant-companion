import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/plant_store.dart';
import 'plant_card.dart';

class CompanionPlantList extends StatelessWidget {
  const CompanionPlantList({
    super.key,
    required this.onAction,
    this.edit = false,
  });
  final void Function(String plantId) onAction;
  final bool edit;
  @override
  Widget build(BuildContext context) => Consumer<PlantStore>(
    builder: (context, store, _) => ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: store.plants.isEmpty && !edit
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No plants yet.',
                    style: TextStyle(
                      fontFamily: 'Pixelify Sans',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Tap + to add one.',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 14),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final plants = store.plants;
                final compact = PlantCard.usesCompactLayout(
                  constraints.maxWidth - 36,
                  MediaQuery.textScalerOf(context),
                );
                Widget card(BuildContext context, int index) {
                  final plant = plants[index];
                  return PlantCard(
                    key: ValueKey('plant-card-${plant.id}'),
                    plant: plant,
                    device: store.deviceFor(plant),
                    now: store.clock.now(),
                    edit: edit,
                    onAction: () => onAction(plant.id),
                  );
                }

                final padding = EdgeInsets.fromLTRB(
                  18,
                  edit ? 0 : 70,
                  18,
                  (compact ? 12 : 24) + MediaQuery.paddingOf(context).bottom,
                );
                final key = PageStorageKey(
                  edit ? 'selection-list' : 'home-list',
                );
                // Compact cards are content-independent 224px, plus a 12px gap.
                // Fixed extents avoid laying out intervening cards on long jumps.
                if (compact) {
                  return ListView.builder(
                    key: key,
                    padding: padding,
                    itemCount: plants.length,
                    itemExtent: 236,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: card(context, index),
                    ),
                  );
                }
                return ListView.separated(
                  key: key,
                  padding: padding,
                  itemCount: plants.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: card,
                );
              },
            ),
    ),
  );
}
