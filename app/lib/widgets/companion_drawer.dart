import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'companion_header.dart';
import 'focus_visibility.dart';

class CompanionDrawer extends StatelessWidget {
  const CompanionDrawer({
    super.key,
    required this.progress,
    required this.onClose,
    required this.onEdit,
  });
  final double progress;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(322.0, constraints.maxWidth * 322 / 430);
      return FocusScope(
        autofocus: true,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Shortcuts(
            shortcuts: {
              LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    onClose();
                    return null;
                  },
                ),
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AbsorbPointer(
                      child: ColoredBox(
                        color: const Color(
                          0xFF0B291E,
                        ).withValues(alpha: .72 * progress),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -width * (1 - progress),
                    top: 0,
                    bottom: 0,
                    width: width,
                    child: ColoredBox(
                      color: const Color(0xFF092C25),
                      child: SafeArea(
                        right: false,
                        child: _DrawerContents(onEdit: onEdit),
                      ),
                    ),
                  ),
                  Positioned(
                    right: headerActionRight,
                    top: headerActionTop(context),
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(0),
                      child: SpriteAction(
                        key: const Key('close-menu'),
                        autofocus: true,
                        label: 'Close menu',
                        asset: 'actions/close_menu.png',
                        onPressed: onClose,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DrawerContents extends StatelessWidget {
  const _DrawerContents({required this.onEdit});
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const Key('drawer-scroll'),
    slivers: [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DrawerHeader(),
            const _DrawerRow(
              title: 'Notifications',
              helper: 'Manage alerts',
              asset: 'notifications',
            ),
            const SizedBox(height: 18),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _DrawerRow(
                title: 'Edit Plants',
                helper: 'Rename & customize',
                asset: 'edit',
                onPressed: onEdit,
              ),
            ),
            const SizedBox(height: 18),
            const _DrawerRow(
              title: 'Settings',
              helper: 'Preferences',
              asset: 'settings',
            ),
            const SizedBox(height: 18),
            const _DrawerRow(
              title: 'About',
              helper: 'App information',
              asset: 'about',
            ),
          ],
        ),
      ),
      // Fill the remaining height at the reference viewport; scroll naturally
      // when short screens or larger text make the content taller than the panel.
      const SliverFillRemaining(
        hasScrollBody: false,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.fromLTRB(26, 32, 26, 46),
            child: Text(
              'Plant Companion · MVP v0.1',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Color(0xFFAAC8B0),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) <= 1) {
      return SizedBox(
        height: 158,
        child: Stack(
          children: [
            Positioned(
              left: 26,
              right: 20,
              top: 43,
              child: Text('MENU', style: _pixel(27, const Color(0xFFF9EFD4))),
            ),
            const Positioned(
              left: 26,
              right: 16,
              top: 76,
              child: Text(
                'Plant Companion',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  color: Color(0xFFC1D8C2),
                ),
              ),
            ),
            const Positioned(
              left: 26,
              right: 26,
              top: 123,
              height: 1,
              child: ColoredBox(color: Color(0xFF3F6C58)),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 43, 26, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MENU', style: _pixel(27, const Color(0xFFF9EFD4))),
          const Text(
            'Plant Companion',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              color: Color(0xFFC1D8C2),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, thickness: 1, color: Color(0xFF3F6C58)),
        ],
      ),
    );
  }
}

TextStyle _pixel(double size, Color color) => TextStyle(
  fontFamily: 'Pixelify Sans',
  fontWeight: FontWeight.w700,
  fontSize: size,
  color: color,
);

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.title,
    required this.helper,
    required this.asset,
    this.onPressed,
  });
  final String title, helper, asset;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 17),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final exact =
            constraints.maxWidth >= 288 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1;
        final art = Image.asset(
          '${companionAssets}actions/$asset.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
        );
        final words = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _pixel(22, const Color(0xFFFFFAEB))),
            const SizedBox(height: 8),
            Text(
              helper,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Color(0xFFB8D5BF),
              ),
            ),
          ],
        );
        final arrow = Text(
          '›',
          textScaler: TextScaler.noScaling,
          style: _pixel(28, const Color(0xFFD8F0D8)),
        );
        final content = exact
            ? SizedBox(
                height: 93,
                child: Stack(
                  children: [
                    Positioned(
                      left: 10,
                      top: 20,
                      width: 52,
                      height: 53,
                      child: art,
                    ),
                    Positioned(
                      left: 75,
                      top: 20,
                      width: 182,
                      child: Text(
                        title,
                        style: _pixel(22, const Color(0xFFFFFAEB)),
                      ),
                    ),
                    Positioned(
                      left: 75,
                      top: 52,
                      width: 185,
                      child: Text(
                        helper,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Color(0xFFB8D5BF),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 252,
                      top: 27,
                      width: 20,
                      child: Text(
                        '›',
                        textScaler: TextScaler.noScaling,
                        style: _pixel(28, const Color(0xFFD8F0D8)),
                      ),
                    ),
                  ],
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 93),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 20, 12, 20),
                  child: MediaQuery.textScalerOf(context).scale(1) > 1.3
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                SizedBox(width: 44, height: 53, child: art),
                                const Spacer(),
                                arrow,
                              ],
                            ),
                            const SizedBox(height: 12),
                            words,
                          ],
                        )
                      : Row(
                          children: [
                            SizedBox(width: 44, height: 53, child: art),
                            const SizedBox(width: 13),
                            Expanded(child: words),
                            const SizedBox(width: 8),
                            arrow,
                          ],
                        ),
                ),
              );
        final surface = DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF244D3B),
            borderRadius: BorderRadius.circular(16),
          ),
          child: content,
        );
        if (onPressed == null) {
          return Semantics(
            container: true,
            label: '$title. $helper',
            button: true,
            enabled: false,
            child: ExcludeSemantics(child: surface),
          );
        }
        return MergeSemantics(
          child: Semantics(
            label: '$title. $helper',
            child: TextButton(
              key: const Key('edit-plants'),
              onPressed: onPressed,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                minimumSize: const WidgetStatePropertyAll(Size.zero),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                side: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? BorderSide(
                          color: const Color(0xFFD8F0D8).withValues(
                            alpha: .65 * FocusVisibility.opacityOf(context),
                          ),
                        )
                      : BorderSide.none,
                ),
                overlayColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? Colors.transparent
                      : null,
                ),
              ),
              child: ExcludeSemantics(
                child: DefaultTextStyle(
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
                  child: surface,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
