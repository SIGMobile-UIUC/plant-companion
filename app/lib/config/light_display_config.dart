/// Shared display/local-simulation policy; never changes saved values or health.
abstract final class LightDisplayConfig {
  static const scalePolicyVersion = 5;
  static const maximumIdealLightFraction = .30;
  static const minimumLux = 0.0;
  static const preferredIdealMinimum = .25;
  static const preferredIdealMaximum = .75;

  // Two significant digits make ordinary maxima readable (e.g. 1500 lux).
  // Only candidates inside the valid interval may be rounded.
  static const maximumSignificantDigits = 2;
  static const stableHashSeed = 5381;
  static const stableHashMultiplier = 33;
  static const stableHashMask = 0x7fffffff;
  static const compactThresholdLux = 10000.0;
  static const luxPerCompactUnit = 1000.0;
  static const compactSuffix = 'k';

  /// Nearest whole thousand; positive half-thousands round upward.
  static int roundCompact(double lux) => (lux / luxPerCompactUnit).round();

  static String number(double lux, {bool compact = true}) {
    if (!compact) {
      return lux == lux.truncateToDouble()
          ? lux.toStringAsFixed(0)
          : lux.toString();
    }
    if (lux >= compactThresholdLux) return '${roundCompact(lux)}$compactSuffix';
    return lux.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  }
}
