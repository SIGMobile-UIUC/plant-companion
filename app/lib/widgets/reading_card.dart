import 'package:flutter/material.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';

class ReadingCard extends StatelessWidget {
  const ReadingCard({
    super.key,
    required this.metric,
    required this.value,
    required this.range,
    this.isStale = false,
  });
  final SensorMetric metric;
  final double? value;
  final TargetRange range;
  final bool isStale;

  static IconData iconFor(SensorMetric metric) => switch (metric) {
    SensorMetric.soilMoisture => Icons.water_drop_outlined,
    SensorMetric.temperature => Icons.thermostat_outlined,
    SensorMetric.humidity => Icons.air,
    SensorMetric.light => Icons.wb_sunny_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final status = range.statusFor(value);
    final statusLabel = switch (status) {
      ReadingStatus.unavailable => 'Unavailable',
      ReadingStatus.belowRange => 'Below range',
      ReadingStatus.inRange => 'In range',
      ReadingStatus.aboveRange => 'Above range',
    };
    final attention = status != ReadingStatus.inRange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(iconFor(metric), size: 23, color: AppColors.forest),
            const SizedBox(height: 12),
            Text(metric.label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              value == null ? 'Unavailable' : metric.format(value!),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (value != null)
              Text(metric.unit, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            Text(
              'Demo target',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
            ),
            Text(
              range.format(metric),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            StatusBadge(
              label: statusLabel,
              icon: attention ? Icons.info_outline : Icons.check_circle_outline,
              attention: attention,
            ),
            if (isStale)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Saved value · stale',
                  style: TextStyle(color: AppColors.terracotta, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
