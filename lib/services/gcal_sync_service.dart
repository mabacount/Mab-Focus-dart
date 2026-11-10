import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/pomodoro_state.dart';
import '../models/project_node.dart';
import '../models/scheduled_block.dart';
import '../models/time_record.dart';
import 'database_service.dart';

class GCalSyncService {
  static final GCalSyncService instance = GCalSyncService._init();

  GCalSyncService._init();

  Future<String?> _getToken() async {
    return await DatabaseService.instance
        .getSetting(AppDefaults.settingKeyGCalToken);
  }

  Future<String> _getPlanCalendarIdForRealm(AppRealm realm) async {
    if (realm == AppRealm.life) {
      final lifeCal = await DatabaseService.instance
          .getSetting(AppDefaults.settingKeyLifePlanCalendarId);
      if (lifeCal != null && lifeCal.trim().isNotEmpty) {
        return lifeCal.trim();
      }
    }
    final workCal = await DatabaseService.instance.getSetting(
      AppDefaults.settingKeyPlanCalendarId,
      defaultValue: 'primary',
    );
    return (workCal != null && workCal.trim().isNotEmpty)
        ? workCal.trim()
        : 'primary';
  }

  /// دریافت بلوک‌های برنامه‌ریزی‌شده از تقویم گوگل (GET) برای هر دو قلمرو کار و زندگی
  Future<List<ScheduledBlock>> fetchScheduledBlocksFromGCal({
    required DateTime timeMin,
    required DateTime timeMax,
    required List<ProjectNode> projects,
  }) async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) return [];

    final workPlanCalId = await _getPlanCalendarIdForRealm(AppRealm.work);
    final lifePlanCalRaw = await DatabaseService.instance
        .getSetting(AppDefaults.settingKeyLifePlanCalendarId);

    final List<({String calId, AppRealm? defaultRealm})> targets = [
      (calId: workPlanCalId, defaultRealm: null),
    ];
    if (lifePlanCalRaw != null &&
        lifePlanCalRaw.trim().isNotEmpty &&
        lifePlanCalRaw.trim() != workPlanCalId) {
      targets.add((calId: lifePlanCalRaw.trim(), defaultRealm: AppRealm.life));
    }

    final List<ScheduledBlock> result = [];
    for (final target in targets) {
      try {
        final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(target.calId)}/events'
          '?timeMin=${timeMin.toUtc().toIso8601String()}'
          '&timeMax=${timeMax.toUtc().toIso8601String()}'
          '&singleEvents=true'
          '&orderBy=startTime',
        );

        final response = await http
            .get(uri, headers: {'Authorization': 'Bearer ${token.trim()}'});
        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>? ?? [];

        for (final item in items) {
          final startRaw = item['start']?['dateTime'] ?? item['start']?['date'];
          final endRaw = item['end']?['dateTime'] ?? item['end']?['date'];
          if (startRaw == null || endRaw == null) continue;

          final title = item['summary'] as String? ?? 'برنامه بدون عنوان';
          final eventId = item['id'] as String;

          ProjectNode? matchedProject;
          for (final p in projects) {
            if (target.defaultRealm != null && p.realm != target.defaultRealm) {
              continue;
            }
            if (title.contains(p.name)) {
              matchedProject = p;
              break;
            }
          }

          final blockRealm =
              target.defaultRealm ?? matchedProject?.realm ?? AppRealm.work;

          final block = ScheduledBlock(
            id: 'gcal_$eventId',
            realm: blockRealm,
            title: title,
            projectId: matchedProject?.id,
            startTime: DateTime.parse(startRaw as String).toLocal(),
            endTime: DateTime.parse(endRaw as String).toLocal(),
            source: 'gcal',
            externalEventId: eventId,
          );

          await DatabaseService.instance.insertScheduledBlock(block);
          result.add(block);
        }
      } catch (_) {}
    }
    return result;
  }

  /// ارسال بلوک برنامه‌ریزی‌شده به تقویم برنامه در گوگل (POST/PATCH) و ذخیره شناسه رویداد جهت جلوگیری از تکرار (چالش ۷)
  Future<bool> pushScheduledBlockToGCal(ScheduledBlock block) async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) return false;

    final planCalId = await _getPlanCalendarIdForRealm(block.realm);

    try {
      final body = {
        'summary': block.title,
        'description':
            'ثبت‌شده توسط سند ظرفیت Mab-Focus v4.0 (${block.realm.labelFa})',
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
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(planCalId)}/events/${Uri.encodeComponent(block.externalEventId!)}',
        );
        res = await http.patch(uri, headers: headers, body: jsonEncode(body));
      } else {
        final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(planCalId)}/events',
        );
        res = await http.post(uri, headers: headers, body: jsonEncode(body));
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          final decoded = jsonDecode(res.body) as Map<String, dynamic>;
          final returnedId = decoded['id'] as String?;
          if (returnedId != null &&
              returnedId.isNotEmpty &&
              returnedId != block.externalEventId) {
            await DatabaseService.instance.updateScheduledBlock(
              block.copyWith(externalEventId: returnedId),
            );
          }
        } catch (_) {}
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ارسال رکوردهای زمانی کار و زندگی به تقویم گوگل (با ارث‌بری بازگشتی تقویم پروژه و PATCH بدون تکرار)
  Future<bool> syncTimeRecord(
    TimeRecord record, {
    required List<ProjectNode> projects,
  }) async {
    if (record.endTime == null) return false;
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) return false;

    String? effectiveProjectCalId = DatabaseService.getEffectiveGoogleCalendarId(
        record.projectId, projects);

    String targetCalId;
    if (effectiveProjectCalId != null && effectiveProjectCalId.isNotEmpty) {
      targetCalId = effectiveProjectCalId;
    } else if (record.isLife) {
      final lifeCal = await DatabaseService.instance
          .getSetting(AppDefaults.settingKeyLifeLogCalendarId);
      final legacyBreakCal = await DatabaseService.instance
          .getSetting(AppDefaults.settingKeyBreakLogCalendarId);
      targetCalId = (lifeCal != null && lifeCal.trim().isNotEmpty)
          ? lifeCal.trim()
          : ((legacyBreakCal != null && legacyBreakCal.trim().isNotEmpty)
              ? legacyBreakCal.trim()
              : 'primary');
    } else {
      final workCal = await DatabaseService.instance.getSetting(
        AppDefaults.settingKeyWorkLogCalendarId,
        defaultValue: 'primary',
      );
      targetCalId = (workCal != null && workCal.trim().isNotEmpty)
          ? workCal.trim()
          : 'primary';
    }

    final String prefix = record.isEdited ? '[Edited] ' : '';
    final String summary = '$prefix${record.title}';
    final desc = StringBuffer()
      ..writeln('ثبت‌شده توسط Mab-Focus v4.0')
      ..writeln('قلمرو: ${record.realm.labelFa}')
      ..writeln('حالت زمان‌سنج: ${record.clockMode.labelFa}')
      ..writeln(
          'مدت: ${(record.durationSeconds / 60).toStringAsFixed(1)} دقیقه');

    if (record.isWork && record.earnedBreakSeconds > 0) {
      desc.writeln(
          'استراحت استحقاقی کسب‌شده: ${(record.earnedBreakSeconds / 60).toStringAsFixed(1)} دقیقه');
    }
    if (record.isEdited) {
      desc.writeln(
        'زمان اولیه قبل از ویرایش: ${((record.originalDurationSeconds ?? record.durationSeconds) / 60).toStringAsFixed(1)} دقیقه',
      );
      if (record.editNote != null) desc.writeln('علت ویرایش: ${record.editNote}');
    }

    final body = {
      'summary': summary,
      'description': desc.toString(),
      'start': {'dateTime': record.startTime.toUtc().toIso8601String()},
      'end': {'dateTime': record.endTime!.toUtc().toIso8601String()},
    };

    try {
      final headers = {
        'Authorization': 'Bearer ${token.trim()}',
        'Content-Type': 'application/json',
      };

      // اگر تقویم مقصد تغییر کرده باشد (مثلاً سوییچ قلمرو پس از همگام‌سازی)، رویداد قبلی را حذف می‌کنیم
      String? existingEventId = record.calendarEventId;
      if (existingEventId != null &&
          existingEventId.isNotEmpty &&
          record.targetCalendarId != null &&
          record.targetCalendarId!.isNotEmpty &&
          record.targetCalendarId != targetCalId) {
        try {
          final deleteUri = Uri.parse(
            'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(record.targetCalendarId!)}/events/${Uri.encodeComponent(existingEventId)}',
          );
          await http.delete(deleteUri, headers: headers);
        } catch (_) {}
        existingEventId = null;
      }

      http.Response res;
      if (existingEventId != null && existingEventId.isNotEmpty) {
        final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(targetCalId)}/events/${Uri.encodeComponent(existingEventId)}',
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
        await DatabaseService.instance.updateTimeRecord(
          record.copyWith(
            syncStatus: 'synced',
            calendarEventId: eventId ?? existingEventId,
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
