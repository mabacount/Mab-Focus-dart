import 'pomodoro_state.dart';

/// کار / هدف (OutcomeItem): نتیجه ملموس در قلمرو کار یا زندگی
class OutcomeItem {
  final String id;
  final AppRealm realm;
  final String? projectId;
  final String title;
  final String description;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime? completedAt;

  OutcomeItem({
    required this.id,
    this.realm = AppRealm.work,
    this.projectId,
    required this.title,
    this.description = '',
    this.isCompleted = false,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isOpen => !isCompleted;
  bool get isWork => realm == AppRealm.work;
  bool get isLife => realm == AppRealm.life;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'realm': realm.dbValue,
      'project_id': projectId,
      'title': title,
      'description': description,
      'is_completed': isCompleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  factory OutcomeItem.fromMap(Map<String, dynamic> map) {
    return OutcomeItem(
      id: map['id'] as String,
      realm: AppRealmX.fromDb(map['realm'] as String?),
      projectId: map['project_id'] as String?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'] as String)
          : null,
    );
  }

  OutcomeItem copyWith({
    String? id,
    AppRealm? realm,
    String? projectId,
    bool clearProjectId = false,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return OutcomeItem(
      id: id ?? this.id,
      realm: realm ?? this.realm,
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }
}
