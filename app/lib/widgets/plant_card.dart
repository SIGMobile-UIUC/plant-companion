import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/device.dart';
import '../config/plant_name_config.dart';
import '../models/plant.dart';
import '../models/sensor_reading.dart';
import '../services/plant_condition_calculator.dart';
import '../theme/app_theme.dart';
import '../utils/compact_sync_time.dart';
import 'companion_header.dart';
import 'plant_portrait.dart';
import 'sensor_rail.dart';

const _speciesStyle = TextStyle(
  fontFamily: 'Inter',
  fontSize: 11,
  color: AppColors.muted,
);
const _labelStyle = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w500,
  fontSize: 9,
  color: Color(0xFF193B2B),
);
const _valueStyle = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.w500,
  fontSize: 11,
  color: AppColors.forest,
);
const _syncStyle = TextStyle(
  fontFamily: 'Inter',
  fontSize: 8,
  color: Color(0xFF7D8578),
);

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({
    super.key,
    required this.connected,
    this.assigned = true,
  });
  final bool connected;
  final bool assigned;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: (connected ? const Color(0xFFEBF3E7) : const Color(0xFFF8EEEB))
          .withValues(alpha: .85),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected
                ? const Color(0xFF2F7543)
                : const Color(0xFFB7483E),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            !assigned
                ? 'No device'
                : connected
                ? 'Connected'
                : 'Disconnected',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: connected
                  ? const Color(0xFF2F7543)
                  : const Color(0xFFB7483E),
            ),
          ),
        ),
      ],
    ),
  );
}

class PlantCard extends StatelessWidget {
  const PlantCard({
    super.key,
    required this.plant,
    required this.device,
    required this.now,
    required this.onAction,
    this.edit = false,
    this.preview = false,
    this.appearanceOverride,
  });
  final Plant plant;
  final Device? device;
  final DateTime now;
  final VoidCallback? onAction;
  final bool edit, preview;
  final PlantAppearance? appearanceOverride;

  static bool usesCompactLayout(double width, TextScaler scaler) =>
      width >= 324 && scaler.scale(22) <= 24.2 + 1e-8;

  @override
  Widget build(BuildContext context) {
    final presentation = ReadingPresentation(plant);
    final appearance = appearanceOverride ?? PlantAppearance(plant);
    final displayName = PlantNameConfig.truncate(
      plant.nickname,
      PlantNameConfig.nicknameDisplayTruncationLength,
    );
    final scaler = MediaQuery.textScalerOf(context);
    Widget portrait(double width) => PlantPortrait(
      avatar: plant.avatar,
      appearance: appearance,
      width: width,
    );
    Widget title() => Text(
      displayName,
      key: const ValueKey('card-title'),
      style: AppTextStyles.plantName.copyWith(height: 1),
      maxLines: PlantNameConfig.nicknameMaxDisplayLines,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: plant.nickname,
    );
    Widget species({int lines = 1}) => Text(
      plant.speciesName,
      key: const ValueKey('card-species'),
      style: _speciesStyle.copyWith(height: 1.3),
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: plant.speciesName,
    );
    Widget badge() => ConnectionBadge(
      key: ValueKey('connection-${plant.id}'),
      connected: device?.isConnected ?? false,
      assigned: device != null,
    );
    Widget sync() => !preview && presentation.timestamp != null
        ? Text(
            'Last synced\n${compactSyncTime(presentation.timestamp!, now)}',
            key: ValueKey('sync-${plant.id}'),
            style: _syncStyle.copyWith(height: 1.2),
            textAlign: TextAlign.right,
            maxLines: 2,
          )
        : const SizedBox.shrink();
    final action = SpriteAction(
      key: ValueKey('${edit ? 'edit' : 'details'}-${plant.id}'),
      label: '${edit ? 'Edit' : 'View details for'} ${plant.nickname}',
      onPressed: preview ? null : onAction,
      size: 48,
      child: SizedBox.square(
        dimension: 48,
        child: Stack(
          children: [
            if (edit)
              Positioned(
                left: 11,
                top: 8,
                width: 28,
                height: 28,
                child: Image.asset(
                  '${companionAssets}actions/edit.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                ),
              )
            else
              const Positioned(
                left: 22,
                top: 11,
                width: 17,
                height: 31,
                child: Text(
                  '›',
                  textScaler: TextScaler.noScaling,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Pixelify Sans',
                    fontWeight: FontWeight.w700,
                    fontSize: 26,
                    height: 1,
                    color: AppColors.forest,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    Widget sensorSummary(SensorMetric m, Widget child) => Semantics(
      label:
          '${m.label}, ${presentation.values[m] == null ? 'Reading unavailable' : metricValue(m, presentation.values[m], compactLight: false)}. Ideal ${metricRange(m, plant.profile.rangeFor(m), compactLight: false)}.${presentation.isDemonstration ? ' Demonstration midpoint, not a measurement.' : ''}',
      child: ExcludeSemantics(child: child),
    );
    Widget labels(
      SensorMetric m,
      double valueWidth, {
      bool compact = true,
    }) => sensorSummary(
      m,
      Row(
        children: [
          Expanded(
            child: Text(
              '${metricTitle(m)} · ${metricRange(m, plant.profile.rangeFor(m), includeChartNote: false).replaceAll(' – ', '–')}',
              key: ValueKey('card-label-${m.name}'),
              style: compact
                  ? _labelStyle
                  : _labelStyle.copyWith(fontSize: 11, height: 1.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: valueWidth,
            child: Text(
              metricValue(m, presentation.values[m]),
              key: ValueKey('card-value-${m.name}'),
              style: _valueStyle.copyWith(height: 1.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
    Widget icon(SensorMetric m) => ExcludeSemantics(
      child: Image.asset(
        '$companionAssets${sensorAsset(m)}',
        width: 20,
        height: 22,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
      ),
    );
    Widget rail(SensorMetric m) => SensorRail(
      plantId: plant.id,
      metric: m,
      range: plant.profile.rangeFor(m),
      current: presentation.values[m],
    );
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        // One policy for every plant. No text, status or readings are measured.
        // 360px phones provide 324px cards after the shared 18px side margins.
        final compact = usesCompactLayout(width, scaler);
        final compactFactor = scaler.scale(22) / 22;
        final compactTitleHeight = 44 * compactFactor;
        final compactBadgeTop = 8 + compactTitleHeight;
        final shift = math.min(0.0, width - 394);
        final portraitWidth = math.max(104.0, math.min(136.0, width * .37));
        final titleHeight = scaler.scale(22) * 2;
        // Font rasterization can round two rendered lines slightly above the
        // nominal slot. Borrow that fraction from the gap, never other slots.
        final headerMetrics = TextPainter(
          text: TextSpan(
            text: 'Ag\nAg',
            style: AppTextStyles.plantName.copyWith(height: 1),
          ),
          textScaler: scaler,
          textDirection: Directionality.of(context),
        )..layout();
        final renderedTwoLines = headerMetrics.height;
        headerMetrics.dispose();
        final compactGap = math.max(
          0.0,
          math.min(
            4 * compactFactor,
            compactTitleHeight + 4 * compactFactor - renderedTwoLines,
          ),
        );
        final stackedGap = math.max(
          0.0,
          math.min(3.0, titleHeight + 3 - renderedTwoLines),
        );
        final speciesHeight = scaler.scale(11) * 2.6;
        final badgeHeight = math.max(15.0, scaler.scale(8) * 1.4 + 4);
        final syncHeight = math.max(20.0, scaler.scale(8) * 2.5);
        final rowTextHeight = scaler.scale(11) * 1.4;
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(23),
            ),
            child: compact
                ? SizedBox(
                    key: const ValueKey('card-compact'),
                    height: 224,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 10,
                          top: (224 - (152 + shift) * 206 / 152) / 2,
                          child: portrait(152 + shift),
                        ),
                        // Only this text group's internal height follows nickname
                        // wrapping. The card, status, sync and rails stay fixed.
                        Positioned(
                          left: 173 + shift,
                          top: 12,
                          // Keep both title lines left of the fixed badge,
                          // including fonts whose glyphs extend past line height.
                          width: width - 267 - shift,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(width: double.infinity, child: title()),
                              SizedBox(height: compactGap),
                              SizedBox(
                                width: width - 267 - shift,
                                height: 16 * compactFactor,
                                child: species(),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 8,
                          top: compactBadgeTop,
                          width: 78,
                          height: 15 * compactFactor,
                          child: badge(),
                        ),
                        Positioned(
                          right: 8,
                          top: 8 + 62 * compactFactor,
                          width: 107,
                          height: 20 * compactFactor,
                          child: sync(),
                        ),
                        for (var i = 0; i < cardMetrics.length; i++) ...[
                          Positioned(
                            left: 165 + shift,
                            top: 104 + 30.0 * i,
                            width: 20,
                            height: 22,
                            child: icon(cardMetrics[i]),
                          ),
                          Positioned(
                            left: 191 + shift,
                            top: 101 + 30.0 * i,
                            width: width - 203 - shift,
                            height: 17,
                            child: labels(cardMetrics[i], 65),
                          ),
                          Positioned(
                            left: 192 + shift,
                            top: 112 + 30.0 * i,
                            width: width - 204 - shift,
                            height: 21,
                            child: rail(cardMetrics[i]),
                          ),
                        ],
                        Positioned(right: 0, top: 0, child: action),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: portraitWidth * 206 / 152,
                          child: Stack(
                            children: [
                              portrait(portraitWidth),
                              Positioned(right: 0, top: 0, child: action),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: titleHeight + 3 + speciesHeight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: double.infinity, child: title()),
                              SizedBox(height: stackedGap),
                              SizedBox(
                                width: double.infinity,
                                height: speciesHeight,
                                child: species(lines: 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: badgeHeight,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: math.max(78, scaler.scale(8) * 9 + 22),
                              height: badgeHeight,
                              child: badge(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          height: syncHeight,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: sync(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final m in cardMetrics)
                          SizedBox(
                            height: rowTextHeight + 21 + 5,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                icon(m),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        height: rowTextHeight,
                                        child: labels(
                                          m,
                                          math.max(65, scaler.scale(11) * 6),
                                          compact: false,
                                        ),
                                      ),
                                      rail(m),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}
