import 'package:plant_companion/models/plant_avatar_id.dart';
// Pure test/review fixtures only; production obtains these fields from SQLite.
import 'package:plant_companion/models/device.dart';
import 'package:plant_companion/models/plant_profile.dart';
import 'package:plant_companion/services/plant_simulation.dart';

final simulationContext = PlantSimulationContext(
  plantId: 'plant-1',
  lightRange: TargetRange(400, 850),
  idealRanges: PlantAvatarId.pothos.hints,
);
PlantSimulationContext simulationFor(DeviceReadingContext c) =>
    PlantSimulationContext(
      plantId: c.plantId,
      lightRange: c.lightRange,
      idealRanges: c.idealRanges,
    );
