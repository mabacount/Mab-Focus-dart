import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/jalali_date.dart';
import '../models/project_node.dart';
import '../models/phase_tag.dart';
import '../models/task_log_entry.dart';
import '../models/work_note_entry.dart';

class ExcelExportService {
  static final ExcelExportService instance = ExcelExportService._init();

  ExcelExportService._init();

  Future<String?> exportTimesheetToExcel({
    required List<TaskLogEntry> logs,
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

    final Map<String, ProjectNode> projectMap = {
      for (final p in projects) p.id: p
    };
    final Map<String, PhaseTag> tagMap = {for (final t in tags) t.id: t};

    // سرستون‌های ۱۵‌گانه استاندارد ممیزی و ظرفیت
    sheet.appendRow([
      TextCellValue('ردیف'),
      TextCellValue('تاریخ'),
      TextCellValue('عنوان تسک / فعالیت'),
      TextCellValue('نوع رکورد'),
      TextCellValue('پروژه کلان'),
      TextCellValue('پروژه زیرمجموعه'),
      TextCellValue('تگ‌های فاز کاری'),
      TextCellValue('ساعت شروع'),
      TextCellValue('ساعت پایان'),
      TextCellValue('مدت نهایی (دقیقه)'),
      TextCellValue('اضافه‌کاری منفی (دقیقه)'),
      TextCellValue('وضعیت ممیزی زمان'),
      TextCellValue('مدت اولیه قبل از ویرایش (دقیقه)'),
      TextCellValue('توضیحات ویرایش'),
      TextCellValue('شناسه گروه هدف (Group ID)'),
    ]);

    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm:ss');

    for (int i = 0; i < logs.length; i++) {
      final entry = logs[i];
      final macroName = entry.macroProjectId != null
          ? (projectMap[entry.macroProjectId]?.name ?? '-')
          : '-';
      final subName = entry.subProjectId != null
          ? (projectMap[entry.subProjectId]?.name ?? '-')
          : '-';
      final tagNames = entry.tagIds
          .map((id) => tagMap[id]?.name)
          .whereType<String>()
          .join('، ');

      String typeLabel;
      switch (entry.entryType) {
        case 'short_break':
          typeLabel = 'استراحت کوتاه';
          break;
        case 'long_break':
          typeLabel = 'استراحت طولانی (زندگی)';
          break;
        case 'stopwatch':
          typeLabel = 'کرنومتر آزاد';
          break;
        default:
          typeLabel = 'کارکرد تمرکز';
      }

      final double finalMin =
          double.parse((entry.durationSeconds / 60.0).toStringAsFixed(2));
      final double overtimeMin =
          double.parse((entry.overtimeSeconds / 60.0).toStringAsFixed(2));
      final String auditStatus =
          entry.isEdited ? 'ویرایش‌شده [Edited]' : 'ثبت اصلی (Original)';
      final String origMin =
          (entry.isEdited && entry.originalDurationSeconds != null)
              ? (entry.originalDurationSeconds! / 60.0).toStringAsFixed(2)
              : '-';

      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(dateFormat.format(entry.startTime.toLocal())),
        TextCellValue(entry.title),
        TextCellValue(typeLabel),
        TextCellValue(macroName),
        TextCellValue(subName),
        TextCellValue(tagNames.isEmpty ? '-' : tagNames),
        TextCellValue(timeFormat.format(entry.startTime.toLocal())),
        TextCellValue(entry.endTime != null
            ? timeFormat.format(entry.endTime!.toLocal())
            : '-'),
        DoubleCellValue(finalMin),
        DoubleCellValue(overtimeMin),
        TextCellValue(auditStatus),
        TextCellValue(origMin),
        TextCellValue(entry.editNote ?? '-'),
        TextCellValue(entry.groupId),
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
        dialogTitle: 'ذخیره خروجی اکسل کارفرما',
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

  Future<String?> exportWorkNotesToExcel({
    required List<WorkNoteEntry> notes,
    required List<ProjectNode> projects,
  }) async {
    final excel = Excel.createExcel();
    const String sheetName = 'MabFocus_WorkNotes';
    final Sheet sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final Map<String, ProjectNode> projectMap = {
      for (final p in projects) p.id: p
    };

    // سرستون‌های گزارش یادداشت‌ها
    sheet.appendRow([
      TextCellValue('ردیف'),
      TextCellValue('تاریخ و روز'),
      TextCellValue('ساعت ثبت'),
      TextCellValue('عنوان تسک'),
      TextCellValue('پروژه'),
      TextCellValue('متن گزارش کار / یادداشت'),
      TextCellValue('تعداد تصاویر'),
      TextCellValue('مسیر فایل تصاویر'),
    ]);

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      final project =
          note.projectId != null ? projectMap[note.projectId] : null;
      final projectName = project != null
          ? (project.isMacro ? project.name : '↳ ${project.name}')
          : '-';
      final jalaliStr = JalaliDate.formatWithWeekDay(note.createdAt);
      final timeStr =
          '${note.createdAt.hour.toString().padLeft(2, '0')}:${note.createdAt.minute.toString().padLeft(2, '0')}';

      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(jalaliStr),
        TextCellValue(timeStr),
        TextCellValue(note.taskTitle),
        TextCellValue(projectName),
        TextCellValue(note.content),
        IntCellValue(note.imagePaths.length),
        TextCellValue(note.imagePaths.join(';\n')),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes == null) return null;

    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final defaultFileName = 'MabFocus_WorkNotes_$timestamp.xlsx';

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره خروجی اکسل یادداشت‌های گزارش کار',
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
          text: 'خروجی اکسل یادداشت‌های گزارش کار Mab-Focus',
        ),
      );
      return mobilePath;
    }
  }
}
