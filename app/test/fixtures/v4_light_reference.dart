// Frozen pre-correction v4 reference. Test-only; never used by production.
import 'dart:convert';
import 'dart:typed_data';
import 'package:plant_companion/config/light_display_config.dart';
import 'package:plant_companion/models/plant_profile.dart';

double originalV4LightMaximum(String plantId, TargetRange range) {
  if (plantId.isEmpty || range.minimum < LightDisplayConfig.minimumLux) {
    throw ArgumentError(
      'Light scaling needs a plant ID and nonnegative range.',
    );
  }
  final lower = range.maximum / LightDisplayConfig.preferredIdealMaximum;
  final upper = range.minimum / LightDisplayConfig.preferredIdealMinimum;
  if (lower >= upper) return lower; // Empty or single-value feasible interval.

  // Canonical IEEE-754 bytes avoid VM/web double-to-string differences. The
  // 31-bit polynomial's intermediates stay below 2^53 on both Dart VM and JS.
  final bounds = ByteData(16)
    ..setFloat64(0, range.minimum, Endian.big)
    ..setFloat64(8, range.maximum, Endian.big);
  var hash = LightDisplayConfig.stableHashSeed;
  for (final byte in [
    ...utf8.encode(plantId),
    0,
    ...bounds.buffer.asUint8List(),
  ]) {
    hash =
        (hash * LightDisplayConfig.stableHashMultiplier + byte) &
        LightDisplayConfig.stableHashMask;
  }

  // Use decimal steps without logarithms near powers of ten. At most ~90
  // two-significant-digit candidates lie in any valid positioning interval.
  var step = 1.0;
  while (step * 10 <= upper) {
    step *= 10;
  }
  while (step > upper) {
    step /= 10;
  }
  for (
    var digit = 1;
    digit < LightDisplayConfig.maximumSignificantDigits;
    digit++
  ) {
    step /= 10;
  }
  if (step > 0) {
    var first = (lower / step).ceil();
    var last = (upper / step).floor();
    // Floating multiplication must not round an endpoint outside the interval.
    if (first * step < lower) first++;
    if (last * step > upper) last--;
    if (first <= last) return (first + hash % (last - first + 1)) * step;
  }
  final unit = hash / (LightDisplayConfig.stableHashMask + 1);
  return (lower + (upper - lower) * unit).clamp(lower, upper);
}
