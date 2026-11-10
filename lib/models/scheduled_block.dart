import 'pomodoro_state.dart';

class ScheduledBlock {
  final String id;
  final AppRealm realm;
  final String title;
  final String? projectId;
  final String? outcomeId;
  final DateTime startTime;
  final DateTime endTime;
  final bool isRecurringWeekly;
  final int? weekday; // 1 (دوشنبه) تا 7 (یکشنبه)
  final String source; // 'local' | 'gcal'
  final String? externalEventId;

  const ScheduledBlock({
    required this.id,
    this.realm = AppRealm.work,
    required this.title,
    this.projectId,
    this.outcomeId,
    required this.startTime,
    required this.endTime,
    this.isRecurringWeekly = false,
    this.weekday,
    this.source = 'local',
    this.externalEventId,
  });

  int get plannedDurationSeconds => endTime.difference(startTime).inSeconds;
  bool get isWork => realm == AppRealm.work;
  bool get isLife => realm == AppRealm.life;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'realm': realm.dbValue,
      'title': title,
      'project_id': projectId,
      'outcome_id': outcomeId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'is_recurring_weekly': isRecurringWeekly ? 1 : 0,
      'weekday': weekday,
      'source': source,
      'external_event_id': externalEventId,
    };
  }

  factory ScheduledBlock.fromMap(Map<String, dynamic> map) {
    return ScheduledBlock(
      id: map['id'] as String,
      realm: AppRealmX.fromDb(map['realm'] as String?),
      title: map['title'] as String,
      projectId: map['project_id'] as String?,
      outcomeId: map['outcome_id'] as String?,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: DateTime.parse(map['end_time'] as String),
      isRecurringWeekly: (map['is_recurring_weekly'] as int? ?? 0) == 1,
      weekday: map['weekday'] as int?,
      source: map['source'] as String? ?? 'local',
      externalEventId: map['external_event_id'] as String?,
    );
  }

  ScheduledBlock copyWith({
    String? id,
    AppRealm? realm,
    String? title,
    String? projectId,
    bool clearProjectId = false,
    String? outcomeId,
    bool clearOutcomeId = false,
    DateTime? startTime,
    DateTime? endTime,
    bool? isRecurringWeekly,
    int? weekday,
    String? source,
    String? externalEventId,
  }) {
    return ScheduledBlock(
      id: id ?? this.id,
      realm: realm ?? this.realm,
      title: title ?? this.title,
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      outcomeId: clearOutcomeId ? null : (outcomeId ?? this.outcomeId),
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isRecurringWeekly: isRecurringWeekly ?? this.isRecurringWeekly,
      weekday: weekday ?? this.weekday,
      source: source ?? this.source,
      externalEventId: externalEventId ?? this.externalEventId,
    );
  }
}
