import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../models/outcome_item.dart';
import '../models/phase_tag.dart';
import '../models/pomodoro_state.dart';
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
      final records = await DatabaseService.instance.getAllTimeRecords();
      final outcomes = await DatabaseService.instance.getOutcomes();
      final projects =
          await DatabaseService.instance.getProjects(includeArchived: true);
      final tags =
          await DatabaseService.instance.getPhaseTags(includeArchived: true);

      final Map<String, OutcomeItem> outcomeMap = {
        for (final o in outcomes) o.id: o
      };
      final Map<String, PhaseTag> tagMap = {for (final t in tags) t.id: t};

      final dateFormat = DateFormat('yyyy-MM-dd');
      final timeFormat = DateFormat('HH:mm:ss');
      final buffer = StringBuffer();

      buffer.writeln(
          '================================================================================');
      buffer.writeln(
          'MAB-FOCUS v4.0 — WORK & LIFE CAPACITY OS AUDIT TRAIL');
      buffer.writeln(
          'Last Updated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      buffer.writeln(
          '================================================================================\n');

      for (final rec in records) {
        final dateStr = dateFormat.format(rec.startTime.toLocal());
        final startStr = timeFormat.format(rec.startTime.toLocal());
        final endStr = rec.endTime != null
            ? timeFormat.format(rec.endTime!.toLocal())
            : 'در حال اجرا';
        final durStr = _formatDuration(rec.durationSeconds);

        final breadcrumb =
            DatabaseService.getProjectBreadcrumb(rec.projectId, projects)
                .map((e) => e.name)
                .join(' > ');
        final projectLabel = breadcrumb.isEmpty ? '-' : breadcrumb;
        final tagNames = rec.tagIds
            .map((id) => tagMap[id]?.name)
            .whereType<String>()
            .join('، ');
        final resolvedTitle = rec.outcomeId != null
            ? (outcomeMap[rec.outcomeId]?.title ?? rec.titleSnapshot)
            : rec.titleSnapshot;

        final realmTag = rec.realm.labelFa;
        final clockTag = rec.clockMode.labelFa;

        if (rec.isUntitledDraft) {
          buffer.writeln(
              '[$dateStr | $startStr - $endStr | $durStr] [$realmTag/$clockTag] [نیازمند تکمیل] $resolvedTitle');
        } else if (rec.isEdited) {
          final origDur = _formatDuration(
              rec.originalDurationSeconds ?? rec.durationSeconds);
          final note = rec.editNote != null ? ' (علت: ${rec.editNote})' : '';
          buffer.writeln(
            '[$dateStr | $startStr - $endStr | $durStr] [$realmTag/$clockTag] [EDITED - زمان اولیه: $origDur] [$projectLabel | $tagNames] $resolvedTitle$note',
          );
        } else {
          buffer.writeln(
            '[$dateStr | $startStr - $endStr | $durStr] [$realmTag/$clockTag] [$projectLabel | $tagNames] $resolvedTitle',
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
