import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'companion_header.dart';

/// Shared measured shell. Only content scrolls; progress follows its real extent.
class PlantFormShell extends StatefulWidget {
  const PlantFormShell({
    super.key,
    required this.title,
    required this.controller,
    required this.child,
    this.locked = false,
    this.onUserScroll,
  });
  final String title;
  final ScrollController controller;
  final Widget child;
  final bool locked;
  final VoidCallback? onUserScroll;
  @override
  State<PlantFormShell> createState() => _PlantFormShellState();
}

class _PlantFormShellState extends State<PlantFormShell> {
  double _progress = 0;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  void _update() {
    if (!mounted || !widget.controller.hasClients) return;
    final p = widget.controller.position;
    final progress = p.maxScrollExtent > 0
        ? (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0)
        : 0.0;
    if (_progress != progress) setState(() => _progress = progress);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(visualDensity: VisualDensity.standard),
    child: PopScope<void>(
      canPop: !widget.locked,
      child: Scaffold(
        body: CompanionSurface(
          child: Column(
            children: [
              CompanionHeader(
                variant: CompanionHeaderVariant.form,
                title: widget.title,
                leading: SpriteAction(
                  key: const Key('form-back'),
                  label: 'Back',
                  asset: 'actions/back.png',
                  onPressed: widget.locked
                      ? null
                      : () => Navigator.of(context).maybePop(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 23, 24, 17),
                child: Semantics(
                  label: 'Form scroll progress',
                  value: '${(_progress * 100).round()}%',
                  child: LayoutBuilder(
                    builder: (context, c) => Container(
                      key: const Key('form-progress'),
                      height: 7,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCADABC),
                        borderRadius: BorderRadius.circular(3.5),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: math.max(7, c.maxWidth * _progress),
                        height: 7,
                        decoration: BoxDecoration(
                          color: const Color(0xFF307D49),
                          borderRadius: BorderRadius.circular(3.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: NotificationListener<Notification>(
                    onNotification: (notification) {
                      if (notification is UserScrollNotification) {
                        widget.onUserScroll?.call();
                      }
                      if (notification is ScrollMetricsNotification) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _update(),
                        );
                      }
                      return false;
                    },
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        key: const Key('plant-form-scroll'),
                        controller: widget.controller,
                        padding: const EdgeInsets.fromLTRB(23, 17, 23, 52),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
