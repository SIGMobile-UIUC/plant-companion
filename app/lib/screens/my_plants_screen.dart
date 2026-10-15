import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plant.dart';
import '../state/plant_store.dart';
import '../theme/app_theme.dart';
import '../utils/reading_time.dart';
import '../widgets/page_body.dart';
import '../widgets/plant_avatar.dart';
import '../widgets/plant_condition.dart';
import '../widgets/status_badge.dart';
import 'add_plant_screen.dart';
import 'plant_details_screen.dart';

class MyPlantsScreen extends StatelessWidget {
  const MyPlantsScreen({super.key});

  void _addPlant(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const AddPlantScreen()));

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlantStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Companion.'),
        leading: const Padding(
          padding: EdgeInsets.only(left: 20),
          child: Icon(Icons.spa, color: AppColors.forest),
        ),
        actions: [
          IconButton(
            tooltip: 'About this demo',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Made to grow with you'),
                content: const Text(
                  'A SIGmobile frontend demo. All readings, connections and battery values are simulated. Demo target ranges are examples, not plant-care recommendations. Plants and readings stay in memory and reset when you restart.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Got it'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SIGMOBILE  /  YOUR GREEN CORNER',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.muted,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Good things\ngrow here.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'A little attention for the plants that make your space feel like home.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.sage,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.science_outlined,
                    color: AppColors.forest,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Demo garden\nSimulated sensors. Real room to explore.',
                      style: TextStyle(color: AppColors.forest, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'My Plants',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${store.plants.length} ${store.plants.length == 1 ? 'plant' : 'plants'}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (store.plants.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.yard_outlined,
                        color: AppColors.forest,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your garden starts here',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Give your first plant a name. A device is optional.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => _addPlant(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Plant'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              for (final plant in store.plants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PlantCard(plant: plant, store: store),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('add-plant-button'),
                  onPressed: () => _addPlant(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Plant'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Small rituals. Happy leaves.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlantCard extends StatelessWidget {
  const _PlantCard({required this.plant, required this.store});
  final Plant plant;
  final PlantStore store;

  @override
  Widget build(BuildContext context) {
    final condition = PlantCondition.forPlant(
      plant,
      store.deviceFor(plant),
      isStale: store.isStale(plant),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('plant-card-${plant.id}'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlantDetailsScreen(plantId: plant.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlantAvatar(condition: condition, size: 72),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plant.nickname,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plant.profile.plantType,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              StatusBadge(
                label: condition.label,
                icon: condition.icon,
                attention: condition.attention,
              ),
              const SizedBox(height: 10),
              Text(
                'Last reading · ${readingAge(plant.latestReading?.recordedAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
