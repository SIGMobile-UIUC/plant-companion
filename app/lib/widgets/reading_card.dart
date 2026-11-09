import 'package:flutter/material.dart';
import '../models/plant_profile.dart';
import '../models/sensor_reading.dart';
import '../theme/app_theme.dart';
import 'companion_header.dart';
import 'plant_portrait.dart';
import 'sensor_rail.dart';

class ReadingCard extends StatelessWidget {
  const ReadingCard({
    super.key,
    required this.plantId,
    required this.metric,
    required this.value,
    required this.range,
    this.isDemonstration = false,
  });
  final String plantId;
  final SensorMetric metric;
  final double? value;
  final TargetRange range;
  final bool isDemonstration;
  @override
  Widget build(BuildContext context) {
    final title = metric == SensorMetric.soilMoisture
        ? 'Soil Moisture'
        : metric.label;
    final number = metricValue(metric, value, compactLight: false);
    final ideal =
        'Ideal ${metricRange(metric, range, compactLight: false).replaceAll(' – ', '–')}';
    final labelStyle = AppTextStyles.readingLabel.copyWith(
      color: const Color(0xFF193B2B),
    );
    const idealStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12.5,
      color: AppColors.muted,
    );
    Widget icon() => Image.asset(
      '$companionAssets${sensorAsset(metric)}',
      width: 50,
      height: 53,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
    );
    Widget rail() => SensorRail(
      plantId: plantId,
      metric: metric,
      range: range,
      current: value,
      variant: SensorRailVariant.details,
    );
    return Semantics(
      container: true,
      label:
          '$title, ${value == null ? 'Reading unavailable' : number}, $ideal${isDemonstration ? '. Demonstration midpoint, not a measurement.' : ''}',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaler = MediaQuery.textScalerOf(context);
            Size measure(String text, TextStyle style) {
              final painter = TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: Directionality.of(context),
                textScaler: scaler,
              )..layout();
              return painter.size;
            }

            final normal =
                constraints.maxWidth >= 354 &&
                measure(title, labelStyle).height <= 25 &&
                measure(title, labelStyle).width <= constraints.maxWidth - 90 &&
                measure(number, AppTextStyles.readingValue).width <= 157 &&
                measure(number, AppTextStyles.readingValue).height <= 32 &&
                measure(ideal, idealStyle).width <= 147;
            return Container(
              key: ValueKey('details-reading-${metric.name}'),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
              ),
              child: normal
                  ? SizedBox(
                      height: 102,
                      child: Stack(
                        children: [
                          Positioned(left: 15, top: 17, child: icon()),
                          Positioned(
                            left: 72,
                            top: 14,
                            right: 18,
                            child: Text(title, style: labelStyle),
                          ),
                          Positioned(
                            left: 72,
                            top: 38,
                            width: 157,
                            child: Text(
                              number,
                              key: ValueKey('details-value-${metric.name}'),
                              style: AppTextStyles.readingValue,
                            ),
                          ),
                          Positioned(
                            right: 15,
                            top: 43,
                            width: 147,
                            child: Text(
                              ideal,
                              textAlign: TextAlign.right,
                              style: idealStyle,
                            ),
                          ),
                          Positioned(
                            left: 72,
                            right: 18,
                            top: 72,
                            child: rail(),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(15, 14, 18, 10),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              icon(),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: labelStyle),
                                    const SizedBox(height: 4),
                                    Text(
                                      number,
                                      key: ValueKey(
                                        'details-value-${metric.name}',
                                      ),
                                      style: AppTextStyles.readingValue,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(ideal, style: idealStyle),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 57),
                            child: rail(),
                          ),
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}
