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
    final int h = totalSeconds ~/ 3600;
    final int m = (totalSeconds % 3600) ~/ 60;
    final int s = totalSeconds % 60;
    if (h > 0) {
      return '${h}h ${m}m ${s}s';
    }
    return '${m}m ${s}s';
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
        for (final p in projects) p.id: p
      };
      final Map<String, PhaseTag> tagMap = {for (final t in tags) t.id: t};

      final dateFormat = DateFormat('yyyy-MM-dd');
      final timeFormat = DateFormat('HH:mm:ss');
      final buffer = StringBuffer();

      buffer.writeln(
          '================================================================================');
      buffer
          .writeln('MAB-FOCUS v3.0 — WORK LOG, BREAKS & CAPACITY AUDIT TRAIL');
      buffer.writeln(
          'Last Updated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      buffer.writeln(
          '================================================================================\n');

      for (final log in logs) {
        final dateStr = dateFormat.format(log.startTime.toLocal());
        final startStr = timeFormat.format(log.startTime.toLocal());
        final endStr = log.endTime != null
            ? timeFormat.format(log.endTime!.toLocal())
            : 'در حال اجرا';
        final durStr = _formatDuration(log.durationSeconds);

        final macroName = log.macroProjectId != null
            ? (projectMap[log.macroProjectId]?.name ?? '-')
            : '-';
        final subName = log.subProjectId != null
            ? (projectMap[log.subProjectId]?.name ?? '-')
            : '-';
        final tagNames = log.tagIds
            .map((id) => tagMap[id]?.name)
            .whereType<String>()
            .join('، ');

        if (log.isBreakEntry) {
          final breakTitle = log.entryType == 'long_break'
              ? 'استراحت طولانی (زندگی)'
              : 'استراحت ۵ دقیقه‌ای';
          buffer.writeln(
              '[$dateStr | $startStr - $endStr | $durStr] [استراحت] $breakTitle');
        } else if (log.isUntitledDraft) {
          buffer.writeln(
              '[$dateStr | $startStr - $endStr | $durStr] [نیازمند تکمیل] ${log.title}');
        } else if (log.isEdited) {
          final origDur = _formatDuration(
              log.originalDurationSeconds ?? log.durationSeconds);
          final note = log.editNote != null ? ' (علت: ${log.editNote})' : '';
          buffer.writeln(
            '[$dateStr | $startStr - $endStr | $durStr] [EDITED - زمان اولیه: $origDur] [$macroName > $subName | $tagNames] ${log.title}$note',
          );
        } else {
          final typeLabel = log.isStopwatch ? '[کرنومتر]' : '[کار]';
          buffer.writeln(
            '[$dateStr | $startStr - $endStr | $durStr] $typeLabel [$macroName > $subName | $tagNames] ${log.title}',
          );
        }
      }

      final file = File(filePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(buffer.toString(), flush: true);
    } catch (_) {}
  }

  Future<String> readLogFileContent() async {
    try {
      final filePath = await getEffectiveLogFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return 'فایل لاگ هنوز ایجاد نشده است.';
    } catch (e) {
      return 'خطا در خواندن فایل متنی: $e';
    }
  }
}
