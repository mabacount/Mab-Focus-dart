import 'dart:convert';

class WorkNoteEntry {
  final String id;
  final String? taskLogId;
  final String? projectId;
  final String taskTitle;
  final String content;
  final List<String> imagePaths;
  final DateTime createdAt;

  WorkNoteEntry({
    required this.id,
    this.taskLogId,
    this.projectId,
    required this.taskTitle,
    required this.content,
    required this.imagePaths,
    required this.createdAt,
  });

  WorkNoteEntry copyWith({
    String? id,
    String? taskLogId,
    String? projectId,
    String? taskTitle,
    String? content,
    List<String>? imagePaths,
    DateTime? createdAt,
  }) {
    return WorkNoteEntry(
      id: id ?? this.id,
      taskLogId: taskLogId ?? this.taskLogId,
      projectId: projectId ?? this.projectId,
      taskTitle: taskTitle ?? this.taskTitle,
      content: content ?? this.content,
      imagePaths: imagePaths ?? this.imagePaths,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_log_id': taskLogId,
      'project_id': projectId,
      'task_title': taskTitle,
      'content': content,
      'image_paths_json': jsonEncode(imagePaths),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory WorkNoteEntry.fromMap(Map<String, dynamic> map) {
    List<String> images = [];
    try {
      final decoded = jsonDecode(map['image_paths_json'] as String? ?? '[]');
      if (decoded is List) {
        images = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return WorkNoteEntry(
      id: map['id'] as String,
      taskLogId: map['task_log_id'] as String?,
      projectId: map['project_id'] as String?,
      taskTitle: map['task_title'] as String? ?? 'تسک بدون عنوان',
      content: map['content'] as String? ?? '',
      imagePaths: images,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
