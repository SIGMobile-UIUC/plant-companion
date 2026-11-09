import 'package:flutter/widgets.dart' show Characters;

/// Product naming policy in grapheme clusters, not UTF-16 code units.
/// Null limits are deliberately unlimited. Storage and display limits are separate.
abstract final class PlantNameConfig {
  static const int? nicknameInputMaxLength = null;
  static const nicknameWarningThreshold = 10;
  static const int? nicknameDisplayTruncationLength =
      null; // Constrained by layout.
  static const nicknameMaxDisplayLines = 2;
  static const int? scientificNameInputMaxLength = null;
  static const scientificNameCompactDisplayLines = 1;
  static const scientificNameMaxDisplayLines = 2;
  static const fullNameInputMaxLength = 25;
  static const int? fullNameWarningThreshold = null;
  static const fullNameDisplayTruncationLength = 15;
  static const fullNameMaxDisplayLines = 1;
  static const ellipsis = '…';

  static int length(String value) => Characters(value).length;
  static bool warnsForNickname(String value) =>
      length(value) > nicknameWarningThreshold;
  static bool accepts(String value, int? maximum) =>
      maximum == null || length(value) <= maximum;
  static String truncate(String value, int? maximum) =>
      maximum == null || length(value) <= maximum
      ? value
      : '${Characters(value).take(maximum)}$ellipsis';

  static String detailsName(String nickname, String? fullName) {
    final full = fullName?.trim();
    return full == null || full.isEmpty
        ? nickname
        : truncate(full, fullNameDisplayTruncationLength);
  }
}
