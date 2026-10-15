import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/my_plants_screen.dart';
import 'state/plant_store.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => PlantStore(),
      child: const PlantCompanionApp(),
    ),
  );
}

class PlantCompanionApp extends StatelessWidget {
  const PlantCompanionApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SIGmobile Plant Companion',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: const MyPlantsScreen(),
  );
}
