// صف ارسال و به‌روزرسانی رویدادها در تقویم گوگل
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/task_log_entry.dart';
import 'database_service.dart';

class GCalSyncService {
  static final GCalSyncService instance = GCalSyncService._init();

  GCalSyncService._init();

  Future<bool> syncTaskLogEntry(TaskLogEntry entry) async {
    if (entry.endTime == null) return false;

    final token = await DatabaseService.instance
        .getSetting(AppDefaults.settingKeyGCalToken);
    final syncLevel = await DatabaseService.instance.getSetting(
      AppDefaults.settingKeyGCalSyncLevel,
      defaultValue: 'task',
    );

    if (token == null || token.trim().isEmpty || syncLevel == 'disabled') {
      return false;
    }

    final String summaryPrefix = entry.isEdited ? '[Edited] ' : '';
    final String summary = '$summaryPrefix${entry.title}';

    final descriptionBuffer = StringBuffer();
    descriptionBuffer.writeln('ثبت‌شده توسط Mab-Focus (ChronoFlow)');
    descriptionBuffer.writeln(
        'مدت نهایی: ${(entry.durationSeconds / 60).toStringAsFixed(1)} دقیقه');
    if (entry.isEdited) {
      final origMin = entry.originalDurationSeconds != null
          ? (entry.originalDurationSeconds! / 60).toStringAsFixed(1)
          : '-';
      descriptionBuffer.writeln('وضعیت ممیزی: ویرایش‌شده [Edited]');
      descriptionBuffer.writeln('مدت اولیه پیش از ویرایش: $origMin دقیقه');
      if (entry.editNote != null && entry.editNote!.isNotEmpty) {
        descriptionBuffer.writeln('علت ویرایش: ${entry.editNote}');
      }
    }

    final Map<String, dynamic> bodyData = {
      'summary': summary,
      'description': descriptionBuffer.toString(),
      'start': {
        'dateTime': entry.startTime.toUtc().toIso8601String(),
      },
      'end': {
        'dateTime': entry.endTime!.toUtc().toIso8601String(),
      },
    };

    try {
      final headers = {
        'Authorization': 'Bearer ${token.trim()}',
        'Content-Type': 'application/json',
      };

      http.Response response;
      if (entry.calendarEventId != null && entry.calendarEventId!.isNotEmpty) {
        final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/primary/events/${entry.calendarEventId}',
        );
        response =
            await http.patch(uri, headers: headers, body: jsonEncode(bodyData));
      } else {
        final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/primary/events',
        );
        response =
            await http.post(uri, headers: headers, body: jsonEncode(bodyData));
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final eventId = decoded['id'] as String? ?? entry.calendarEventId;
        final updatedEntry = entry.copyWith(
          syncStatus: 'synced',
          calendarEventId: eventId,
        );
        await DatabaseService.instance.updateTaskLog(updatedEntry);
        return true;
      } else {
        final failedEntry = entry.copyWith(syncStatus: 'failed');
        await DatabaseService.instance.updateTaskLog(failedEntry);
        return false;
      }
    } catch (_) {
      final failedEntry = entry.copyWith(syncStatus: 'failed');
      await DatabaseService.instance.updateTaskLog(failedEntry);
      return false;
    }
  }
}
