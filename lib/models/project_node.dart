import 'pomodoro_state.dart';

class ProjectNode {
  final String id;
  final AppRealm realm;
  final String name;
  final String? parentId; // NULL برای پروژه‌های ریشه؛ ساختار درختی بی‌نهایت سطحی
  final String status; // 'active' | 'suspended' | 'archived'
  final String colorHex;
  final int dailyQuotaMinutes;
  final int weeklyQuotaMinutes;
  final int monthlyQuotaMinutes;
  final double hourlyRate;
  final String? googleCalendarId;
  final DateTime createdAt;

  ProjectNode({
    required this.id,
    this.realm = AppRealm.work,
    required this.name,
    this.parentId,
    this.status = 'active',
    String? colorHex,
    this.dailyQuotaMinutes = 0,
    this.weeklyQuotaMinutes = 0,
    this.monthlyQuotaMinutes = 0,
    this.hourlyRate = 0.0,
    this.googleCalendarId,
    DateTime? createdAt,
  })  : colorHex = colorHex ?? (realm == AppRealm.life ? '#10B981' : '#3B82F6'),
        createdAt = createdAt ?? DateTime.now();

  bool get isActive => status == 'active';
  bool get isSuspended => status == 'suspended';
  bool get isArchived => status == 'archived';
  bool get isRoot => parentId == null;
  bool get isWork => realm == AppRealm.work;
  bool get isLife => realm == AppRealm.life;

  /// تشخیص پروژه خواب برای ریست خودکار چرخه Flowmodoro (چالش ۱)
  bool get isSleepProject {
    final lower = name.trim().toLowerCase();
    return lower.contains('خواب') || lower.contains('sleep');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'realm': realm.dbValue,
      'name': name,
      'parent_id': parentId,
      'status': status,
      'color': colorHex,
      'daily_quota_minutes': dailyQuotaMinutes,
      'weekly_quota_minutes': weeklyQuotaMinutes,
      'monthly_quota_minutes': monthlyQuotaMinutes,
      'hourly_rate': hourlyRate,
      'google_calendar_id': googleCalendarId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ProjectNode.fromMap(Map<String, dynamic> map) {
    final realm = AppRealmX.fromDb(map['realm'] as String?);
    return ProjectNode(
      id: map['id'] as String,
      realm: realm,
      name: map['name'] as String,
      parentId: map['parent_id'] as String?,
      status: map['status'] as String? ?? 'active',
      colorHex: (map['color'] ??
          map['colorHex'] ??
          (realm == AppRealm.life ? '#10B981' : '#3B82F6')) as String,
      dailyQuotaMinutes: map['daily_quota_minutes'] as int? ?? 0,
      weeklyQuotaMinutes: map['weekly_quota_minutes'] as int? ?? 0,
      monthlyQuotaMinutes: map['monthly_quota_minutes'] as int? ?? 0,
      hourlyRate: (map['hourly_rate'] as num? ?? 0.0).toDouble(),
      googleCalendarId: map['google_calendar_id'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ProjectNode copyWith({
    String? id,
    AppRealm? realm,
    String? name,
    String? parentId,
    bool clearParentId = false,
    String? status,
    String? colorHex,
    int? dailyQuotaMinutes,
    int? weeklyQuotaMinutes,
    int? monthlyQuotaMinutes,
    double? hourlyRate,
    String? googleCalendarId,
    bool clearGoogleCalendarId = false,
    DateTime? createdAt,
  }) {
    return ProjectNode(
      id: id ?? this.id,
      realm: realm ?? this.realm,
      name: name ?? this.name,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      status: status ?? this.status,
      colorHex: colorHex ?? this.colorHex,
      dailyQuotaMinutes: dailyQuotaMinutes ?? this.dailyQuotaMinutes,
      weeklyQuotaMinutes: weeklyQuotaMinutes ?? this.weeklyQuotaMinutes,
      monthlyQuotaMinutes: monthlyQuotaMinutes ?? this.monthlyQuotaMinutes,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      googleCalendarId: clearGoogleCalendarId
          ? null
          : (googleCalendarId ?? this.googleCalendarId),
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
