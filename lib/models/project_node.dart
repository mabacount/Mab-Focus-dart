class ProjectNode {
  final String id;
  final String name;
  final String? parentId;
  final String status; // 'active' | 'suspended' | 'archived'
  final String colorHex;
  final bool countShortBreaksAsWork;
  final bool countLongBreaksAsWork;
  final int dailyQuotaMinutes;
  final int weeklyQuotaMinutes;
  final int monthlyQuotaMinutes;
  final double hourlyRate;
  final String? googleCalendarId;

  const ProjectNode({
    required this.id,
    required this.name,
    this.parentId,
    this.status = 'active',
    this.colorHex = '#3B82F6',
    this.countShortBreaksAsWork = false,
    this.countLongBreaksAsWork = false,
    this.dailyQuotaMinutes = 0,
    this.weeklyQuotaMinutes = 0,
    this.monthlyQuotaMinutes = 0,
    this.hourlyRate = 0.0,
    this.googleCalendarId,
  });

  bool get isActive => status == 'active';
  bool get isSuspended => status == 'suspended';
  bool get isArchived => status == 'archived';
  bool get isMacro => parentId == null;
  bool get isSubProject => parentId != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'status': status,
      'color': colorHex,
      'count_short_breaks_as_work': countShortBreaksAsWork ? 1 : 0,
      'count_long_breaks_as_work': countLongBreaksAsWork ? 1 : 0,
      'daily_quota_minutes': dailyQuotaMinutes,
      'weekly_quota_minutes': weeklyQuotaMinutes,
      'monthly_quota_minutes': monthlyQuotaMinutes,
      'hourly_rate': hourlyRate,
      'google_calendar_id': googleCalendarId,
    };
  }

  factory ProjectNode.fromMap(Map<String, dynamic> map) {
    return ProjectNode(
      id: map['id'] as String,
      name: map['name'] as String,
      parentId: map['parent_id'] as String?,
      status: map['status'] as String? ?? 'active',
      colorHex: (map['color'] ?? map['colorHex'] ?? '#3B82F6') as String,
      countShortBreaksAsWork:
          (map['count_short_breaks_as_work'] as int? ?? 0) == 1,
      countLongBreaksAsWork:
          (map['count_long_breaks_as_work'] as int? ?? 0) == 1,
      dailyQuotaMinutes: map['daily_quota_minutes'] as int? ?? 0,
      weeklyQuotaMinutes: map['weekly_quota_minutes'] as int? ?? 0,
      monthlyQuotaMinutes: map['monthly_quota_minutes'] as int? ?? 0,
      hourlyRate: (map['hourly_rate'] as num? ?? 0.0).toDouble(),
      googleCalendarId: map['google_calendar_id'] as String?,
    );
  }

  ProjectNode copyWith({
    String? id,
    String? name,
    String? parentId,
    String? status,
    String? colorHex,
    bool? countShortBreaksAsWork,
    bool? countLongBreaksAsWork,
    int? dailyQuotaMinutes,
    int? weeklyQuotaMinutes,
    int? monthlyQuotaMinutes,
    double? hourlyRate,
    String? googleCalendarId,
  }) {
    return ProjectNode(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      status: status ?? this.status,
      colorHex: colorHex ?? this.colorHex,
      countShortBreaksAsWork:
          countShortBreaksAsWork ?? this.countShortBreaksAsWork,
      countLongBreaksAsWork:
          countLongBreaksAsWork ?? this.countLongBreaksAsWork,
      dailyQuotaMinutes: dailyQuotaMinutes ?? this.dailyQuotaMinutes,
      weeklyQuotaMinutes: weeklyQuotaMinutes ?? this.weeklyQuotaMinutes,
      monthlyQuotaMinutes: monthlyQuotaMinutes ?? this.monthlyQuotaMinutes,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      googleCalendarId: googleCalendarId ?? this.googleCalendarId,
    );
  }
}
