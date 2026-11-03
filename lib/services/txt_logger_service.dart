// لاگر خودکار فایل متنی ChronoFlow_WorkLog.txt
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../models/project_node.dart';
import '../models/phase_tag.dart';
import 'database_service.dart';

class TxtLoggerService {
  static final TxtLoggerService instance = TxtLoggerService._init();

  TxtLoggerService._init();

  Future<String> getEffectiveLogFilePath() async {
    final savedPath = await DatabaseService.instance
        .getSetting(AppDefaults.settingKeyTxtPath);
    if (savedPath != null && savedPath.trim().isNotEmpty) {
      return savedPath.trim();
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final defaultPath = p.join(docsDir.path, AppDefaults.defaultTxtFileName);
    await DatabaseService.instance
        .setSetting(AppDefaults.settingKeyTxtPath, defaultPath);
    return defaultPath;
  }

  String _formatDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}m${seconds.toString().padLeft(2, '0')}s';
  }

  Future<void> syncTxtFile() async {
    try {
      final filePath = await getEffectiveLogFilePath();
      final logs = await DatabaseService.instance.getAllTaskLogs();
      final projects =
          await DatabaseService.instance.getProjects(includeArchived: true);
      final tags =
          await DatabaseService.instance.getPhaseTags(includeArchived: true);

      final Map<String, ProjectNode> projectMap = {
        for (final proj in projects) proj.id: proj,
      };
      final Map<String, PhaseTag> tagMap = {
        for (final tag in tags) tag.id: tag,
      };

      final dateFormat = DateFormat('yyyy-MM-dd');
      final timeFormat = DateFormat('HH:mm:ss');
      final buffer = StringBuffer();

      buffer.writeln(
          '================================================================================');
      buffer
          .writeln('MAB-FOCUS (CHRONOFLOW) — WORK LOG & EMPLOYER AUDIT TRAIL');
      buffer.writeln(
          'Last Updated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      buffer.writeln(
          '================================================================================');

      for (final log in logs) {
        final dateStr = dateFormat.format(log.startTime.toLocal());
        final startStr = timeFormat.format(log.startTime.toLocal());
        final endStr = log.endTime != null
            ? timeFormat.format(log.endTime!.toLocal())
            : 'در حال اجرا';
        final durationStr = _formatDuration(log.durationSeconds);

        final macroName = log.macroProjectId != null
            ? (projectMap[log.macroProjectId!]?.name ?? 'بدون پروژه کلان')
            : 'بدون پروژه کلان';
        final subName = log.subProjectId != null
            ? (projectMap[log.subProjectId!]?.name ?? '-')
            : '-';
        final tagNames = log.tagIds
            .map((id) => tagMap[id]?.name)
            .whereType<String>()
            .join('، ');
        final tagSection = tagNames.isEmpty ? 'بدون تگ' : tagNames;

        if (log.isUntitledDraft) {
          buffer.writeln(
            '[$dateStr | $startStr -$endStr | $durationStr] [نیازمند تکمیل] ${log.title}',
          );
        } else if (log.isEdited) {
          final origDur = _formatDuration(
              log.originalDurationSeconds ?? log.durationSeconds);
          final notePart =
              (log.editNote != null && log.editNote!.trim().isNotEmpty)
                  ? ' (علت: ${log.editNote!.trim()})'
                  : '';
          buffer.writeln(
            '[$dateStr | $startStr -$endStr | $durationStr] [EDITED / ویرایش‌شده - زمان اولیه: $origDur] [$macroName >$subName | $tagSection]${log.title}$notePart',
          );
        } else {
          buffer.writeln(
            '[$dateStr \vert{}$startStr - $endStr \vert{}$durationStr] [$macroName >$subName | $tagSection]${log.title}',
          );
        }
      }

      final file = File(filePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(buffer.toString(), flush: true);
    } catch (_) {
      // جلوگیری از توقف تایمر در صورت قفل بودن موقت فایل در سیستم‌عامل
    }
  }

  Future<String> readLogFileContent() async {
    try {
      final filePath = await getEffectiveLogFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return 'فایل گزارش متنی هنوز ایجاد نشده است.';
    } catch (e) {
      return 'خطا در خواندن فایل متنی: $e';
    }
  }
}
