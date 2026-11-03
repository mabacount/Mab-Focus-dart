// متدهای تغییر شکل پنجره ویندوز، نوار لبه‌ای و Always-on-Top
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import '../models/pomodoro_state.dart';
import 'constants.dart';

class PlatformHelper {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<void> initWindowManager() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();

    const WindowOptions windowOptions = WindowOptions(
      size: Size(1150, 760),
      minimumSize: Size(18, 160),
      center: true,
      backgroundColor: AppColors.background,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Mab-Focus — Dashboard',
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
    await windowManager.setSize(const Size(1150, 760));
    await windowManager.center();
  }

  static Future<void> switchToFloatingWidgetMode(
      {bool expanded = false}) async {
    if (!isDesktop) return;
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setResizable(false);
    final Size targetSize =
        expanded ? const Size(320, 440) : const Size(220, 220);
    await windowManager.setSize(targetSize);
  }

  static Future<void> switchToEdgeDockedMode(bool isLeft) async {
    if (!isDesktop) return;
    final display = await screenRetriever.getPrimaryDisplay();
    final Offset currentPos = await windowManager.getPosition();

    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setResizable(false);
    await windowManager.setSize(const Size(18, 160));

    final double targetX = isLeft ? 0.0 : (display.size.width - 18.0);
    final double targetY =
        currentPos.dy.clamp(40.0, display.size.height - 200.0);
    await windowManager.setPosition(Offset(targetX, targetY));
  }

  static Future<WindowPosture?> checkEdgeSnapCondition() async {
    if (!isDesktop) return null;
    final display = await screenRetriever.getPrimaryDisplay();
    final Offset pos = await windowManager.getPosition();
    final Size winSize = await windowManager.getSize();

    if (pos.dx <= 20.0) {
      return WindowPosture.edgeDockedLeft;
    } else if (pos.dx + winSize.width >= display.size.width - 20.0) {
      return WindowPosture.edgeDockedRight;
    }
    return null;
  }
}
