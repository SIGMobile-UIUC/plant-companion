import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/plant_store.dart';
import '../services/plant_condition_calculator.dart';
import '../services/reading_scheduler.dart';
import '../services/condition_driven_simulation.dart';
import '../theme/app_theme.dart';
import '../widgets/reading_card.dart';
import '../widgets/sensor_rail.dart';
import '../widgets/details_device_card.dart';
import '../widgets/companion_header.dart';
import '../widgets/details_hero.dart';
import '../navigation/plant_navigation.dart';
import '../widgets/plant_operation_notice.dart';

class PlantDetailsScreen extends StatefulWidget {
  const PlantDetailsScreen({super.key, required this.plantId});
  final String plantId;
  @override
  State<PlantDetailsScreen> createState() => _PlantDetailsScreenState();
}

class _PlantDetailsScreenState extends State<PlantDetailsScreen> {
  final _scroll = ScrollController();
  bool _closing = false;
  String? _error;
  String? _errorPacket;
  String? _errorDevice;
  Future<void> _refresh() async {
    setState(() => _error = null);
    final store = context.read<PlantStore>();
    final result = await store.refresh(widget.plantId);
    if (!mounted || store.findPlant(widget.plantId) == null) return;
    final plant = store.findPlant(widget.plantId)!;
    setState(() {
      _error = switch (result) {
        RefreshResult.updatedPublicationFailed =>
          'Readings saved. Could not update the display. Try again.',
        RefreshResult.updatedSchedulerFailed =>
          'Readings saved. Automatic updates could not resume. Try again.',
        RefreshResult.connectionFailed => 'Could not reconnect. Try again.',
        RefreshResult.acquisitionFailed =>
          'Could not refresh readings. Try again.',
        RefreshResult.simulationUnavailable =>
          NoFeasibleManualCondition.message,
        RefreshResult.assignmentChanged =>
          'Device assignment changed. Try again.',
        _ => null,
      };
      _errorPacket = plant.latestReading?.id;
      _errorDevice = plant.deviceId;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlantStore>();
    final plant = store.findPlant(widget.plantId);
    if (plant == null) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final route = ModalRoute.of(context),
                navigator = Navigator.of(context);
            if (route?.isCurrent == true && navigator.canPop()) {
              navigator.pop();
            } else if (route != null && route.isActive) {
              navigator.removeRoute(route);
            }
          }
        });
      }
      return const SizedBox.shrink();
    }
    return Scaffold(
      body: CompanionSurface(
        child: Column(
          children: [
            CompanionHeader(
              variant: CompanionHeaderVariant.details,
              leading: SpriteAction(
                key: const Key('details-back'),
                label: 'Back',
                asset: 'actions/back.png',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              trailing: SpriteAction(
                key: const Key('refresh-button'),
                label: store.isRefreshing(plant.id)
                    ? 'Refreshing readings'
                    : 'Refresh readings',
                asset: 'actions/refresh_readings.png',
                onPressed:
                    plant.deviceId == null || store.isRefreshing(plant.id)
                    ? null
                    : _refresh,
              ),
            ),
            PlantOperationNotice(plantId: plant.id),
            if (_error != null &&
                _errorPacket == plant.latestReading?.id &&
                _errorDevice == plant.deviceId)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 6,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    key: const Key('details-refresh-error'),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.terracotta,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: SafeArea(
                top: false,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    key: ValueKey('details-scroll-${plant.id}'),
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                    child: Column(
                      children: [
                        DetailsHero(
                          plant: plant,
                          device: store.deviceFor(plant),
                          now: store.clock.now(),
                          onEdit: () => openPlantRoute(
                            context,
                            PlantRouteIntent(
                              PlantDestination.edit,
                              PlantRouteOrigin.details,
                              plantId: plant.id,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final metric in cardMetrics) ...[
                          ReadingCard(
                            plantId: plant.id,
                            metric: metric,
                            value: ReadingPresentation(plant).values[metric],
                            range: plant.profile.rangeFor(metric),
                            isDemonstration: plant.deviceId == null,
                          ),
                          if (metric != cardMetrics.last)
                            const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: DetailsDeviceCard(
                            device: store.deviceFor(plant),
                            onChange: () => openPlantRoute(
                              context,
                              PlantRouteIntent(
                                PlantDestination.edit,
                                PlantRouteOrigin.details,
                                plantId: plant.id,
                                expandDevice: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
