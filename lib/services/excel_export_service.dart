// تولید خروجی اکسل با ۱۳ ستون شفافیت و ممیزی کارفرما
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/project_node.dart';
import '../models/phase_tag.dart';
import '../models/task_log_entry.dart';

class ExcelExportService {
  static final ExcelExportService instance = ExcelExportService._init();

  ExcelExportService._init();

  Future<String?> exportTimesheetToExcel({
    required List<TaskLogEntry> logs,
    required List<ProjectNode> projects,
    required List<PhaseTag> tags,
  }) async {
    final excel = Excel.createExcel();
    const String sheetName = 'Timesheet';
    final Sheet sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final Map<String, ProjectNode> projectMap = {
      for (final proj in projects) proj.id: proj,
    };
    final Map<String, PhaseTag> tagMap = {
      for (final t in tags) t.id: t,
    };

    // ردیف سرستون‌ها (۱۳ ستون استاندارد ممیزی کارفرما)
    sheet.appendRow([
      TextCellValue('ردیف'),
      TextCellValue('تاریخ'),
      TextCellValue('عنوان تسک'),
      TextCellValue('پروژه کلان'),
      TextCellValue('پروژه زیرمجموعه'),
      TextCellValue('تگ‌های فاز کاری'),
      TextCellValue('ساعت شروع'),
      TextCellValue('ساعت پایان'),
      TextCellValue('مدت نهایی (دقیقه)'),
      TextCellValue('اضافه‌کاری منفی (دقیقه)'),
      TextCellValue('وضعیت ممیزی زمان'),
      TextCellValue('مدت اولیه ثبت‌شده (دقیقه)'),
      TextCellValue('توضیحات ویرایش'),
    ]);

    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm:ss');

    for (int i = 0; i < logs.length; i++) {
      final entry = logs[i];
      final macroName = entry.macroProjectId != null
          ? (projectMap[entry.macroProjectId!]?.name ?? '-')
          : '-';
      final subName = entry.subProjectId != null
          ? (projectMap[entry.subProjectId!]?.name ?? '-')
          : '-';
      final tagNames = entry.tagIds
          .map((id) => tagMap[id]?.name)
          .whereType<String>()
          .join('، ');

      final double finalMinutes =
          double.parse((entry.durationSeconds / 60.0).toStringAsFixed(2));
      final double overtimeMinutes =
          double.parse((entry.overtimeSeconds / 60.0).toStringAsFixed(2));
      final String auditStatus =
          entry.isEdited ? 'ویرایش‌شده [Edited]' : 'ثبت اصلی (Original)';
      final String origMinutesStr =
          (entry.isEdited && entry.originalDurationSeconds != null)
              ? (entry.originalDurationSeconds! / 60.0).toStringAsFixed(2)
              : '-';

      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(dateFormat.format(entry.startTime.toLocal())),
        TextCellValue(entry.title),
        TextCellValue(macroName),
        TextCellValue(subName),
        TextCellValue(tagNames.isEmpty ? '-' : tagNames),
        TextCellValue(timeFormat.format(entry.startTime.toLocal())),
        TextCellValue(entry.endTime != null
            ? timeFormat.format(entry.endTime!.toLocal())
            : '-'),
        DoubleCellValue(finalMinutes),
        DoubleCellValue(overtimeMinutes),
        TextCellValue(auditStatus),
        TextCellValue(origMinutesStr),
        TextCellValue(entry.editNote ?? '-'),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes == null) return null;

    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final defaultFileName = 'MabFocus_Timesheet_$timestamp.xlsx';

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      String? outputPath = await FilePicker.saveFile(
        dialogTitle: 'ذخیره فایل اکسل تایم‌شیت کارفرما',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputPath == null) {
        return null;
      }
      if (!outputPath.toLowerCase().endsWith('.xlsx')) {
        outputPath = '$outputPath.xlsx';
      }

      final outFile = File(outputPath);
      await outFile.writeAsBytes(fileBytes, flush: true);
      return outputPath;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      final mobilePath = p.join(docsDir.path, defaultFileName);
      final outFile = File(mobilePath);
      await outFile.writeAsBytes(fileBytes, flush: true);

      await SharePlus.instance.share(
        [
          XFile(mobilePath)
        ], // یا ارسال فایل با ساختار جدید اگر شیء XFile بخواهد
        text: 'گزارش تایم‌شیت و کارکرد Mab-Focus',
      );
      return mobilePath;
    }
  }
}
