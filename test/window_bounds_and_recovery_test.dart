import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/core/color_utils.dart';
import 'package:mab_focus/core/constants.dart';
import 'package:mab_focus/core/window_bounds_helper.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/models/time_record.dart';
import 'package:mab_focus/providers/app_state_provider.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  tearDown(() {
    DatabaseService.instance.resetForTest();
  });

  group('WindowBoundsHelper', () {
    test('clamps oversized startup window to DPI-scaled display visible bounds',
        () {
      const visible = Rect.fromLTWH(0, 0, 1280, 672);
      final clamped = WindowBoundsHelper.clampWindowBounds(
        desired: const Rect.fromLTWH(0, 0, 1220, 800),
        displayVisibleBounds: const [visible],
        minSize: const Size(420, 480),
      );

      expect(clamped, const Rect.fromLTWH(0, 0, 1220, 672));
    });

    test('recovers off-screen negative coordinates back onto primary display',
        () {
      const primary = Rect.fromLTWH(0, 0, 1920, 1040);
      final clamped = WindowBoundsHelper.clampWindowBounds(
        desired: const Rect.fromLTWH(-4000, -3000, 1180, 780),
        displayVisibleBounds: const [primary],
        minSize: const Size(420, 480),
      );

      expect(clamped, const Rect.fromLTWH(0, 0, 1180, 780));
    });

    test('recovers off-screen positive coordinates onto primary bottom-right',
        () {
      const primary = Rect.fromLTWH(0, 0, 1920, 1040);
      final clamped = WindowBoundsHelper.clampWindowBounds(
        desired: const Rect.fromLTWH(5000, 3000, 360, 560),
        displayVisibleBounds: const [primary],
        minSize: const Size(200, 140),
      );

      expect(clamped, const Rect.fromLTWH(1560, 480, 360, 560));
    });

    test('keeps window on secondary monitor including negative-left monitor',
        () {
      const primary = Rect.fromLTWH(0, 0, 1920, 1040);
      const rightSecondary = Rect.fromLTWH(1920, 0, 1920, 1040);
      const leftSecondary = Rect.fromLTWH(-1920, 0, 1920, 1040);

      final onRight = WindowBoundsHelper.clampWindowBounds(
        desired: const Rect.fromLTWH(3700, 900, 360, 560),
        displayVisibleBounds: const [primary, rightSecondary],
        minSize: const Size(200, 140),
      );
      expect(onRight.left, 3480);
      expect(onRight.top, 480);
      expect(onRight.right, 3840);
      expect(onRight.bottom, 1040);

      final onLeft = WindowBoundsHelper.clampWindowBounds(
        desired: const Rect.fromLTWH(-1800, 200, 360, 560),
        displayVisibleBounds: const [primary, leftSecondary],
        minSize: const Size(200, 140),
      );
      expect(onLeft, const Rect.fromLTWH(-1800, 200, 360, 560));
    });

    test('displayVisibleRect falls back when visiblePosition or size is null',
        () {
      const display = Display(
        id: 'd1',
        size: Size(1600, 900),
      );
      expect(
        WindowBoundsHelper.displayVisibleRect(display),
        const Rect.fromLTWH(0, 0, 1600, 900),
      );
    });

    test('enforces minSize and caps effectiveMinSize on tiny display safely',
        () {
      const normalDisplay = Rect.fromLTWH(0, 0, 1280, 720);
      final expanded = WindowBoundsHelper.clampWindowBounds(
        desired: const Rect.fromLTWH(100, 100, 100, 100),
        displayVisibleBounds: const [normalDisplay],
        minSize: const Size(420, 480),
      );
      expect(expanded, const Rect.fromLTWH(100, 100, 420, 480));

      const tinyDisplay = Rect.fromLTWH(0, 0, 300, 350);
      final capped = WindowBoundsHelper.clampWindowBounds(
        desired: const Rect.fromLTWH(0, 0, 200, 200),
        displayVisibleBounds: const [tinyDisplay],
        minSize: const Size(420, 480),
      );
      expect(capped, const Rect.fromLTWH(0, 0, 300, 350));
      expect(
        WindowBoundsHelper.effectiveMinSize(
          const Size(420, 480),
          tinyDisplay,
        ),
        const Size(300, 350),
      );
    });
  });

  group('ColorUtils.parseHex', () {
    test('parses valid 6-char, 3-char, 8-char, and 0x hex strings', () {
      expect(ColorUtils.parseHex('#3B82F6'), const Color(0xFF3B82F6));
      expect(ColorUtils.parseHex('10B981'), const Color(0xFF10B981));
      expect(ColorUtils.parseHex('#80FF5722'), const Color(0x80FF5722));
      expect(ColorUtils.parseHex('#F0A'), const Color(0xFFFF00AA));
      expect(ColorUtils.parseHex('0xFF223344'), const Color(0xFF223344));
    });

    test('returns fallback on malformed, empty, or null hex strings', () {
      expect(
        ColorUtils.parseHex('bad-hex', fallback: AppColors.lifeGreen),
        AppColors.lifeGreen,
      );
      expect(ColorUtils.parseHex(''), AppColors.workBlue);
      expect(ColorUtils.parseHex(null), AppColors.workBlue);
    });
  });

  group('Life-Mode Crash Recovery & Slideshow Exit', () {
    test('recovers open life record and dismisses slideshow cleanly', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 5,
          singleInstance: false,
          onCreate: (db, v) => DatabaseService.instance.createSchemaV5(db, v),
        ),
      );
      DatabaseService.instance.setTestDatabase(db);

      await DatabaseService.instance.insertTimeRecord(
        TimeRecord(
          id: 'life_open_1',
          realm: AppRealm.life,
          clockMode: ClockType.pomodoro,
          titleSnapshot: 'استراحت میان‌روز',
          isUntitledDraft: false,
          startTime: DateTime.now().subtract(const Duration(minutes: 4)),
        ),
      );

      final provider = AppStateProvider(isTestMode: true);
      await provider.initialize();

      expect(provider.pomodoroState.realm, AppRealm.life);
      expect(provider.pomodoroState.status, isNot(TimerStatus.idle));
      expect(provider.shouldShowNatureSlideshow, isTrue);

      await provider.dismissNatureSlideshow();

      expect(provider.shouldShowNatureSlideshow, isFalse);
      expect(provider.pomodoroState.windowPosture, WindowPosture.dashboard);

      provider.dispose();
      await db.close();
    });
  });
}
