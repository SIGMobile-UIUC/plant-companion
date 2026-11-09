import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/add_plant_screen.dart';
import '../screens/plant_details_screen.dart';
import '../screens/edit_plant_screen.dart';
import '../state/plant_store.dart';

enum PlantRouteOrigin { home, selection, details }

enum PlantDestination { add, details, edit }

class PlantRouteIntent {
  const PlantRouteIntent(
    this.destination,
    this.origin, {
    this.plantId,
    this.expandDevice = false,
  });
  final PlantDestination destination;
  final PlantRouteOrigin origin;
  final String? plantId;
  final bool expandDevice;
}

/// Explicit slide avoids Material's platform-dependent web center expansion.
class PlantPageRoute<T> extends PageRouteBuilder<T> {
  PlantPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondary) => builder(context),
        transitionsBuilder: (context, animation, secondary, child) =>
            MediaQuery.disableAnimationsOf(context)
            ? child
            : SlideTransition(
                position:
                    Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                        .chain(CurveTween(curve: Curves.easeInOutCubic))
                        .animate(animation),
                child: child,
              ),
      );
}

Future<void> openPlantRoute(
  BuildContext context,
  PlantRouteIntent intent,
) async {
  if (intent.plantId != null &&
      context.read<PlantStore>().findPlant(intent.plantId!) == null) {
    return;
  }
  await Navigator.of(context).push(
    PlantPageRoute<void>(
      settings: RouteSettings(
        name: intent.destination == PlantDestination.add
            ? '/plants/add'
            : '/plants/${intent.plantId}/${intent.destination.name}',
        arguments: intent,
      ),
      builder: (_) => switch (intent.destination) {
        PlantDestination.add => const AddPlantScreen(),
        PlantDestination.details => PlantDetailsScreen(
          plantId: intent.plantId!,
        ),
        PlantDestination.edit => EditPlantScreen(
          plantId: intent.plantId!,
          saveReturnsHome: intent.origin == PlantRouteOrigin.selection,
          expandDevice: intent.expandDevice,
        ),
      },
    ),
  );
}
