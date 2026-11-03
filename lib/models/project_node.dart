// مدل پروژه‌های کلان، زیرپروژه‌ها و تنظیمات احتساب استراحت
class ProjectNode {
  final String id;
  final String name;
  final String? parentId; // null یعنی پروژه کلان؛ در غیر این صورت زیرپروژه است
  final bool countShortBreaksAsWork; // محاسبه استراحت ۵ دقیقه‌ای جزو ساعت کاری
  final bool countLongBreaksAsWork; // محاسبه استراحت ۶۰ دقیقه‌ای جزو ساعت کاری
  final String colorHex;
  final bool archived;

  const ProjectNode({
    required this.id,
    required this.name,
    this.parentId,
    this.countShortBreaksAsWork = false,
    this.countLongBreaksAsWork = false,
    this.colorHex = '#3B82F6',
    this.archived = false,
  });

  bool get isMacro => parentId == null;
  bool get isSubProject => parentId != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'count_short_breaks_as_work': countShortBreaksAsWork ? 1 : 0,
      'count_long_breaks_as_work': countLongBreaksAsWork ? 1 : 0,
      'color': colorHex,
      'archived': archived ? 1 : 0,
    };
  }

  factory ProjectNode.fromMap(Map<String, dynamic> map) {
    return ProjectNode(
      id: map['id'] as String,
      name: map['name'] as String,
      parentId: map['parent_id'] as String?,
      countShortBreaksAsWork:
          (map['count_short_breaks_as_work'] as int? ?? 0) == 1,
      countLongBreaksAsWork:
          (map['count_long_breaks_as_work'] as int? ?? 0) == 1,
      colorHex: (map['color'] ?? map['colorHex'] ?? '#3B82F6') as String,
      archived: (map['archived'] as int? ?? 0) == 1,
    );
  }

  ProjectNode copyWith({
    String? id,
    String? name,
    String? parentId,
    bool? countShortBreaksAsWork,
    bool? countLongBreaksAsWork,
    String? colorHex,
    bool? archived,
  }) {
    return ProjectNode(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      countShortBreaksAsWork:
          countShortBreaksAsWork ?? this.countShortBreaksAsWork,
      countLongBreaksAsWork:
          countLongBreaksAsWork ?? this.countLongBreaksAsWork,
      colorHex: colorHex ?? this.colorHex,
      archived: archived ?? this.archived,
    );
  }
}
