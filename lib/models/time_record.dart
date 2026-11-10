import 'dart:convert';
import '../core/constants.dart';
import 'pomodoro_state.dart';

/// رکورد زمانی (TimeRecord): یک برش زمانی پیوسته از فعالیت در قلمرو کار یا زندگی
class TimeRecord {
  final String id;
  final AppRealm realm;
  final ClockType clockMode;
  final String? outcomeId;
  final String? projectId;
  final String titleSnapshot;
  final bool isUntitledDraft;
  final List<String> tagIds;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds;
  final int overtimeSeconds;
  final int earnedBreakSeconds;

  // فیلدهای ممیزی ویرایش
  final bool isEdited;
  final DateTime? originalStartTime;
  final DateTime? originalEndTime;
  final int? originalDurationSeconds;
  final DateTime? editedAt;
  final String? editNote;

  // فیلدهای همگام‌سازی تقویم گوگل
  final String syncStatus; // 'pending' | 'synced' | 'failed'
  final String? calendarEventId;
  final String? targetCalendarId;

  const TimeRecord({
    required this.id,
    this.realm = AppRealm.work,
    this.clockMode = ClockType.pomodoro,
    this.outcomeId,
    this.projectId,
    this.titleSnapshot = AppDefaults.untitledTaskTitle,
    this.isUntitledDraft = true,
    this.tagIds = const [],
    required this.startTime,
    this.endTime,
    this.durationSeconds = 0,
    this.overtimeSeconds = 0,
    this.earnedBreakSeconds = 0,
    this.isEdited = false,
    this.originalStartTime,
    this.originalEndTime,
    this.originalDurationSeconds,
    this.editedAt,
    this.editNote,
    this.syncStatus = 'pending',
    this.calendarEventId,
    this.targetCalendarId,
  });

  bool get isWork => realm == AppRealm.work;
  bool get isLife => realm == AppRealm.life;
  bool get isStopwatch => clockMode == ClockType.stopwatch;
  bool get isPomodoro => clockMode == ClockType.pomodoro;
  bool get isOpen => endTime == null;
  String get title => titleSnapshot;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'realm': realm.dbValue,
      'clock_mode': clockMode.dbValue,
      'outcome_id': outcomeId,
      'project_id': projectId,
      'title_snapshot': titleSnapshot,
      'is_untitled_draft': isUntitledDraft ? 1 : 0,
      'tag_ids_json': jsonEncode(tagIds),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'overtime_seconds': overtimeSeconds,
      'earned_break_seconds': earnedBreakSeconds,
      'is_edited': isEdited ? 1 : 0,
      'original_start_time': originalStartTime?.toIso8601String(),
      'original_end_time': originalEndTime?.toIso8601String(),
      'original_duration_seconds': originalDurationSeconds,
      'edited_at': editedAt?.toIso8601String(),
      'edit_note': editNote,
      'sync_status': syncStatus,
      'calendar_event_id': calendarEventId,
      'target_calendar_id': targetCalendarId,
    };
  }

  factory TimeRecord.fromMap(Map<String, dynamic> map) {
    List<String> parsedTags = [];
    if (map['tag_ids_json'] != null) {
      try {
        final decoded = jsonDecode(map['tag_ids_json'] as String);
        if (decoded is List) {
          parsedTags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return TimeRecord(
      id: map['id'] as String,
      realm: AppRealmX.fromDb(map['realm'] as String?),
      clockMode: ClockTypeX.fromDb(map['clock_mode'] as String?),
      outcomeId: map['outcome_id'] as String?,
      projectId: map['project_id'] as String?,
      titleSnapshot:
          map['title_snapshot'] as String? ?? AppDefaults.untitledTaskTitle,
      isUntitledDraft: (map['is_untitled_draft'] as int? ?? 0) == 1,
      tagIds: parsedTags,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.tryParse(map['end_time'] as String)
          : null,
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      overtimeSeconds: map['overtime_seconds'] as int? ?? 0,
      earnedBreakSeconds: map['earned_break_seconds'] as int? ?? 0,
      isEdited: (map['is_edited'] as int? ?? 0) == 1,
      originalStartTime: map['original_start_time'] != null
          ? DateTime.tryParse(map['original_start_time'] as String)
          : null,
      originalEndTime: map['original_end_time'] != null
          ? DateTime.tryParse(map['original_end_time'] as String)
          : null,
      originalDurationSeconds: map['original_duration_seconds'] as int?,
      editedAt: map['edited_at'] != null
          ? DateTime.tryParse(map['edited_at'] as String)
          : null,
      editNote: map['edit_note'] as String?,
      syncStatus: map['sync_status'] as String? ?? 'pending',
      calendarEventId: map['calendar_event_id'] as String?,
      targetCalendarId: map['target_calendar_id'] as String?,
    );
  }

  TimeRecord copyWith({
    String? id,
    AppRealm? realm,
    ClockType? clockMode,
    String? outcomeId,
    bool clearOutcomeId = false,
    String? projectId,
    bool clearProjectId = false,
    String? titleSnapshot,
    bool? isUntitledDraft,
    List<String>? tagIds,
    DateTime? startTime,
    DateTime? endTime,
    bool clearEndTime = false,
    int? durationSeconds,
    int? overtimeSeconds,
    int? earnedBreakSeconds,
    bool? isEdited,
    DateTime? originalStartTime,
    DateTime? originalEndTime,
    int? originalDurationSeconds,
    DateTime? editedAt,
    String? editNote,
    String? syncStatus,
    String? calendarEventId,
    bool clearCalendarEventId = false,
    String? targetCalendarId,
  }) {
    return TimeRecord(
      id: id ?? this.id,
      realm: realm ?? this.realm,
      clockMode: clockMode ?? this.clockMode,
      outcomeId: clearOutcomeId ? null : (outcomeId ?? this.outcomeId),
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      titleSnapshot: titleSnapshot ?? this.titleSnapshot,
      isUntitledDraft: isUntitledDraft ?? this.isUntitledDraft,
      tagIds: tagIds ?? this.tagIds,
      startTime: startTime ?? this.startTime,
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      durationSeconds: durationSeconds ?? this.durationSeconds,
      overtimeSeconds: overtimeSeconds ?? this.overtimeSeconds,
      earnedBreakSeconds: earnedBreakSeconds ?? this.earnedBreakSeconds,
      isEdited: isEdited ?? this.isEdited,
      originalStartTime: originalStartTime ?? this.originalStartTime,
      originalEndTime: originalEndTime ?? this.originalEndTime,
      originalDurationSeconds:
          originalDurationSeconds ?? this.originalDurationSeconds,
      editedAt: editedAt ?? this.editedAt,
      editNote: editNote ?? this.editNote,
      syncStatus: syncStatus ?? this.syncStatus,
      calendarEventId: clearCalendarEventId
          ? null
          : (calendarEventId ?? this.calendarEventId),
      targetCalendarId: targetCalendarId ?? this.targetCalendarId,
    );
  }
}
