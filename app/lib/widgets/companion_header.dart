import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'focus_visibility.dart';

const companionAssets = 'assets/plant_companion/';
const headerActionRight = 17.0;
double headerActionTop(BuildContext context) =>
    MediaQuery.paddingOf(context).top + 2;

/// Measured artwork slots with native keyboard and focus behavior.
class SpriteAction extends StatelessWidget {
  const SpriteAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.asset,
    this.child,
    this.size = 50,
    this.artSize,
    this.focusNode,
    this.autofocus = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final String? asset;
  final Widget? child;
  final double size;
  final Size? artSize;
  final FocusNode? focusNode;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: label,
      enabled: onPressed != null,
      child: TextButton(
        focusNode: focusNode,
        autofocus: autofocus,
        onPressed: onPressed,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: WidgetStatePropertyAll(Size.square(size)),
          maximumSize: WidgetStatePropertyAll(Size.square(size)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? BorderSide(
                    color: AppColors.forest.withValues(
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
          child:
              child ??
              Image.asset(
                '$companionAssets$asset',
                width: artSize?.width ?? size,
                height: artSize?.height ?? size,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
              ),
        ),
      ),
    ),
  );
}

enum CompanionHeaderVariant { home, details, form }

class CompanionHeader extends StatelessWidget {
  const CompanionHeader({
    super.key,
    required this.leading,
    this.trailing,
    this.variant = CompanionHeaderVariant.home,
    this.title,
  });
  final Widget leading;
  final Widget? trailing;
  final CompanionHeaderVariant variant;
  final String? title;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.card,
    child: SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: variant == CompanionHeaderVariant.details ? 63 : 62,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned(
                    left: 18,
                    top: headerActionTop(context),
                    child: leading,
                  ),
                  Positioned(
                    right: headerActionRight,
                    top: headerActionTop(context),
                    child: trailing ?? const SizedBox.square(dimension: 50),
                  ),
                  if (variant == CompanionHeaderVariant.form)
                    Positioned(
                      left: 90,
                      right: 18,
                      top: 11,
                      child: Text(
                        title ?? '',
                        style: AppTextStyles.heading.copyWith(fontSize: 28),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    Positioned(
                      top: variant == CompanionHeaderVariant.details ? 4 : 12,
                      left:
                          (constraints.maxWidth -
                              math.min(
                                variant == CompanionHeaderVariant.details
                                    ? 185
                                    : 250,
                                constraints.maxWidth - 166,
                              )) /
                          2,
                      child: Image.asset(
                        '$companionAssets${variant == CompanionHeaderVariant.details ? 'branding/companion_wordmark.png' : 'branding/plant_companion_full.png'}',
                        width: math.min(
                          variant == CompanionHeaderVariant.details ? 185 : 250,
                          constraints.maxWidth - 166,
                        ),
                        height: variant == CompanionHeaderVariant.details
                            ? 51
                            : 42,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                        semanticLabel: variant == CompanionHeaderVariant.details
                            ? 'Companion'
                            : 'Plant Companion',
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 3,
            width: double.infinity,
            child: ColoredBox(
              color: variant == CompanionHeaderVariant.details
                  ? const Color(0xFFD4DEBD)
                  : const Color(0xFFD3DEBF),
            ),
          ),
          if (variant == CompanionHeaderVariant.details)
            const SizedBox(height: 2),
        ],
      ),
    ),
  );
}

class CompanionSurface extends StatelessWidget {
  const CompanionSurface({
    super.key,
    required this.child,
    this.darkStatusIcons = true,
  });
  final Widget child;
  final bool darkStatusIcons;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: darkStatusIcons
            ? Brightness.dark
            : Brightness.light,
        statusBarBrightness: darkStatusIcons
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: AppColors.ink,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}
