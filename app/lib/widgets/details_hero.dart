import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/plant_name_config.dart';
import '../models/device.dart';
import '../models/plant.dart';
import '../services/plant_condition_calculator.dart';
import '../theme/app_theme.dart';
import '../utils/compact_sync_time.dart';
import 'companion_header.dart';
import 'plant_portrait.dart';

const _detailName = TextStyle(
  fontFamily: 'Pixelify Sans',
  fontWeight: FontWeight.w700,
  fontSize: 25,
  color: Color(0xFF1C432F),
);
const _detailSpecies = TextStyle(
  fontFamily: 'Inter',
  fontSize: 14,
  color: Color(0xFF647769),
);

class DetailsHero extends StatelessWidget {
  const DetailsHero({
    super.key,
    required this.plant,
    required this.device,
    required this.now,
    this.onEdit,
  });
  final Plant plant;
  final Device? device;
  final DateTime now;
  final VoidCallback? onEdit;

  Widget _portrait(double width) => PlantPortrait(
    avatar: plant.avatar,
    appearance: PlantAppearance(plant, detail: true),
    detail: true,
    width: width,
  );

  Widget _status() => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          key: const Key('details-connection-dot'),
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: device?.isConnected == true
                ? const Color(0xFF2DA24B)
                : AppColors.terracotta,
            shape: BoxShape.circle,
          ),
        ),
      ),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          device?.isConnected == true ? 'Connected' : 'Disconnected',
          style: TextStyle(
            fontFamily: 'Pixelify Sans',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: device?.isConnected == true
                ? const Color(0xFF20633A)
                : AppColors.terracotta,
          ),
        ),
      ),
    ],
  );

  Widget _name() => LayoutBuilder(
    builder: (context, constraints) {
      final displayName = PlantNameConfig.detailsName(
        plant.nickname,
        plant.fullName,
      );
      final text = TextPainter(
        text: TextSpan(text: displayName, style: _detailName),
        maxLines: PlantNameConfig.fullNameMaxDisplayLines,
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout(maxWidth: math.max(1, constraints.maxWidth - 82));
      final height = math.max(51.0, text.height + 16);
      text.dispose();
      return Container(
        key: const ValueKey('details-name-card'),
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF4E9CA),
          borderRadius: BorderRadius.circular(17),
        ),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE6D8AD)),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 18,
              right: 64,
              top: 8,
              child: Text(
                displayName,
                key: const Key('details-nickname'),
                style: _detailName,
                maxLines: PlantNameConfig.fullNameMaxDisplayLines,
                overflow: TextOverflow.ellipsis,
                semanticsLabel: plant.fullName?.trim().isNotEmpty == true
                    ? plant.fullName
                    : plant.nickname,
              ),
            ),
            Positioned(
              right: 8,
              top: (height - 48) / 2,
              child: SpriteAction(
                key: ValueKey('details-edit-${plant.id}'),
                label: 'Edit ${plant.nickname}',
                asset: 'actions/edit.png',
                size: 48,
                artSize: const Size(27, 27),
                onPressed: onEdit,
              ),
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final scaler = MediaQuery.textScalerOf(context);
      final timestamp = ReadingPresentation(plant).timestamp;
      final sync = timestamp == null
          ? null
          : Text(
              'Synced ${compactSyncTime(timestamp, now)}',
              key: const Key('details-sync'),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: Color(0xFF698072),
              ),
            );
      final species = Text(
        plant.speciesName,
        key: const Key('details-species'),
        style: _detailSpecies,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        semanticsLabel: plant.speciesName,
      );
      final speciesMeasure = TextPainter(
        text: TextSpan(text: plant.speciesName, style: _detailSpecies),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 3,
      )..layout(maxWidth: math.max(1, width - 54));
      final reference = width >= 354 && scaler.scale(1) <= 1.15;
      return Container(
        key: const Key('details-hero'),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(22),
        ),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEE5CF)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: reference
            ? SizedBox(
                height: math.max(421, 378 + speciesMeasure.height + 26),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: (width - 212.8) / 2,
                      top: 10,
                      child: _portrait(212.8),
                    ),
                    Positioned(
                      left: 27,
                      top: 10,
                      width: width - 54,
                      child: _status(),
                    ),
                    if (sync != null)
                      Positioned(
                        left: 27,
                        top: 38,
                        width: width - 54,
                        child: sync,
                      ),
                    Positioned(left: 41, right: 41, top: 327, child: _name()),
                    Positioned(left: 27, right: 27, top: 378, child: species),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                child: Column(
                  children: [
                    Align(alignment: Alignment.centerLeft, child: _status()),
                    if (sync != null) ...[
                      const SizedBox(height: 7),
                      Align(alignment: Alignment.centerLeft, child: sync),
                    ],
                    const SizedBox(height: 12),
                    // Reserve the bubble's full painted extent, not just the nominal panel.
                    SizedBox(
                      width: math.min(261.4, width - 36),
                      height: math.min(261.4, width - 36) * 295.4 / 261.4,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _portrait(
                          math.min(261.4, width - 36) * 212.8 / 261.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _name(), const SizedBox(height: 8), species,
                  ],
                ),
              ),
      );
    },
  );
}
