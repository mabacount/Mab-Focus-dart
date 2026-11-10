/// تبدیل و قالب‌بندی تاریخ هجری شمسی (جلالی)
/// الگوریتم دقیق تقویم خورشیدی ایران
class JalaliDate {
  final int year;
  final int month;
  final int day;

  const JalaliDate(this.year, this.month, this.day);

  static const List<String> monthNames = [
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];

  static const List<String> weekDays = [
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنجشنبه',
    'جمعه',
    'شنبه',
    'یکشنبه',
  ];

  String get monthName =>
      (month >= 1 && month <= 12) ? monthNames[month - 1] : '';

  static String getWeekDayName(DateTime date) {
    return weekDays[(date.weekday - 1) % 7];
  }

  /// تبدیل شیء استاندارد DateTime به تقویم هجری شمسی
  factory JalaliDate.fromDateTime(DateTime date) {
    int gy = date.year;
    int gm = date.month;
    int gd = date.day;

    const gDM = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    int jy;
    if (gy > 1600) {
      jy = 979;
      gy -= 1600;
    } else {
      jy = 0;
      gy -= 621;
    }

    final int gy2 = (gm > 2) ? (gy + 1) : gy;
    int days = (365 * gy) +
        ((gy2 + 3) ~/ 4) -
        ((gy2 + 99) ~/ 100) +
        ((gy2 + 399) ~/ 400) -
        80 +
        gd +
        gDM[gm - 1];

    jy += 33 * (days ~/ 12053);
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;

    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }

    final int jm;
    final int jd;
    if (days < 186) {
      jm = 1 + (days ~/ 31);
      jd = 1 + (days % 31);
    } else {
      jm = 7 + ((days - 186) ~/ 30);
      jd = 1 + ((days - 186) % 30);
    }

    return JalaliDate(jy, jm, jd);
  }

  /// قالب‌بندی کامل: ۱۴ آبان ۱۴۰۵
  String formatFull() => '$day $monthName $year';

  /// قالب‌بندی کوتاه: ۱۴ آبان
  String formatShort() => '$day $monthName';

  /// قالب‌بندی عددی: ۱۴۰۵/۰۸/۱۴
  String formatNumeric() =>
      '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}';

  /// قالب‌بندی با نام روز: چهارشنبه ۱۴ آبان
  static String formatWithWeekDay(DateTime date) {
    final j = JalaliDate.fromDateTime(date);
    final w = getWeekDayName(date);
    return '$w ${j.day} ${j.monthName}';
  }

  /// قالب‌بندی با نام روز و سال: چهارشنبه ۱۴ آبان ۱۴۰۵
  static String formatWithWeekDayAndYear(DateTime date) {
    final j = JalaliDate.fromDateTime(date);
    final w = getWeekDayName(date);
    return '$w ${j.day} ${j.monthName} ${j.year}';
  }
}
