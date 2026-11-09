import 'package:flutter_test/flutter_test.dart';
import 'package:plant_companion/models/plant_avatar_id.dart';
import 'package:plant_companion/models/portrait_geometry.dart';

void main() {
  test(
    'all original plant pot centers register within half a pixel of face center',
    () {
      for (final avatar in PlantAvatarId.values) {
        final geometry = PortraitGeometry(avatar);
        expect(
          (geometry.face.center.dx - geometry.potCenter.dx).abs(),
          lessThan(.5),
        );
        expect(
          (geometry.face.center.dy - geometry.potCenter.dy).abs(),
          lessThan(.5),
        );
        final enlarged = PortraitGeometry(avatar, scale: 2);
        expect(enlarged.face.center.dx, geometry.face.center.dx * 2);
        expect(enlarged.face.center.dy, geometry.face.center.dy * 2);
        expect(
          enlarged.paintedPlant.width / enlarged.paintedPlant.height,
          closeTo(geometry.nativeSize.width / geometry.nativeSize.height, 1e-9),
        );
      }
    },
  );
  test(
    'detail bubble retains latest farther-right placement and intentional overflow',
    () {
      final geometry = PortraitGeometry(PlantAvatarId.pothos, detail: true);
      expect(geometry.bubble.left, 174.6);
      expect(geometry.bubble.right, greaterThan(geometry.size.width));
      expect(
        geometry.sensorIcon.center.dy,
        lessThan(geometry.bubble.center.dy),
      );
    },
  );
}
