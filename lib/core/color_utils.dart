import 'package:flutter/material.dart';
import 'constants.dart';

class ColorUtils {
  const ColorUtils._();

  /// Safely parses a `#RRGGBB`, `RRGGBB`, `#RGB`, `#AARRGGBB`, or `0xAARRGGBB`
  /// color string, returning [fallback] instead of throwing on invalid input.
  static Color parseHex(
    String? hex, {
    Color fallback = AppColors.workBlue,
  }) {
    if (hex == null) return fallback;
    var normalized = hex.trim();
    if (normalized.isEmpty) return fallback;

    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    } else if (normalized.startsWith('0x') || normalized.startsWith('0X')) {
      normalized = normalized.substring(2);
    }

    if (normalized.length == 6) {
      normalized = 'FF$normalized';
    } else if (normalized.length == 3) {
      final r = normalized[0];
      final g = normalized[1];
      final b = normalized[2];
      normalized = 'FF$r$r$g$g$b$b';
    } else if (normalized.length != 8) {
      return fallback;
    }

    final parsed = int.tryParse(normalized, radix: 16);
    return parsed != null ? Color(parsed) : fallback;
  }
}
