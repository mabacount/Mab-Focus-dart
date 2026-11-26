import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';

class WindowBoundsHelper {
  const WindowBoundsHelper._();

  static const Rect fallbackDisplayBounds = Rect.fromLTWH(0, 0, 1280, 720);

  /// Converts a [Display] to its usable work-area bounds, falling back to
  /// [Offset.zero] / [Display.size] when [visiblePosition] or [visibleSize]
  /// is null or non-positive.
  static Rect displayVisibleRect(Display display) {
    final Offset origin = display.visiblePosition ?? Offset.zero;
    final Size? vis = display.visibleSize;
    final Size size = (vis != null && vis.width > 0 && vis.height > 0)
        ? vis
        : display.size;
    if (size.width <= 0 || size.height <= 0) {
      return Rect.fromLTWH(
        origin.dx,
        origin.dy,
        fallbackDisplayBounds.width,
        fallbackDisplayBounds.height,
      );
    }
    return Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
  }

  /// Selects the target display rect containing [windowBounds.center], or the
  /// display with largest intersection area, or [primaryVisibleBounds]/[displayVisibleBounds.first].
  static Rect selectTargetDisplayBounds({
    Rect? windowBounds,
    required List<Rect> displayVisibleBounds,
    Rect? primaryVisibleBounds,
  }) {
    final valid = displayVisibleBounds
        .where((r) => r.width > 0 && r.height > 0)
        .toList();
    final Rect fallback = (primaryVisibleBounds != null &&
            primaryVisibleBounds.width > 0 &&
            primaryVisibleBounds.height > 0)
        ? primaryVisibleBounds
        : (valid.isNotEmpty ? valid.first : fallbackDisplayBounds);

    if (valid.isEmpty || windowBounds == null) {
      return fallback;
    }

    final Offset center = windowBounds.center;
    for (final rect in valid) {
      if (rect.contains(center)) {
        return rect;
      }
    }

    Rect? bestIntersect;
    double bestArea = 0.0;
    for (final rect in valid) {
      final inter = windowBounds.intersect(rect);
      if (inter.width > 0 && inter.height > 0) {
        final area = inter.width * inter.height;
        if (area > bestArea) {
          bestArea = area;
          bestIntersect = rect;
        }
      }
    }
    return bestIntersect ?? fallback;
  }

  /// Clamps [desired] size (respecting [minSize] capped to display size) and
  /// position onto the selected target display's visible bounds.
  static Rect clampWindowBounds({
    required Rect desired,
    required List<Rect> displayVisibleBounds,
    required Size minSize,
  }) {
    final target = selectTargetDisplayBounds(
      windowBounds: desired,
      displayVisibleBounds: displayVisibleBounds,
    );

    final double safeMinW = math.min(math.max(0.0, minSize.width), target.width);
    final double safeMinH =
        math.min(math.max(0.0, minSize.height), target.height);

    final double rawW = desired.width.isFinite && desired.width > 0
        ? desired.width
        : safeMinW;
    final double rawH = desired.height.isFinite && desired.height > 0
        ? desired.height
        : safeMinH;

    final double clampedW = rawW.clamp(safeMinW, target.width);
    final double clampedH = rawH.clamp(safeMinH, target.height);

    final double maxLeft = math.max(target.left, target.right - clampedW);
    final double maxTop = math.max(target.top, target.bottom - clampedH);

    final double rawLeft = desired.left.isFinite ? desired.left : target.left;
    final double rawTop = desired.top.isFinite ? desired.top : target.top;

    final double clampedLeft = rawLeft.clamp(target.left, maxLeft);
    final double clampedTop = rawTop.clamp(target.top, maxTop);

    return Rect.fromLTWH(clampedLeft, clampedTop, clampedW, clampedH);
  }

  /// Centers [desiredSize] within [targetBounds] after clamping size to [minSize]
  /// and [targetBounds.size].
  static Rect clampAndCenterInBounds({
    required Size desiredSize,
    required Rect targetBounds,
    required Size minSize,
  }) {
    final sized = clampWindowBounds(
      desired: Rect.fromLTWH(
        targetBounds.left,
        targetBounds.top,
        desiredSize.width,
        desiredSize.height,
      ),
      displayVisibleBounds: [targetBounds],
      minSize: minSize,
    );
    final double left =
        targetBounds.left + (targetBounds.width - sized.width) / 2.0;
    final double top =
        targetBounds.top + (targetBounds.height - sized.height) / 2.0;
    return Rect.fromLTWH(left, top, sized.width, sized.height);
  }

  /// Computes effective minimum size capped so it never exceeds [targetBounds].
  static Size effectiveMinSize(Size minSize, Rect targetBounds) {
    return Size(
      math.min(minSize.width, targetBounds.width),
      math.min(minSize.height, targetBounds.height),
    );
  }
}
