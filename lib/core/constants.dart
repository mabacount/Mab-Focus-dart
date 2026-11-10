import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF141416);
  static const Color surface = Color(0xFF1E1E22);
  static const Color surfaceElevated = Color(0xFF28282E);
  static const Color border = Color(0x14FFFFFF);

  static const Color focus = Color(0xFF3B82F6);
  static const Color breakTime = Color(0xFF10B981);
  static const Color golden = Color(0xFFFFB703);
  static const Color overtime = Color(0xFFFF5722); // نارنجی متمایل به قرمز برای اضافه‌کاری متمایز از ستاره طلایی
  static const Color stopwatch = Color(0xFF06B6D4);
  static const Color edited = Color(0xFF8B5CF6);
  static const Color draftWarning = Color(0xFFF59E0B);
  static const Color lifeSanctuary = Color(0xFF10B981);

  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);
}

class AppDurations {
  static const int defaultFocusSeconds = 25 * 60;
  static const int defaultShortBreakSeconds = 5 * 60;
  static const int defaultLongBreakSeconds = 60 * 60;
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
  static const String settingKeyGCalToken = 'gcal_access_token';
  static const String settingKeyPlanCalendarId = 'gcal_plan_calendar_id';
  static const String settingKeyWorkLogCalendarId = 'gcal_worklog_calendar_id';
  static const String settingKeyBreakLogCalendarId =
      'gcal_breaklog_calendar_id';
  static const String settingKeyPlayMusicDuringBreaks =
      'play_music_during_breaks';
  static const String settingKeyWidgetPinned = 'widget_is_pinned';
}
