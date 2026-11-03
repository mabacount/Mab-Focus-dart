import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/task_log_entry.dart';
import '../models/scheduled_block.dart';
import '../models/project_node.dart';
import 'database_service.dart';

class GCalSyncService {
  static final GCalSyncService instance = GCalSyncService._init();

  GCalSyncService._init();

  Future<String?> _getToken() async {
    return await DatabaseService.instance
        .getSetting(AppDefaults.settingKeyGCalToken);
  }

  /// دریافت بلوک‌های برنامه‌ریزی‌شده از تقویم گوگل (GET)
  Future<List<ScheduledBlock>> fetchScheduledBlocksFromGCal({
    required DateTime timeMin,
    required DateTime timeMax,
    required List<ProjectNode> projects,
  }) async {
    final token = await _getToken();
    final planCalId = await DatabaseService.instance.getSetting(
      AppDefaults.settingKeyPlanCalendarId,
      defaultValue: 'primary',
    );

    if (token == null || token.trim().isEmpty) return [];

    try {
      final uri = Uri.parse(
        'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(planCalId ?? "primary")}/events'
        '?timeMin=${timeMin.toUtc().toIso8601String()}'
        '&timeMax=${timeMax.toUtc().toIso8601String()}'
        '&singleEvents=true'
        '&orderBy=startTime',
      );

      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer ${token.trim()}'});
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      final List<ScheduledBlock> result = [];

      for (final item in items) {
        final startRaw = item['start']?['dateTime'] ?? item['start']?['date'];
        final endRaw = item['end']?['dateTime'] ?? item['end']?['date'];
        if (startRaw == null || endRaw == null) continue;

        final title = item['summary'] as String? ?? 'برنامه بدون عنوان';
        final eventId = item['id'] as String;

        // تطبیق هوشمند با نام پروژه
        String? matchedProjectId;
        for (final p in projects) {
          if (title.contains(p.name)) {
            matchedProjectId = p.id;
            break;
          }
        }

        final block = ScheduledBlock(
          id: 'gcal_$eventId',
          title: title,
          projectId: matchedProjectId,
          startTime: DateTime.parse(startRaw as String).toLocal(),
          endTime: DateTime.parse(endRaw as String).toLocal(),
          source: 'gcal',
          externalEventId: eventId,
        );

        await DatabaseService.instance.insertScheduledBlock(block);
        result.add(block);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// ارسال بلوک برنامه‌ریزی‌شده به تقویم برنامه در گوگل (POST/PATCH)
  Future<bool> pushScheduledBlockToGCal(ScheduledBlock block) async {
    final token = await _getToken();
    final planCalId = await DatabaseService.instance.getSetting(
      AppDefaults.settingKeyPlanCalendarId,
      defaultValue: 'primary',
    );

    if (token == null || token.trim().isEmpty) return false;

    try {
      final body = {
        'summary': block.title,
        'description': 'ثبت‌شده توسط سند ظرفیت Mab-Focus',
        'start': {'dateTime': block.startTime.toUtc().toIso8601String()},
        'end': {'dateTime': block.endTime.toUtc().toIso8601String()},
      };

      final headers = {
        'Authorization': 'Bearer ${token.trim()}',
        'Content-Type': 'application/json',
      };

      http.Response res;
      if (block.externalEventId != null && block.externalEventId!.isNotEmpty) {
        final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(planCalId ?? "primary")}/events/${block.externalEventId}',
        );
        res = await http.patch(uri, headers: headers, body: jsonEncode(body));
      } else {
        final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(planCalId ?? "primary")}/events',
        );
        res = await http.post(uri, headers: headers, body: jsonEncode(body));
      }

      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// ارسال رکوردهای کارکرد و استراحت به تقویم‌های مربوطه
  Future<bool> syncTaskLogEntry(TaskLogEntry entry,
      {ProjectNode? project}) async {
    if (entry.endTime == null) return false;
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) return false;

    // تفکیک تقویم مقصد: استراحت، پروژه اختصاصی، یا تقویم کارکرد عمومی
    String targetCalId;
    if (entry.isBreakEntry) {
      targetCalId = await DatabaseService.instance.getSetting(
            AppDefaults.settingKeyBreakLogCalendarId,
            defaultValue: 'primary',
          ) ??
          'primary';
    } else if (project?.googleCalendarId != null &&
        project!.googleCalendarId!.isNotEmpty) {
      targetCalId = project.googleCalendarId!;
    } else {
      targetCalId = await DatabaseService.instance.getSetting(
            AppDefaults.settingKeyWorkLogCalendarId,
            defaultValue: 'primary',
          ) ??
          'primary';
    }

    final String prefix = entry.isEdited ? '[Edited] ' : '';
    final String summary = '$prefix${entry.title}';
    final desc = StringBuffer()
      ..writeln('ثبت‌شده توسط Mab-Focus v3.0')
      ..writeln('نوع رکورد: ${entry.entryType}')
      ..writeln(
          'مدت: ${(entry.durationSeconds / 60).toStringAsFixed(1)} دقیقه');

    if (entry.isEdited) {
      desc.writeln(
        'زمان اولیه قبل از ویرایش: ${((entry.originalDurationSeconds ?? entry.durationSeconds) / 60).toStringAsFixed(1)} دقیقه',
      );
      if (entry.editNote != null) desc.writeln('علت ویرایش: ${entry.editNote}');
    }

    final body = {
      'summary': summary,
      'description': desc.toString(),
      'start': {'dateTime': entry.startTime.toUtc().toIso8601String()},
      'end': {'dateTime': entry.endTime!.toUtc().toIso8601String()},
    };

    try {
      final headers = {
        'Authorization': 'Bearer ${token.trim()}',
        'Content-Type': 'application/json',
      };

      http.Response res;
      if (entry.calendarEventId != null && entry.calendarEventId!.isNotEmpty) {
        final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(targetCalId)}/events/${entry.calendarEventId}',
        );
        res = await http.patch(uri, headers: headers, body: jsonEncode(body));
      } else {
        final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(targetCalId)}/events',
        );
        res = await http.post(uri, headers: headers, body: jsonEncode(body));
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final eventId = decoded['id'] as String?;
        await DatabaseService.instance.updateTaskLog(
          entry.copyWith(
            syncStatus: 'synced',
            calendarEventId: eventId,
            targetCalendarId: targetCalId,
          ),
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
