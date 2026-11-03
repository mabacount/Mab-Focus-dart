import os
import sys

# مسیر ریشه پروژه
BASE_DIR = r"E:\آرشیو من\Mab-Project\Mab-Focus-dart"

# ساختار پوشه‌ها طبق سند معماری فلاتر
DIRECTORIES = [
    os.path.join(BASE_DIR, "lib", "core"),
    os.path.join(BASE_DIR, "lib", "models"),
    os.path.join(BASE_DIR, "lib", "services"),
    os.path.join(BASE_DIR, "lib", "providers"),
    os.path.join(BASE_DIR, "lib", "ui", "widget_mode"),
    os.path.join(BASE_DIR, "lib", "ui", "dashboard_mode"),
    os.path.join(BASE_DIR, "assets", "audio"),
    os.path.join(BASE_DIR, "assets", "fonts"),
]

# محتوای فایل pubspec.yaml هماهنگ با وابستگی‌های ویندوز و اندروید
PUBSPEC_CONTENT = """name: mab_focus
description: Mab-Focus - Dual-Clock Pomodoro & Employer Time Tracker for Windows & Android
publish_to: 'none'
version: 2.0.0+1

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  provider: ^6.1.2
  sqflite: ^2.3.3
  sqflite_common_ffi: ^2.3.3      # پشتیبانی کامل از SQLite در ویندوز
  path_provider: ^2.1.3
  path: ^1.9.0
  uuid: ^4.4.0
  intl: ^0.19.0
  shared_preferences: ^2.2.3
  window_manager: ^0.3.9          # مدیریت پنجره شفاف و بدون حاشیه در ویندوز
  screen_retriever: ^0.1.9        # محاسبه ابعاد مانیتور جهت چسبیدن به لبه
  excel: ^4.0.3                   # خروجی اکسل بدون وابستگی بومی
  file_picker: ^8.0.3             # انتخاب مسیر لاگ متنی و فایل اکسل
  share_plus: ^9.0.0              # اشتراک‌گذاری خروجی در اندروید
  http: ^1.2.1                    # ارتباط با API تقویم گوگل
  google_fonts: ^6.2.1            # فونت‌های Vazirmatn و JetBrains Mono

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/audio/
"""

GITIGNORE_CONTENT = """# Flutter/Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
build/
.pub-cache/
.pub/

# IDE
.idea/
.vscode/
*.swp
*.iml

# OS
Thumbs.db
Desktop.ini
.DS_Store
"""

# لیست فایل‌های کدنویسی با توضیح اولیه ساختار
FILES = {
    os.path.join(BASE_DIR, "pubspec.yaml"): PUBSPEC_CONTENT,
    os.path.join(BASE_DIR, ".gitignore"): GITIGNORE_CONTENT,
    os.path.join(BASE_DIR, "lib", "main.dart"): "// نقطه ورود اپلیکیشن، مقداردهی اولیه SQLite FFI و WindowManager\n",
    os.path.join(BASE_DIR, "lib", "core", "constants.dart"): "// ثابت‌ها، پالت رنگ، تم تاریک ابسیدین و فونت‌ها\n",
    os.path.join(BASE_DIR, "lib", "core", "platform_helper.dart"): "// متدهای تغییر شکل پنجره ویندوز، نوار لبه‌ای و Always-on-Top\n",
    os.path.join(BASE_DIR, "lib", "models", "project_node.dart"): "// مدل پروژه‌های کلان، زیرپروژه‌ها و تنظیمات احتساب استراحت\n",
    os.path.join(BASE_DIR, "lib", "models", "phase_tag.dart"): "// مدل تگ‌های فاز کاری و وضعیت اجرایی\n",
    os.path.join(BASE_DIR, "lib", "models", "task_log_entry.dart"): "// مدل لاگ کارکرد، فیلدهای ممیزی ویرایش [Edited] و وضعیت همگام‌سازی\n",
    os.path.join(BASE_DIR, "lib", "models", "pomodoro_state.dart"): "// وضعیت لحظه‌ای تایمر پومودورو، اضافه‌کاری منفی و حالت پنجره\n",
    os.path.join(BASE_DIR, "lib", "services", "database_service.dart"): "// مدیریت پایگاه داده SQLite و تابع ممیزی updateTaskLogWithAudit\n",
    os.path.join(BASE_DIR, "lib", "services", "txt_logger_service.dart"): "// لاگر خودکار فایل متنی ChronoFlow_WorkLog.txt\n",
    os.path.join(BASE_DIR, "lib", "services", "excel_export_service.dart"): "// تولید خروجی اکسل با ۱۳ ستون شفافیت و ممیزی کارفرما\n",
    os.path.join(BASE_DIR, "lib", "services", "sound_service.dart"): "// پخش صدای زنگ پایان و تلنگرهای ارگونومیک اضافه‌کاری\n",
    os.path.join(BASE_DIR, "lib", "services", "gcal_sync_service.dart"): "// صف ارسال و به‌روزرسانی رویدادها در تقویم گوگل\n",
    os.path.join(BASE_DIR, "lib", "providers", "app_state_provider.dart"): "// موتور دو ساعته، Timestamp-Delta Ticker و مدیریت وضعیت برنامه\n",
    os.path.join(BASE_DIR, "lib", "ui", "app_shell.dart"): "// سوییچر میان ویجت شناور دایره‌ای و داشبورد اصلی\n",
    os.path.join(BASE_DIR, "lib", "ui", "widget_mode", "floating_widget_view.dart"): "// ویجت شناور، حلقه وضعیت، شمارنده و نوار لبه‌ای\n",
    os.path.join(BASE_DIR, "lib", "ui", "widget_mode", "quick_task_sheet.dart"): "// منوی بازشونده شروع فوری تسک و تعویض تسک در میانه پومودورو\n",
    os.path.join(BASE_DIR, "lib", "ui", "dashboard_mode", "dashboard_screen.dart"): "// پوسته کلی داشبورد، ناوبری تب‌ها و دکمه تبدیل به ویجت\n",
    os.path.join(BASE_DIR, "lib", "ui", "dashboard_mode", "untitled_inbox_tab.dart"): "// کارتابل تکمیل مشخصات تسک‌های بدون عنوان بدون تگ ویرایش\n",
    os.path.join(BASE_DIR, "lib", "ui", "dashboard_mode", "activity_log_tab.dart"): "// جدول تایم‌شیت، نشانگر بنفش [Edited] و مودال ویرایش زمان\n",
    os.path.join(BASE_DIR, "lib", "ui", "dashboard_mode", "project_studio_tab.dart"): "// مدیریت درختی پروژه‌ها و کلیدهای احتساب استراحت\n",
    os.path.join(BASE_DIR, "lib", "ui", "dashboard_mode", "settings_tab.dart"): "// تنظیمات تایمرها، مسیر فایل متنی و همگام‌سازی تقویم\n",
}

def main():
    print(f"[+] ساخت ساختار پروژه در مسیر: {BASE_DIR}")
    
    # ساخت پوشه‌ها
    for directory in DIRECTORIES:
        os.makedirs(directory, exist_ok=True)
        print(f"  ✓ دایرکتوری ایجاد شد: {directory}")

    # ساخت فایل‌ها
    for filepath, content in FILES.items():
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"  ✓ فایل ایجاد شد: {os.path.basename(filepath)}")

    print("\n[✔] تمامی دایرکتوری‌ها و فایل‌های پروژه فلاتر با موفقیت ساخته شدند.")

if __name__ == "__main__":
    main()