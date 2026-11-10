import 'package:flutter/material.dart';

class AppColors {
  // رنگ‌های پایه ابسیدین (مشترک / پیش‌فرض)
  static const Color background = Color(0xFF141416);
  static const Color surface = Color(0xFF1E1E22);
  static const Color surfaceElevated = Color(0xFF28282E);
  static const Color border = Color(0x14FFFFFF);

  // پالت قلمرو کار (Work Blue — تم سرمه‌ای/آبی)
  static const Color workBlue = Color(0xFF3B82F6);
  static const Color workBackground = Color(0xFF0F131B);
  static const Color workSurface = Color(0xFF161C28);
  static const Color workSurfaceElevated = Color(0xFF1F2737);
  static const Color workBorder = Color(0x263B82F6);

  // پالت قلمرو زندگی (Life Green — تم سبز زمردی/پناهگاه زندگی)
  static const Color lifeGreen = Color(0xFF10B981);
  static const Color lifeBackground = Color(0xFF0D1714);
  static const Color lifeSurface = Color(0xFF14221D);
  static const Color lifeSurfaceElevated = Color(0xFF1B2E27);
  static const Color lifeBorder = Color(0x2610B981);

  // رنگ‌های وضعیت و ممیزی
  static const Color focus = workBlue;
  static const Color breakTime = lifeGreen;
  static const Color lifeSanctuary = lifeGreen;
  static const Color golden = Color(0xFFFFB703);
  static const Color overtime = Color(0xFFFF5722);
  static const Color stopwatch = Color(0xFF06B6D4);
  static const Color edited = Color(0xFF8B5CF6);
  static const Color draftWarning = Color(0xFFF59E0B);

  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);
}

class RealmPalette {
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color border;

  const RealmPalette({
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
  });

  static const RealmPalette work = RealmPalette(
    accent: AppColors.workBlue,
    background: AppColors.workBackground,
    surface: AppColors.workSurface,
    surfaceElevated: AppColors.workSurfaceElevated,
    border: AppColors.workBorder,
  );

  static const RealmPalette life = RealmPalette(
    accent: AppColors.lifeGreen,
    background: AppColors.lifeBackground,
    surface: AppColors.lifeSurface,
    surfaceElevated: AppColors.lifeSurfaceElevated,
    border: AppColors.lifeBorder,
  );
}

class AppDurations {
  static const int defaultFocusSeconds = 25 * 60; // ۲۵ دقیقه = 1500 ثانیه
  static const int defaultShortBreakSeconds = 5 * 60; // کف ۵ دقیقه = 300 ثانیه
  static const int defaultLongBreakSeconds = 60 * 60; // ۶۰ دقیقه = 3600 ثانیه
  static const int defaultCycleWorkTargetSeconds =
      100 * 60; // ۱۰۰ دقیقه کار خالص = 6000 ثانیه
  static const int defaultBreakRatio = 5; // نسبت کار به استراحت ۵ به ۱
  static const int defaultCycleAutoResetThresholdSeconds =
      90 * 60; // ۹۰ دقیقه استراحت/خواب = ریست خودکار چرخه
  static const int setsPerCycle = 4;
  static const int overtimeNudgeIntervalSeconds = 300;
}

class AppDefaults {
  static const String defaultTxtFileName = 'ChronoFlow_WorkLog.txt';
  static const String untitledTaskTitle = 'تسک بدون عنوان';

  static const String settingKeyGCalSyncLevel = 'gcal_sync_level';
  static const String settingKeyTxtPath = 'txt_log_path';
  static const String settingKeyFocusDuration = 'focus_duration_minutes';
  static const String settingKeyShortBreakDuration =
      'short_break_duration_minutes';
  static const String settingKeyLongBreakDuration =
      'long_break_duration_minutes';
  static const String settingKeyBreakRatio = 'flowmodoro_break_ratio';
  static const String settingKeyCycleWorkTargetMinutes =
      'flowmodoro_cycle_work_target_minutes';
  static const String settingKeyCycleAutoResetMinutes =
      'flowmodoro_cycle_auto_reset_minutes';

  static const String settingKeyGCalToken = 'gcal_access_token';
  static const String settingKeyPlanCalendarId = 'gcal_plan_calendar_id';
  static const String settingKeyLifePlanCalendarId =
      'gcal_life_plan_calendar_id';
  static const String settingKeyWorkLogCalendarId = 'gcal_worklog_calendar_id';
  static const String settingKeyLifeLogCalendarId = 'gcal_lifelog_calendar_id';
  static const String settingKeyBreakLogCalendarId =
      'gcal_breaklog_calendar_id';
  static const String settingKeyPlayMusicDuringBreaks =
      'play_music_during_breaks';
  static const String settingKeyWidgetPinned = 'widget_is_pinned';

  // کلیدهای پایداری وضعیت موتور Flowmodoro در SQLite جهت بازیابی پس از کرش/بستن اپ
  static const String stateCycleWorkSeconds = 'state_cycle_work_seconds';
  static const String stateEarnedShortBreakSeconds =
      'state_earned_short_break_seconds';
  static const String stateBreakDebtSeconds = 'state_break_debt_seconds';
  static const String stateIsInLongBreak = 'state_is_in_long_break';
  static const String stateCurrentBreakTargetSeconds =
      'state_current_break_target_seconds';
  static const String stateClockMode = 'state_clock_mode';
  static const String stateLastCycleResetAt = 'state_last_cycle_reset_at';
}
