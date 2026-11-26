import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import '../models/pomodoro_state.dart';
import 'constants.dart';
import 'window_bounds_helper.dart';

class PlatformHelper {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static const MethodChannel _vDesktopChannel =
      MethodChannel('com.mabfocus.app/virtual_desktop');

  static const double unhoveredSize = 240.0;
  static const double baseCircleSize = 78.0;
  static const double hoveredWidth = 240.0;
  static const double hoveredHeight = 180.0;
  static const double expandedSheetWidth = 360.0;
  static const double expandedSheetHeight = 560.0;

  static const Size dashboardMinSize = Size(420, 480);
  static const Size dashboardDefaultSize = Size(1180, 780);
  static const Size startupDefaultSize = Size(1220, 800);
  static const Size floatingMinSize = Size(200, 140);
  static const Size edgeDockSize = Size(18, 140);

  static Future<void> pinToAllVirtualDesktops() async {
    if (!Platform.isWindows) return;
    try {
      await _vDesktopChannel.invokeMethod('pinToAllDesktops');
    } catch (_) {}
  }

  static Future<
      ({
        Rect primaryVisible,
        List<Rect> allVisible,
        List<Display> displays,
        Display? primaryDisplay,
      })> _getDisplaySnapshot() async {
    Display? primary;
    List<Display> displays = [];
    try {
      primary = await screenRetriever.getPrimaryDisplay();
    } catch (_) {}
    try {
      displays = await screenRetriever.getAllDisplays();
    } catch (_) {}

    final Rect primaryVisible = primary != null
        ? WindowBoundsHelper.displayVisibleRect(primary)
        : (displays.isNotEmpty
            ? WindowBoundsHelper.displayVisibleRect(displays.first)
            : WindowBoundsHelper.fallbackDisplayBounds);

    final List<Rect> allVisible = [primaryVisible];
    for (final d in displays) {
      final rect = WindowBoundsHelper.displayVisibleRect(d);
      if (rect != primaryVisible) {
        allVisible.add(rect);
      }
    }

    return (
      primaryVisible: primaryVisible,
      allVisible: allVisible,
      displays: displays,
      primaryDisplay: primary ?? (displays.isNotEmpty ? displays.first : null),
    );
  }

  static Display? _resolveTargetDisplay(
    List<Display> displays,
    Display? primary,
    Rect? windowBounds,
  ) {
    if (displays.isEmpty) return primary;
    final primaryRect = primary != null
        ? WindowBoundsHelper.displayVisibleRect(primary)
        : WindowBoundsHelper.displayVisibleRect(displays.first);
    final rects = displays.map(WindowBoundsHelper.displayVisibleRect).toList();
    final targetRect = WindowBoundsHelper.selectTargetDisplayBounds(
      windowBounds: windowBounds,
      displayVisibleBounds: rects,
      primaryVisibleBounds: primaryRect,
    );
    for (final d in displays) {
      if (WindowBoundsHelper.displayVisibleRect(d) == targetRect) {
        return d;
      }
    }
    return primary ?? displays.first;
  }

  static Future<Rect?> _getCurrentWindowBounds() async {
    try {
      return await windowManager.getBounds();
    } catch (_) {
      return null;
    }
  }

  static Future<void> initWindowManager() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();

    final snapshot = await _getDisplaySnapshot();
    final Rect initialBounds = WindowBoundsHelper.clampAndCenterInBounds(
      desiredSize: startupDefaultSize,
      targetBounds: snapshot.primaryVisible,
      minSize: dashboardMinSize,
    );
    final Size minSize = WindowBoundsHelper.effectiveMinSize(
      dashboardMinSize,
      snapshot.primaryVisible,
    );

    final WindowOptions windowOptions = WindowOptions(
      size: initialBounds.size,
      minimumSize: minSize,
      center: true,
      backgroundColor: AppColors.background,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Mab-Focus v4.0 — Work & Life OS',
    );

    try {
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        try {
          if (await windowManager.isFullScreen()) {
            await windowManager.setFullScreen(false);
          }
        } catch (_) {}
        try {
          await windowManager.setAlwaysOnTop(false);
        } catch (_) {}
        try {
          await windowManager.setResizable(true);
        } catch (_) {}
        try {
          await windowManager.setBounds(initialBounds);
        } catch (_) {}
        try {
          await windowManager.show();
        } catch (_) {}
        try {
          await windowManager.focus();
        } catch (_) {}
        await pinToAllVirtualDesktops();
      });
    } catch (_) {
      try {
        await windowManager.show();
      } catch (_) {}
    }
  }

  static Future<void> switchToDashboardMode() async {
    if (!isDesktop) return;
    try {
      try {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
      } catch (_) {}
      try {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        }
      } catch (_) {}

      await windowManager.setAlwaysOnTop(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setBackgroundColor(AppColors.background);
      await windowManager.setResizable(true);
      await windowManager.setHasShadow(true);

      final snapshot = await _getDisplaySnapshot();
      final currentBounds = await _getCurrentWindowBounds();
      final targetVisible = WindowBoundsHelper.selectTargetDisplayBounds(
        windowBounds: currentBounds,
        displayVisibleBounds: snapshot.allVisible,
        primaryVisibleBounds: snapshot.primaryVisible,
      );
      final targetRect = WindowBoundsHelper.clampAndCenterInBounds(
        desiredSize: dashboardDefaultSize,
        targetBounds: targetVisible,
        minSize: dashboardMinSize,
      );
      final minSize = WindowBoundsHelper.effectiveMinSize(
        dashboardMinSize,
        targetVisible,
      );

      await windowManager.setMinimumSize(minSize);
      await windowManager.setBounds(targetRect);
    } catch (_) {}
  }

  static Future<void> enterLifeSlideshowMode() async {
    if (!isDesktop) return;
    try {
      final snapshot = await _getDisplaySnapshot();
      final currentBounds = await _getCurrentWindowBounds();
      final targetDisplay = _resolveTargetDisplay(
        snapshot.displays,
        snapshot.primaryDisplay,
        currentBounds,
      );

      final double screenLeft = targetDisplay?.visiblePosition?.dx ?? 0.0;
      final double screenTop = targetDisplay?.visiblePosition?.dy ?? 0.0;
      final double screenWidth = targetDisplay?.size.width ??
          WindowBoundsHelper.fallbackDisplayBounds.width;
      final double screenHeight = targetDisplay?.size.height ??
          WindowBoundsHelper.fallbackDisplayBounds.height;

      // ۱. اجازه تغییر ابعاد به سیستم عامل ویندوز داده شود
      await windowManager.setResizable(true);

      // ۲. ریست وضعیت frameless در پلاگین window_manager تا متد setFullScreen عمل کند
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);

      // ۳. تغییر صریح ابعاد و مختصات پنجره دقیقا به ابعاد مانیتور فعال
      await windowManager.setBounds(
        Rect.fromLTWH(screenLeft, screenTop, screenWidth, screenHeight),
      );

      // ۴. فعال‌سازی حالت فول‌اسکرین، قرارگیری در بالاترین لایه و سنجاق به همه دسکتاپ‌ها
      try {
        await windowManager.setFullScreen(true);
      } catch (_) {}
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      await pinToAllVirtualDesktops();
    } catch (_) {}
  }

  static Future<void> exitLifeSlideshowMode(
      WindowPosture previousPosture) async {
    if (!isDesktop) return;
    try {
      try {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
      } catch (_) {}
      try {
        await windowManager.setAlwaysOnTop(false);
      } catch (_) {}

      if (previousPosture == WindowPosture.dashboard) {
        await switchToDashboardMode();
      } else if (previousPosture == WindowPosture.edgeDockedLeft) {
        await switchToEdgeDockedMode(true);
      } else if (previousPosture == WindowPosture.edgeDockedRight) {
        await switchToEdgeDockedMode(false);
      } else {
        await switchToFloatingWidgetMode();
      }
    } catch (_) {
      await switchToDashboardMode();
    }
  }

  static Future<void> setPinned(bool isPinned) async {
    if (!isDesktop) return;
    try {
      await windowManager.setAlwaysOnTop(isPinned);
    } catch (_) {}
  }

  static Future<bool> isNearLeftEdge() async {
    if (!isDesktop) return false;
    try {
      final snapshot = await _getDisplaySnapshot();
      final currentBounds = await _getCurrentWindowBounds();
      if (currentBounds == null) return false;
      final targetDisplay = _resolveTargetDisplay(
        snapshot.displays,
        snapshot.primaryDisplay,
        currentBounds,
      );
      final targetVisible = targetDisplay != null
          ? WindowBoundsHelper.displayVisibleRect(targetDisplay)
          : snapshot.primaryVisible;
      if ((currentBounds.left - targetVisible.left) < 140.0) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// به‌روزرسانی ابعاد پنجره در صورت باز یا بسته شدن کوئیک‌شیت (تنظیمات)
  static Future<void> updateFloatingSheetExpansion(bool isSheetExpanded) async {
    if (!isDesktop) return;
    try {
      final snapshot = await _getDisplaySnapshot();
      final currentBounds = await _getCurrentWindowBounds();
      final double cx = currentBounds != null
          ? currentBounds.left + (currentBounds.width / 2.0)
          : snapshot.primaryVisible.center.dx;
      final double top = currentBounds?.top ?? snapshot.primaryVisible.top + 80.0;

      final targetVisible = WindowBoundsHelper.selectTargetDisplayBounds(
        windowBounds: currentBounds,
        displayVisibleBounds: snapshot.allVisible,
        primaryVisibleBounds: snapshot.primaryVisible,
      );

      final double targetWidth =
          isSheetExpanded ? expandedSheetWidth : hoveredWidth;
      final double maxSheetH = math.max(300.0, targetVisible.height - 40.0);
      final double targetHeight = isSheetExpanded
          ? expandedSheetHeight.clamp(300.0, maxSheetH)
          : hoveredHeight;

      final clamped = WindowBoundsHelper.clampWindowBounds(
        desired: Rect.fromLTWH(
          cx - (targetWidth / 2.0),
          top,
          targetWidth,
          targetHeight,
        ),
        displayVisibleBounds: snapshot.allVisible,
        minSize: floatingMinSize,
      );

      await windowManager.setMinimumSize(
        WindowBoundsHelper.effectiveMinSize(floatingMinSize, targetVisible),
      );
      await windowManager.setBounds(clamped);
    } catch (_) {}
  }

  /// سازگاری با متدهای قدیمی - در حالت هاور پنجره نیتیو تغییر اندازه پیدا نمی‌کند تا از پرش و تکان خوردن جلوگیری شود
  static Future<void> setFloatingWidgetHovered(
    bool isHovered, {
    bool isSheetExpanded = false,
  }) async {
    // برای پایداری ۱۰۰٪ پنجره، عملیات هاور به صورت انیمیشن خالص فلاتر اجرا می‌شود و نیازی به تغییر سایز پنجره سیستم‌عامل نیست.
    if (isSheetExpanded) {
      await updateFloatingSheetExpansion(true);
    }
  }

  /// انتقال به حالت ویجت شناور
  static Future<void> switchToFloatingWidgetMode({
    bool isSheetExpanded = false,
    bool isPinned = true,
  }) async {
    if (!isDesktop) return;
    try {
      try {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
      } catch (_) {}

      final snapshot = await _getDisplaySnapshot();
      final currentBounds = await _getCurrentWindowBounds();
      final targetVisible = WindowBoundsHelper.selectTargetDisplayBounds(
        windowBounds: currentBounds,
        displayVisibleBounds: snapshot.allVisible,
        primaryVisibleBounds: snapshot.primaryVisible,
      );

      await windowManager.setMinimumSize(
        WindowBoundsHelper.effectiveMinSize(floatingMinSize, targetVisible),
      );
      await windowManager.setAsFrameless();
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setHasShadow(false);
      await windowManager.setAlwaysOnTop(isPinned);
      await windowManager.setResizable(false);

      final double targetWidth =
          isSheetExpanded ? expandedSheetWidth : hoveredWidth;
      final double targetHeight =
          isSheetExpanded ? expandedSheetHeight : hoveredHeight;

      final desired = Rect.fromLTWH(
        currentBounds?.left ?? targetVisible.left + 40.0,
        currentBounds?.top ?? targetVisible.top + 40.0,
        targetWidth,
        targetHeight,
      );
      final clamped = WindowBoundsHelper.clampWindowBounds(
        desired: desired,
        displayVisibleBounds: snapshot.allVisible,
        minSize: floatingMinSize,
      );

      await windowManager.setBounds(clamped);
      await pinToAllVirtualDesktops();
    } catch (_) {}
  }

  static Future<void> switchToEdgeDockedMode(bool isLeft) async {
    if (!isDesktop) return;
    try {
      try {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
      } catch (_) {}

      final snapshot = await _getDisplaySnapshot();
      final currentBounds = await _getCurrentWindowBounds();
      final targetVisible = WindowBoundsHelper.selectTargetDisplayBounds(
        windowBounds: currentBounds,
        displayVisibleBounds: snapshot.allVisible,
        primaryVisibleBounds: snapshot.primaryVisible,
      );

      await windowManager.setMinimumSize(
        WindowBoundsHelper.effectiveMinSize(edgeDockSize, targetVisible),
      );
      await windowManager.setAsFrameless();
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setHasShadow(false);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setResizable(false);

      final double targetX = isLeft
          ? targetVisible.left
          : (targetVisible.right - edgeDockSize.width);
      final double targetY =
          currentBounds?.top ?? (targetVisible.top + 40.0);

      final Rect clamped = WindowBoundsHelper.clampWindowBounds(
        desired: Rect.fromLTWH(
          targetX,
          targetY,
          edgeDockSize.width,
          edgeDockSize.height,
        ),
        displayVisibleBounds: [targetVisible],
        minSize: edgeDockSize,
      );

      await windowManager.setBounds(clamped);
      await pinToAllVirtualDesktops();
    } catch (_) {}
  }

  static Future<WindowPosture?> checkEdgeSnapCondition() async {
    if (!isDesktop) return null;
    try {
      final snapshot = await _getDisplaySnapshot();
      final currentBounds = await _getCurrentWindowBounds();
      if (currentBounds == null) return null;

      final targetVisible = WindowBoundsHelper.selectTargetDisplayBounds(
        windowBounds: currentBounds,
        displayVisibleBounds: snapshot.allVisible,
        primaryVisibleBounds: snapshot.primaryVisible,
      );

      if (currentBounds.left <= targetVisible.left + 15.0) {
        return WindowPosture.edgeDockedLeft;
      } else if (currentBounds.right >= targetVisible.right - 15.0) {
        return WindowPosture.edgeDockedRight;
      }
    } catch (_) {}
    return null;
  }
}
