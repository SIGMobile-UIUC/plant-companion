import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../models/plant.dart';
import '../models/sensor_reading.dart';
import '../state/plant_store.dart';
import '../theme/app_theme.dart';
import '../utils/reading_time.dart';
import '../widgets/page_body.dart';
import '../widgets/plant_avatar.dart';
import '../widgets/plant_condition.dart';
import '../widgets/reading_card.dart';
import '../widgets/status_badge.dart';

class PlantDetailsScreen extends StatelessWidget {
  const PlantDetailsScreen({super.key, required this.plantId});
  final String plantId;

  Future<void> _refresh(BuildContext context) async {
    final message = await context.read<PlantStore>().refresh(plantId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showDemoMenu(BuildContext context, Plant plant) {
    final store = context.read<PlantStore>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Demo conditions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a simulated scene. These are demonstration thresholds, not a diagnosis.',
              ),
              const SizedBox(height: 12),
              for (final scenario in DemoScenario.values)
                ListTile(
                  key: Key('demo-${scenario.name}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _scenarioIcon(scenario),
                    color: AppColors.forest,
                  ),
                  title: Text(scenario.label),
                  subtitle: Text(_scenarioDescription(scenario)),
                  trailing: scenario == plant.demoScenario
                      ? const Icon(Icons.check, color: AppColors.forest)
                      : null,
                  onTap: () {
                    store.setDemoScenario(plantId, scenario);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _scenarioIcon(DemoScenario scenario) => switch (scenario) {
    DemoScenario.comfortable => Icons.check_circle_outline,
    DemoScenario.thirsty => Icons.water_drop_outlined,
    DemoScenario.lowLight => Icons.bedtime_outlined,
    DemoScenario.disconnected => Icons.bluetooth_disabled,
    DemoScenario.staleData => Icons.history,
  };

  String _scenarioDescription(DemoScenario scenario) => switch (scenario) {
    DemoScenario.comfortable =>
      'Reconnect and create a fresh, in-range reading.',
    DemoScenario.thirsty => 'Soil wetness index below the selected range.',
    DemoScenario.lowLight =>
      'Dim-light avatar example; one low reading is not a diagnosis.',
    DemoScenario.disconnected =>
      'Keep the last reading and its original timestamp.',
    DemoScenario.staleData =>
      'Load a two-hour-old packet; refresh keeps its timestamp.',
  };

  Future<void> _unlink(BuildContext context) async {
    final store = context.read<PlantStore>();
    final unlink = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlink simulated device?'),
        content: const Text(
          'Saved readings stay with this plant. The one ESP32 becomes available in Add Plant, so you can try the device setup demo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (unlink == true) store.unlinkDevice(plantId);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlantStore>();
    final plant = store.plantById(plantId);
    final device = store.deviceFor(plant);
    final stale = store.isStale(plant);
    final refreshing = store.isRefreshing(plantId);
    final condition = PlantCondition.forPlant(plant, device, isStale: stale);
    return Scaffold(
      appBar: AppBar(title: const Text('Plant Details')),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A MOMENT WITH YOUR PLANT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.muted,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              plant.nickname,
              key: const Key('details-nickname'),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 4),
            Text(
              plant.profile.plantType,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.sage,
                borderRadius: BorderRadius.circular(24),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final explanation = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(
                        label: condition.label,
                        icon: condition.icon,
                        attention: condition.attention,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        condition.explanation,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PlantAvatar(condition: condition, size: 116),
                        const SizedBox(height: 18),
                        explanation,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      PlantAvatar(condition: condition, size: 116),
                      const SizedBox(width: 20),
                      Expanded(child: explanation),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            if (device != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('demo-menu-button'),
                  onPressed: refreshing
                      ? null
                      : () => _showDemoMenu(context, plant),
                  icon: const Icon(Icons.tune),
                  label: Text('Demo conditions · ${plant.demoScenario.label}'),
                ),
              ),
            const SizedBox(height: 28),
            Text(
              'A closer look',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Simulated readings · demo target ranges',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  for (final metric in SensorMetric.values)
                    ReadingCard(
                      metric: metric,
                      value: plant.latestReading?.valueFor(metric),
                      range: plant.profile.rangeFor(metric),
                      isStale: stale,
                    ),
                ];
                final singleColumn =
                    constraints.maxWidth < 350 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                if (singleColumn) {
                  return Column(
                    children: [
                      for (final card in cards)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(width: double.infinity, child: card),
                        ),
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var index = 0; index < cards.length; index += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: cards[index]),
                              const SizedBox(width: 12),
                              Expanded(child: cards[index + 1]),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'Soil moisture is a relative wetness index (0–100), not a percentage of actual soil water. All ranges are configurable teaching examples, not scientifically established ideals for these species.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('refresh-button'),
                onPressed: refreshing ? null : () => _refresh(context),
                icon: refreshing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(refreshing ? 'Refreshing…' : 'Refresh readings'),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Your little helper',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _DeviceCard(
                plant: plant,
                device: device,
                stale: stale,
                onUnlink: refreshing ? null : () => _unlink(context),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Recent readings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Latest first · simulated · this session only',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (plant.readings.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No readings yet. A plant without a device can still be part of your garden.',
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < plant.readings.length;
                        index++
                      ) ...[
                        if (index != 0) const Divider(color: AppColors.border),
                        _RecentReading(reading: plant.readings[index]),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'This demo resets when the app restarts.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.plant,
    required this.device,
    required this.stale,
    required this.onUnlink,
  });
  final Plant plant;
  final Device? device;
  final bool stale;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device?.name ?? 'No device linked',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          StatusBadge(
            label: device == null
                ? 'Not linked'
                : 'Simulated · ${device!.isConnected ? 'Connected' : 'Disconnected'}',
            icon: device?.isConnected == true
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            attention: device != null && !device!.isConnected,
          ),
          const SizedBox(height: 16),
          Text(
            'Battery voltage · ${device?.batteryVoltage == null ? 'Unavailable' : '${device!.batteryVoltage!.toStringAsFixed(2)} V (simulated)'}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Text(
            'Last reading · ${readingTime(plant.latestReading?.recordedAt)}',
            key: const Key('last-reading-time'),
            style: const TextStyle(color: AppColors.muted),
          ),
          if (plant.latestReading != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                stale
                    ? 'Stale · older than 30 minutes'
                    : 'Recent · ${readingAge(plant.latestReading!.recordedAt)}',
                style: TextStyle(
                  color: stale ? AppColors.terracotta : AppColors.forest,
                ),
              ),
            ),
          if (device != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                onPressed: onUnlink,
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Unlink simulated device'),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RecentReading extends StatelessWidget {
  const _RecentReading({required this.reading});
  final SensorReading reading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          readingTime(reading.recordedAt),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final metric in SensorMetric.values)
              Text(
                '${metric.label}: ${reading.valueFor(metric) == null ? 'Unavailable' : '${metric.format(reading.valueFor(metric)!)} ${metric.unit}'}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
          ],
        ),
      ],
    ),
  );
}
