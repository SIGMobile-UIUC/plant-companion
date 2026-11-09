import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'persistence/database_connection.dart';
import 'persistence/sqlite_plant_repository.dart';
import 'screens/my_plants_screen.dart';
import 'state/plant_store.dart';
import 'theme/app_theme.dart';
import 'widgets/focus_visibility.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = PlantStore(
    persistence: SqlitePlantRepository(openAppDatabase()),
  );
  await store.initialized;
  await store.resume();
  runApp(
    ChangeNotifierProvider.value(
      value: store,
      child: const PlantCompanionApp(),
    ),
  );
}

class PlantCompanionApp extends StatefulWidget {
  const PlantCompanionApp({super.key});
  @override
  State<PlantCompanionApp> createState() => _PlantCompanionAppState();
}

class _PlantCompanionAppState extends State<PlantCompanionApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final store = context.read<PlantStore>();
    if (state == AppLifecycleState.resumed) {
      store.resume();
    } else {
      store.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SIGmobile Plant Companion',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    builder: (_, child) => FocusVisibility(child: child!),
    home: const MyPlantsScreen(),
  );
}
