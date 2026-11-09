import 'package:flutter/widgets.dart';
import 'plant_form_screen.dart';

class EditPlantScreen extends StatelessWidget {
  const EditPlantScreen({
    super.key,
    required this.plantId,
    this.saveReturnsHome = false,
    this.expandDevice = false,
  });
  final String plantId;
  final bool saveReturnsHome, expandDevice;
  @override
  Widget build(BuildContext context) => PlantFormScreen(
    plantId: plantId,
    saveReturnsHome: saveReturnsHome,
    expandDevice: expandDevice,
  );
}
