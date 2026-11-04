import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import '../models/pomodoro_state.dart';
import 'constants.dart';

class PlatformHelper {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static const double unhoveredSize = 84.0;
  static const double baseCircleSize = 68.0;
  static const double hoveredWidth = 340.0;
  static const double hoveredHeight = 145.0;
  static const double expandedSheetWidth = 340.0;
  static const double expandedSheetHeight = 460.0;

  static Future<void> initWindowManager() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();

    const WindowOptions windowOptions = WindowOptions(
      size: Size(1180, 780),
      minimumSize: Size(18, 140),
      center: true,
      backgroundColor: AppColors.background,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Mab-Focus v3.0 — Life Capacity OS',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  static Future<void> switchToDashboardMode() async {
    if (!isDesktop) return;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setBackgroundColor(AppColors.background);
    await windowManager.setResizable(true);
    await windowManager.setHasShadow(true);
    await windowManager.setSize(const Size(1180, 780));
    await windowManager.center();
  }

  static Future<void> setPinned(bool isPinned) async {
    if (!isDesktop) return;
    await windowManager.setAlwaysOnTop(isPinned);
  }

  static Future<bool> isNearLeftEdge() async {
    if (!isDesktop) return false;
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final currentPos = await windowManager.getPosition();
      final screenLeft = display.visiblePosition?.dx ?? 0.0;
      // اگر پنجره نزدیک لبه چپ باشد
      if ((currentPos.dx - screenLeft) < 140.0) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// تغییر اندازه پنجره ویندوز بر اساس وضعیت هاور جهت آزاد شدن کلیک‌های اطراف دایره
  static Future<void> setFloatingWidgetHovered(
    bool isHovered, {
    bool buttonsOnRight = false,
    bool isSheetExpanded = false,
  }) async {
    if (!isDesktop) return;
    try {
      final currentPos = await windowManager.getPosition();
      final currentSize = await windowManager.getSize();

      // محاسبه مختصات مرکز دایره روی نمایشگر فیزیکی
      final double cx;
      final double cy;

      if (currentSize.width <= 110.0) {
        // اندازه پنجره در حالت بسته: unhoveredSize x unhoveredSize
        cx = currentPos.dx + (currentSize.width / 2.0);
        cy = currentPos.dy + (currentSize.height / 2.0);
      } else {
        // اندازه پنجره در حالت باز: 340x145
        final double circleXInWindow = buttonsOnRight ? 78.0 : (340.0 - 78.0);
        const double circleYInWindow = 44.0;
        cx = currentPos.dx + circleXInWindow;
        cy = currentPos.dy + circleYInWindow;
      }

      if (isSheetExpanded) {
        await windowManager
            .setSize(const Size(expandedSheetWidth, expandedSheetHeight));
        final double targetX =
            buttonsOnRight ? (cx - 78.0) : (cx - (340.0 - 78.0));
        final double targetY = cy - 44.0;
        await windowManager.setPosition(Offset(targetX, targetY));
      } else if (isHovered) {
        // باز شدن پنجره به 340x145 به طور دقیق دور مرکز دایره
        final double targetX =
            buttonsOnRight ? (cx - 78.0) : (cx - (340.0 - 78.0));
        final double targetY = cy - 44.0;
        await windowManager.setSize(const Size(hoveredWidth, hoveredHeight));
        await windowManager.setPosition(Offset(targetX, targetY));
      } else {
        // جمع شدن پنجره به 84x84 دقیقاً روی دایره تا فضای اطراف برای کلیک آزاد شود
        final double targetX = cx - (unhoveredSize / 2.0);
        final double targetY = cy - (unhoveredSize / 2.0);
        await windowManager.setSize(const Size(unhoveredSize, unhoveredSize));
        await windowManager.setPosition(Offset(targetX, targetY));
      }
    } catch (_) {}
  }

  /// انتقال به حالت ویجت شناور (با اندازه اولیه ۸۴×۸۴ جهت آزاد بودن اطراف دایره)
  static Future<void> switchToFloatingWidgetMode({
    bool isSheetExpanded = false,
    bool isPinned = true,
  }) async {
    if (!isDesktop) return;

    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setHasShadow(false);
    await windowManager.setAlwaysOnTop(isPinned);
    await windowManager.setResizable(false);

    final display = await screenRetriever.getPrimaryDisplay();
    final Offset currentPos = await windowManager.getPosition();

    final double screenLeft = display.visiblePosition?.dx ?? 0.0;
    final double screenTop = display.visiblePosition?.dy ?? 0.0;
    final double screenWidth = display.size.width;
    final double screenHeight = display.size.height;

    final double targetWidth =
        isSheetExpanded ? expandedSheetWidth : unhoveredSize;
    final double targetHeight =
        isSheetExpanded ? expandedSheetHeight : unhoveredSize;

    final double maxX = screenLeft + screenWidth - targetWidth;
    final double maxY = screenTop + screenHeight - targetHeight;

    final double newX =
        currentPos.dx.clamp(screenLeft, maxX > screenLeft ? maxX : screenLeft);
    final double newY =
        currentPos.dy.clamp(screenTop, maxY > screenTop ? maxY : screenTop);

    await windowManager.setSize(Size(targetWidth, targetHeight));
    await windowManager.setPosition(Offset(newX, newY));
  }

  static Future<void> switchToEdgeDockedMode(bool isLeft) async {
    if (!isDesktop) return;
    final display = await screenRetriever.getPrimaryDisplay();
    final Offset currentPos = await windowManager.getPosition();

    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setHasShadow(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setResizable(false);
    await windowManager.setSize(const Size(18, 140));

    final double targetX = isLeft ? 0.0 : (display.size.width - 18.0);
    final double targetY =
        currentPos.dy.clamp(40.0, display.size.height - 180.0);
    await windowManager.setPosition(Offset(targetX, targetY));
  }

  static Future<WindowPosture?> checkEdgeSnapCondition() async {
    if (!isDesktop) return null;
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final Offset pos = await windowManager.getPosition();
      final Size winSize = await windowManager.getSize();

      final double screenLeft = display.visiblePosition?.dx ?? 0.0;
      final double screenRight = screenLeft + display.size.width;

      if (pos.dx <= screenLeft + 15.0) {
        return WindowPosture.edgeDockedLeft;
      } else if (pos.dx + winSize.width >= screenRight - 15.0) {
        return WindowPosture.edgeDockedRight;
      }
    } catch (_) {}
    return null;
  }
}
