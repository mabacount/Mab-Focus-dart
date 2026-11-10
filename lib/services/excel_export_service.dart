import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/constants.dart';
import '../core/jalali_date.dart';
import '../models/outcome_item.dart';
import '../models/phase_tag.dart';
import '../models/pomodoro_state.dart';
import '../models/project_node.dart';
import '../models/session_note.dart';
import '../models/time_record.dart';
import 'database_service.dart';

class ExcelExportService {
  static final ExcelExportService instance = ExcelExportService._init();

  ExcelExportService._init();

  Future<String?> exportTimesheetToExcel({
    required List<TimeRecord> records,
    required List<OutcomeItem> outcomes,
    required List<ProjectNode> projects,
    required List<PhaseTag> tags,
  }) async {
    final excel = Excel.createExcel();
    const String sheetName = 'MabFocus_Timesheet';
    final Sheet sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final Map<String, OutcomeItem> outcomeMap = {
      for (final o in outcomes) o.id: o
    };
    final Map<String, PhaseTag> tagMap = {for (final t in tags) t.id: t};

    // سرستون‌های ۱۶‌گانه استاندارد ممیزی و ظرفیت نسخه ۴
    sheet.appendRow([
      TextCellValue('ردیف'),
      TextCellValue('تاریخ'),
      TextCellValue('قلمرو (Work/Life)'),
      TextCellValue('عنوان کار / فعالیت'),
      TextCellValue('حالت زمان‌سنج'),
      TextCellValue('مسیر درختی پروژه'),
      TextCellValue('تگ‌های فاز کاری'),
      TextCellValue('ساعت شروع'),
      TextCellValue('ساعت پایان'),
      TextCellValue('مدت نهایی (دقیقه)'),
      TextCellValue('اضافه‌زمان / Overtime (دقیقه)'),
      TextCellValue('استراحت استحقاقی کسب‌شده (دقیقه)'),
      TextCellValue('وضعیت ممیزی زمان'),
      TextCellValue('مدت اولیه قبل از ویرایش (دقیقه)'),
      TextCellValue('توضیحات ویرایش'),
      TextCellValue('شناسه کار (Outcome ID)'),
    ]);

    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm:ss');

    for (int i = 0; i < records.length; i++) {
      final entry = records[i];
      final breadcrumb =
          DatabaseService.getProjectBreadcrumb(entry.projectId, projects)
              .map((e) => e.name)
              .join(' > ');
      final projectPath = breadcrumb.isEmpty ? '-' : breadcrumb;
      final tagNames = entry.tagIds
          .map((id) => tagMap[id]?.name)
          .whereType<String>()
          .join('، ');
      final resolvedTitle = entry.outcomeId != null
          ? (outcomeMap[entry.outcomeId]?.title ?? entry.titleSnapshot)
          : entry.titleSnapshot;

      final double finalMin =
          double.parse((entry.durationSeconds / 60.0).toStringAsFixed(2));
      final double overtimeMin =
          double.parse((entry.overtimeSeconds / 60.0).toStringAsFixed(2));
      final double earnedBreakMin =
          double.parse((entry.earnedBreakSeconds / 60.0).toStringAsFixed(2));
      final String auditStatus =
          entry.isEdited ? 'ویرایش‌شده [Edited]' : 'ثبت اصلی (Original)';
      final String origMin =
          (entry.isEdited && entry.originalDurationSeconds != null)
              ? (entry.originalDurationSeconds! / 60.0).toStringAsFixed(2)
              : '-';

      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(dateFormat.format(entry.startTime.toLocal())),
        TextCellValue(entry.realm.labelFa),
        TextCellValue(resolvedTitle),
        TextCellValue(entry.clockMode.labelFa),
        TextCellValue(projectPath),
        TextCellValue(tagNames.isEmpty ? '-' : tagNames),
        TextCellValue(timeFormat.format(entry.startTime.toLocal())),
        TextCellValue(entry.endTime != null
            ? timeFormat.format(entry.endTime!.toLocal())
            : '-'),
        DoubleCellValue(finalMin),
        DoubleCellValue(overtimeMin),
        DoubleCellValue(earnedBreakMin),
        TextCellValue(auditStatus),
        TextCellValue(origMin),
        TextCellValue(entry.editNote ?? '-'),
        TextCellValue(entry.outcomeId ?? '-'),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes == null) {
      return null;
    }

    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final defaultFileName = 'MabFocus_Timesheet_$timestamp.xlsx';

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره خروجی اکسل تایم‌شیت Mab-Focus',
        fileName: defaultFileName,
      );

      if (outputPath == null) {
        return null;
      }
      final finalPath = outputPath.toLowerCase().endsWith('.xlsx')
          ? outputPath
          : '$outputPath.xlsx';
      final outFile = File(finalPath);
      await outFile.writeAsBytes(fileBytes, flush: true);
      return finalPath;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      final mobilePath = p.join(docsDir.path, defaultFileName);
      final outFile = File(mobilePath);
      await outFile.writeAsBytes(fileBytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(mobilePath)],
          text: 'گزارش تایم‌شیت و سند ظرفیت Mab-Focus',
        ),
      );
      return mobilePath;
    }
  }

  Future<String?> exportSessionNotesToExcel({
    required List<SessionNote> notes,
    required List<OutcomeItem> outcomes,
    required List<TimeRecord> records,
    required List<ProjectNode> projects,
  }) async {
    final excel = Excel.createExcel();
    const String sheetName = 'MabFocus_SessionNotes';
    final Sheet sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final Map<String, OutcomeItem> outcomeMap = {
      for (final o in outcomes) o.id: o
    };
    final Map<String, TimeRecord> recordMap = {
      for (final r in records) r.id: r
    };

    sheet.appendRow([
      TextCellValue('ردیف'),
      TextCellValue('تاریخ و روز'),
      TextCellValue('ساعت ثبت'),
      TextCellValue('قلمرو'),
      TextCellValue('نوع یادداشت'),
      TextCellValue('عنوان کار / فعالیت'),
      TextCellValue('مسیر پروژه'),
      TextCellValue('متن یادداشت'),
      TextCellValue('تعداد تصاویر'),
      TextCellValue('مسیر فایل تصاویر'),
    ]);

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      final breadcrumb =
          DatabaseService.getProjectBreadcrumb(note.projectId, projects)
              .map((e) => e.name)
              .join(' > ');
      final projectName = breadcrumb.isEmpty ? '-' : breadcrumb;

      final String taskTitle = (note.outcomeId != null
              ? outcomeMap[note.outcomeId]?.title
              : null) ??
          (note.timeRecordId != null
              ? recordMap[note.timeRecordId]?.titleSnapshot
              : null) ??
          AppDefaults.untitledTaskTitle;

      final jalaliStr = JalaliDate.formatWithWeekDay(note.createdAt);
      final timeStr =
          '${note.createdAt.hour.toString().padLeft(2, '0')}:${note.createdAt.minute.toString().padLeft(2, '0')}';

      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(jalaliStr),
        TextCellValue(timeStr),
        TextCellValue(note.realm.labelFa),
        TextCellValue(note.noteType.labelFa),
        TextCellValue(taskTitle),
        TextCellValue(projectName),
        TextCellValue(note.content),
        IntCellValue(note.imagePaths.length),
        TextCellValue(note.imagePaths.join(';\n')),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes == null) return null;

    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final defaultFileName = 'MabFocus_SessionNotes_$timestamp.xlsx';

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره خروجی اکسل یادداشت‌های حین کار',
        fileName: defaultFileName,
      );

      if (outputPath == null) return null;
      final finalPath = outputPath.toLowerCase().endsWith('.xlsx')
          ? outputPath
          : '$outputPath.xlsx';
      final outFile = File(finalPath);
      await outFile.writeAsBytes(fileBytes, flush: true);
      return finalPath;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      final mobilePath = p.join(docsDir.path, defaultFileName);
      final outFile = File(mobilePath);
      await outFile.writeAsBytes(fileBytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(mobilePath)],
          text: 'خروجی اکسل یادداشت‌های حین کار Mab-Focus',
        ),
      );
      return mobilePath;
    }
  }
}
