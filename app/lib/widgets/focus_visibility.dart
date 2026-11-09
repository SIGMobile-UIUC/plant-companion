import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One timer/animation for the active application, independent of logical focus.
/// Accessible-navigation/high-contrast modes retain a persistent focus cue.
class FocusVisibility extends StatefulWidget {
  const FocusVisibility({super.key, required this.child});
  final Widget child;
  static const delay = Duration(milliseconds: 700);
  static const fade = Duration(milliseconds: 180);

  static double opacityOf(BuildContext context) {
    if (MediaQuery.accessibleNavigationOf(context) ||
        MediaQuery.highContrastOf(context)) {
      return 1;
    }
    return context
            .dependOnInheritedWidgetOfExactType<_Visibility>()
            ?.notifier
            ?.value ??
        0;
  }

  static bool usingKeyboard(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_Visibility>()?.owner.keyboard ??
      false;

  @override
  State<FocusVisibility> createState() => _FocusVisibilityState();
}

class _FocusVisibilityState extends State<FocusVisibility>
    with SingleTickerProviderStateMixin {
  late final _opacity = AnimationController(
    vsync: this,
    duration: FocusVisibility.fade,
  );
  Timer? _timer;
  bool keyboard = false;
  bool _reduceMotion = false;
  static const navigation = [
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    keyboard = true;
    if (navigation.contains(event.logicalKey)) {
      _timer?.cancel();
      _opacity.value = 1;
      _timer = Timer(FocusVisibility.delay, () {
        if (_reduceMotion) {
          _opacity.value = 0;
        } else {
          _opacity.reverse();
        }
      });
    }
    return false; // Never consume traversal or activation.
  }

  void _pointer(PointerDownEvent event) {
    keyboard = false;
    _timer?.cancel();
    _opacity.value = 0;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Visibility(
    owner: this,
    notifier: _opacity,
    child: Listener(onPointerDown: _pointer, child: widget.child),
  );
}

class _Visibility extends InheritedNotifier<AnimationController> {
  const _Visibility({
    required this.owner,
    required super.notifier,
    required super.child,
  });
  final _FocusVisibilityState owner;
}
