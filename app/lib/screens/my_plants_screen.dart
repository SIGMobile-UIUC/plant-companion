import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../navigation/plant_navigation.dart';
import '../widgets/companion_header.dart';
import '../widgets/companion_plant_list.dart';
import '../widgets/companion_drawer.dart';
import '../widgets/focus_visibility.dart';
import 'choose_plant_screen.dart';
import '../widgets/plant_operation_notice.dart';

class MyPlantsScreen extends StatefulWidget {
  const MyPlantsScreen({super.key});
  @override
  State<MyPlantsScreen> createState() => _MyPlantsScreenState();
}

class _MyPlantsScreenState extends State<MyPlantsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  bool _drawerOpen = false;
  final _menuFocus = FocusNode(debugLabel: 'Home menu');
  void _showDrawer() {
    setState(() => _drawerOpen = true);
    _animation.forward();
  }

  Future<void> _closeDrawer({bool restoreFocus = true}) async {
    await _animation.reverse();
    if (mounted) {
      setState(() => _drawerOpen = false);
      if (restoreFocus && FocusVisibility.usingKeyboard(context)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _menuFocus.requestFocus();
        });
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _menuFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_drawerOpen,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _drawerOpen) _closeDrawer();
    },
    child: Scaffold(
      body: CompanionSurface(
        darkStatusIcons: !_drawerOpen,
        child: AnimatedBuilder(
          animation: _animation,
          child: Column(
            children: [
              CompanionHeader(
                leading: SpriteAction(
                  key: const Key('open-menu'),
                  label: 'Open menu',
                  focusNode: _menuFocus,
                  asset: 'actions/menu.png',
                  onPressed: _showDrawer,
                ),
                trailing: SpriteAction(
                  key: const Key('add-plant-button'),
                  label: 'Add Plant',
                  asset: 'actions/add_plant.png',
                  onPressed: () => openPlantRoute(
                    context,
                    const PlantRouteIntent(
                      PlantDestination.add,
                      PlantRouteOrigin.home,
                    ),
                  ),
                ),
              ),
              const PlantOperationNotice(),
              Expanded(
                child: CompanionPlantList(
                  onAction: (id) => openPlantRoute(
                    context,
                    PlantRouteIntent(
                      PlantDestination.details,
                      PlantRouteOrigin.home,
                      plantId: id,
                    ),
                  ),
                ),
              ),
            ],
          ),
          builder: (context, child) => Stack(
            children: [
              ExcludeSemantics(
                excluding: _drawerOpen,
                child: FocusScope(
                  canRequestFocus: !_drawerOpen,
                  child: IgnorePointer(
                    ignoring: _drawerOpen,
                    child: ImageFiltered(
                      enabled: _drawerOpen,
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: 4 * _animation.value,
                        sigmaY: 4 * _animation.value,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
              if (_drawerOpen)
                CompanionDrawer(
                  progress: Curves.easeOutCubic.transform(_animation.value),
                  onClose: _closeDrawer,
                  onEdit: () async {
                    await _closeDrawer(restoreFocus: false);
                    if (context.mounted) {
                      await Navigator.of(context).push(
                        PlantPageRoute<void>(
                          settings: const RouteSettings(
                            name: '/plants/choose-edit',
                          ),
                          builder: (_) => const ChoosePlantScreen(),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
