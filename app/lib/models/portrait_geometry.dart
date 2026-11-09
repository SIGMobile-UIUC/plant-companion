import 'dart:math' as math;
import 'dart:ui';
import 'plant_avatar_id.dart';

/// Measured Figma composition slots, not a new rendered widget.
/// Each PNG is contained in its slot; never stretch artwork to fill it.
class PortraitGeometry {
  PortraitGeometry(this.avatar, {this.detail = false, this.scale = 1}) {
    if (!scale.isFinite || scale <= 0) throw ArgumentError.value(scale);
  }
  final PlantAvatarId avatar;
  final bool detail;
  final double scale;
  double get _factor => scale * (detail ? 1.4 : 1);
  Size get size => Size(152 * _factor, 206 * _factor);
  Rect get plant {
    final point = switch (avatar) {
      PlantAvatarId.pothos => const Offset(6, 19),
      PlantAvatarId.snakePlant => const Offset(1, 13),
      PlantAvatarId.peaceLily => const Offset(2, 12),
    };
    return Rect.fromLTWH(
      point.dx * _factor,
      point.dy * _factor,
      150 * _factor,
      192 * _factor,
    );
  }

  Rect get face =>
      Rect.fromLTWH(47 * _factor, 168 * _factor, 58 * _factor, 24 * _factor);
  Rect get bubble => detail
      ? Rect.fromLTWH(174.6 * scale, 14 * scale, 86.8 * scale, 103.6 * scale)
      : Rect.fromLTWH(79 * scale, 10 * scale, 62 * scale, 74 * scale);
  Rect get sensorIcon => detail
      ? Rect.fromLTWH(198.4 * scale, 33.6 * scale, 39.2 * scale, 40.6 * scale)
      : Rect.fromLTWH(96 * scale, 24 * scale, 28 * scale, 29 * scale);
  Rect get heartIcon => detail
      ? Rect.fromLTWH(198.4 * scale, 35 * scale, 39.2 * scale, 36.4 * scale)
      : Rect.fromLTWH(96 * scale, 25 * scale, 28 * scale, 26 * scale);

  /// Screens 9/10: 31×31 overlay at (94.5,22.5), relative to the icon.
  Rect get slashIcon => Rect.fromLTWH(
    sensorIcon.left - 1.5 * _factor,
    sensorIcon.top - 1.5 * _factor,
    31 * _factor,
    31 * _factor,
  );

  Size get nativeSize => switch (avatar) {
    PlantAvatarId.pothos => const Size(70, 85),
    PlantAvatarId.snakePlant => const Size(58, 92),
    PlantAvatarId.peaceLily => const Size(70, 86),
  };

  Rect get paintedPlant {
    final slot = plant;
    final factor = math.min(
      slot.width / nativeSize.width,
      slot.height / nativeSize.height,
    );
    final w = nativeSize.width * factor, h = nativeSize.height * factor;
    return Rect.fromLTWH(
      slot.left + (slot.width - w) / 2,
      slot.top + (slot.height - h) / 2,
      w,
      h,
    );
  }

  Offset get potCenter {
    final normalized = switch (avatar) {
      PlantAvatarId.pothos => const Offset(.466216227, .855555518),
      PlantAvatarId.snakePlant => const Offset(.5, .872222224),
      PlantAvatarId.peaceLily => const Offset(.493150687, .888888853),
    };
    final image = paintedPlant;
    return Offset(
      image.left + image.width * normalized.dx,
      image.top + image.height * normalized.dy,
    );
  }
}
