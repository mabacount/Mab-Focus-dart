/// توابع کمکی محاسبات زمانی و تقویم جلالی (شروع هفته از بامداد شنبه)
class DateTimeUtils {
  /// محاسبه مبدا هفته جلالی (بامداد شنبه ساعت 00:00:00 به وقت محلی)
  /// فرمول استاندارد: (dt.weekday % 7 + 1) % 7
  /// در دارت: دوشنبه=1 ... جمعه=5، شنبه=6، یکشنبه=7
  static DateTime startOfJalaliWeek(DateTime dt) {
    final local = dt.toLocal();
    final int daysSinceSaturday = (local.weekday % 7 + 1) % 7;
    return DateTime(local.year, local.month, local.day)
        .subtract(Duration(days: daysSinceSaturday));
  }

  /// آغاز روز جاری (ساعت 00:00:00 به وقت محلی)
  static DateTime startOfDay(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// آغاز ماه جلالی جاری (تقریبی بر مبنای تقویم شمسی) یا ماه میلادی
  static DateTime startOfMonth(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, 1);
  }

  /// قالب‌بندی خوانای مدت زمان به ساعت و دقیقه و ثانیه (HH:MM:SS یا MM:SS)
  static String formatDurationHms(int totalSeconds) {
    final int absSec = totalSeconds < 0 ? 0 : totalSeconds;
    final int h = absSec ~/ 3600;
    final int m = (absSec % 3600) ~/ 60;
    final int s = absSec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// قالب‌بندی کوتاه فارسی مدت زمان (مثلاً: ۲ ساعت و ۱۵ دقیقه)
  static String formatDurationFa(int totalSeconds) {
    final int absSec = totalSeconds < 0 ? 0 : totalSeconds;
    final int h = absSec ~/ 3600;
    final int m = (absSec % 3600) ~/ 60;
    final int s = absSec % 60;
    if (h > 0 && m > 0) return '$h ساعت و $m دقیقه';
    if (h > 0) return '$h ساعت';
    if (m > 0) return '$m دقیقه';
    return '$s ثانیه';
  }
}
