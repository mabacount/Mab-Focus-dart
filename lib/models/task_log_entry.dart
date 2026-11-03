// مدل لاگ کارکرد، فیلدهای ممیزی ویرایش [Edited] و وضعیت همگام‌سازی
import 'dart:convert';

class TaskLogEntry {
  final String id;
  final String title;
  final bool isUntitledDraft;
  final String? macroProjectId;
  final String? subProjectId;
  final List<String> tagIds;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds;
  final int overtimeSeconds;
  final int pomodoroSetIndex;

  // فیلدهای ممیزی ویرایش ([Edited])
  final bool isEdited;
  final DateTime? originalStartTime;
  final DateTime? originalEndTime;
  final int? originalDurationSeconds;
  final DateTime? editedAt;
  final String? editNote;

  // فیلدهای همگام‌سازی تقویم
  final String syncStatus; // 'pending' | 'synced' | 'failed'
  final String? calendarEventId;

  const TaskLogEntry({
    required this.id,
    this.title = 'تسک بدون عنوان',
    this.isUntitledDraft = true,
    this.macroProjectId,
    this.subProjectId,
    this.tagIds = const [],
    required this.startTime,
    this.endTime,
    this.durationSeconds = 0,
    this.overtimeSeconds = 0,
    this.pomodoroSetIndex = 1,
    this.isEdited = false,
    this.originalStartTime,
    this.originalEndTime,
    this.originalDurationSeconds,
    this.editedAt,
    this.editNote,
    this.syncStatus = 'pending',
    this.calendarEventId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'is_untitled_draft': isUntitledDraft ? 1 : 0,
      'macro_project_id': macroProjectId,
      'sub_project_id': subProjectId,
      'tag_ids_json': jsonEncode(tagIds),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'overtime_seconds': overtimeSeconds,
      'pomodoro_set_index': pomodoroSetIndex,
      'is_edited': isEdited ? 1 : 0,
      'original_start_time': originalStartTime?.toIso8601String(),
      'original_end_time': originalEndTime?.toIso8601String(),
      'original_duration_seconds': originalDurationSeconds,
      'edited_at': editedAt?.toIso8601String(),
      'edit_note': editNote,
      'sync_status': syncStatus,
      'calendar_event_id': calendarEventId,
    };
  }

  factory TaskLogEntry.fromMap(Map<String, dynamic> map) {
    List<String> parsedTagIds = [];
    if (map['tag_ids_json'] != null) {
      try {
        final decoded = jsonDecode(map['tag_ids_json'] as String);
        if (decoded is List) {
          parsedTagIds = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return TaskLogEntry(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'تسک بدون عنوان',
      isUntitledDraft: (map['is_untitled_draft'] as int? ?? 0) == 1,
      macroProjectId: map['macro_project_id'] as String?,
      subProjectId: map['sub_project_id'] as String?,
      tagIds: parsedTagIds,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      overtimeSeconds: map['overtime_seconds'] as int? ?? 0,
      pomodoroSetIndex: map['pomodoro_set_index'] as int? ?? 1,
      isEdited: (map['is_edited'] as int? ?? 0) == 1,
      originalStartTime: map['original_start_time'] != null
          ? DateTime.parse(map['original_start_time'] as String)
          : null,
      originalEndTime: map['original_end_time'] != null
          ? DateTime.parse(map['original_end_time'] as String)
          : null,
      originalDurationSeconds: map['original_duration_seconds'] as int?,
      editedAt: map['edited_at'] != null
          ? DateTime.parse(map['edited_at'] as String)
          : null,
      editNote: map['edit_note'] as String?,
      syncStatus: map['sync_status'] as String? ?? 'pending',
      calendarEventId: map['calendar_event_id'] as String?,
    );
  }

  TaskLogEntry copyWith({
    String? id,
    String? title,
    bool? isUntitledDraft,
    String? macroProjectId,
    String? subProjectId,
    List<String>? tagIds,
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    int? overtimeSeconds,
    int? pomodoroSetIndex,
    bool? isEdited,
    DateTime? originalStartTime,
    DateTime? originalEndTime,
    int? originalDurationSeconds,
    DateTime? editedAt,
    String? editNote,
    String? syncStatus,
    String? calendarEventId,
  }) {
    return TaskLogEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      isUntitledDraft: isUntitledDraft ?? this.isUntitledDraft,
      macroProjectId: macroProjectId ?? this.macroProjectId,
      subProjectId: subProjectId ?? this.subProjectId,
      tagIds: tagIds ?? this.tagIds,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      overtimeSeconds: overtimeSeconds ?? this.overtimeSeconds,
      pomodoroSetIndex: pomodoroSetIndex ?? this.pomodoroSetIndex,
      isEdited: isEdited ?? this.isEdited,
      originalStartTime: originalStartTime ?? this.originalStartTime,
      originalEndTime: originalEndTime ?? this.originalEndTime,
      originalDurationSeconds:
          originalDurationSeconds ?? this.originalDurationSeconds,
      editedAt: editedAt ?? this.editedAt,
      editNote: editNote ?? this.editNote,
      syncStatus: syncStatus ?? this.syncStatus,
      calendarEventId: calendarEventId ?? this.calendarEventId,
    );
  }
}
