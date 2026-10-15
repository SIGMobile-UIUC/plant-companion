import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'plant_condition.dart';

/// Replace the icon composition here with an Image.asset when pixel art is ready.
class PlantAvatar extends StatelessWidget {
  const PlantAvatar({super.key, required this.condition, this.size = 88});
  final PlantCondition condition;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Plant avatar placeholder: ${condition.label}',
    image: true,
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: condition.attention
                    ? const Color(0xFFF1E6DA)
                    : AppColors.sage,
                borderRadius: BorderRadius.circular(size * .28),
              ),
              child: Center(
                child: Icon(
                  Icons.spa,
                  color: AppColors.forest,
                  size: size * .6,
                ),
              ),
            ),
            Positioned(
              right: size * .06,
              bottom: size * .06,
              child: Container(
                padding: EdgeInsets.all(size * .055),
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  condition.icon,
                  size: size * .2,
                  color: condition.attention
                      ? AppColors.terracotta
                      : AppColors.forest,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
