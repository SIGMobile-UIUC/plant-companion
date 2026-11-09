/// Shared display, local-simulation and newly submitted ideal-care envelope.
/// Historical sensor packets/profiles retain their broader original domain.
abstract final class TemperatureDisplayConfig {
  static const minimumFahrenheit = -40.0;
  static const maximumFahrenheit = 120.0;
  static const minimumCelsius = (minimumFahrenheit - 32) * 5 / 9;
  static const maximumCelsius = (maximumFahrenheit - 32) * 5 / 9;
  static const rangeError = 'Temperature must be between −40°F and 120°F.';
  // Only canonical conversion noise; raw Fahrenheit input is checked strictly.
  static const canonicalTolerance = 1e-10;
}
