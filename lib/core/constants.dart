// ثابت‌ها، پالت رنگ، تم تاریک ابسیدین و فونت‌ها
import 'package:flutter/material.dart';

class AppColors {
  // پس‌زمینه و کارت‌های تم دارک ابسیدین
  static const Color background = Color(0xFF141416);
  static const Color surface = Color(0xFF1E1E22);
  static const Color surfaceElevated = Color(0xFF28282E);
  static const Color border = Color(0x14FFFFFF); // rgba(255, 255, 255, 0.08)

  // رنگ‌های اختصاصی وضعیت تایمر و پروژه
  static const Color focus = Color(0xFF3B82F6); // آبی کبالت پومودورو
  static const Color breakTime = Color(0xFF10B981); // سبز زمردی استراحت
  static const Color overtime =
      Color(0xFFF59E0B); // کهربایی گرم اضافه‌کاری منفی
  static const Color edited = Color(0xFF8B5CF6); // بنفش شاخص ممیزی ویرایش
  static const Color draftWarning = Color(0xFFF59E0B); // هشدار تسک بدون عنوان

  // رنگ‌های متون
  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);
}

class AppDurations {
  static const int defaultFocusSeconds = 25 * 60; // ۲۵ دقیقه
  static const int defaultShortBreakSeconds = 5 * 60; // ۵ دقیقه
  static const int defaultLongBreakSeconds = 60 * 60; // ۶۰ دقیقه
  static const int setsPerCycle = 4; // ۴ ست قبل از استراحت طولانی
  static const int overtimeNudgeIntervalSeconds =
      300; // هشدار ارگونومیک هر ۵ دقیقه
}

class AppDefaults {
  static const String defaultTxtFileName = 'ChronoFlow_WorkLog.txt';
  static const String untitledTaskTitle = 'تسک بدون عنوان';
  static const String settingKeyTxtPath = 'txt_log_path';
  static const String settingKeyFocusDuration = 'focus_duration_minutes';
  static const String settingKeyShortBreakDuration =
      'short_break_duration_minutes';
  static const String settingKeyLongBreakDuration =
      'long_break_duration_minutes';
  static const String settingKeyGCalToken = 'gcal_access_token';
  static const String settingKeyGCalSyncLevel =
      'gcal_sync_level'; // task | pomodoro | both
}
