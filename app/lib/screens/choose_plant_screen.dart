import 'package:flutter/material.dart';
import '../navigation/plant_navigation.dart';
import '../widgets/companion_header.dart';
import '../widgets/companion_plant_list.dart';

class ChoosePlantScreen extends StatelessWidget {
  const ChoosePlantScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: CompanionSurface(
      child: Column(
        children: [
          CompanionHeader(
            leading: SpriteAction(
              key: const Key('selection-back'),
              label: 'Back',
              asset: 'actions/back.png',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(25, 27, 25, 21),
            child: Text(
              'CHOOSE A PLANT TO EDIT',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pixelify Sans',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: Color(0xFF265E3B),
              ),
            ),
          ),
          Expanded(
            child: CompanionPlantList(
              edit: true,
              onAction: (id) => openPlantRoute(
                context,
                PlantRouteIntent(
                  PlantDestination.edit,
                  PlantRouteOrigin.selection,
                  plantId: id,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
