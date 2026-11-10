import 'dart:convert';
import 'package:flutter/material.dart';
import 'pomodoro_state.dart';

enum SessionNoteType { plan, challenge, report, idea, general }

extension SessionNoteTypeX on SessionNoteType {
  String get dbValue {
    switch (this) {
      case SessionNoteType.plan:
        return 'plan';
      case SessionNoteType.challenge:
        return 'challenge';
      case SessionNoteType.report:
        return 'report';
      case SessionNoteType.idea:
        return 'idea';
      case SessionNoteType.general:
        return 'general';
    }
  }

  String get labelFa {
    switch (this) {
      case SessionNoteType.plan:
        return 'برنامه';
      case SessionNoteType.challenge:
        return 'چالش';
      case SessionNoteType.report:
        return 'گزارش';
      case SessionNoteType.idea:
        return 'ایده';
      case SessionNoteType.general:
        return 'عمومی';
    }
  }

  Color get color {
    switch (this) {
      case SessionNoteType.plan:
        return const Color(0xFF3B82F6);
      case SessionNoteType.challenge:
        return const Color(0xFFFF5722);
      case SessionNoteType.report:
        return const Color(0xFF10B981);
      case SessionNoteType.idea:
        return const Color(0xFFFFB703);
      case SessionNoteType.general:
        return const Color(0xFF8B5CF6);
    }
  }

  IconData get icon {
    switch (this) {
      case SessionNoteType.plan:
        return Icons.route_rounded;
      case SessionNoteType.challenge:
        return Icons.warning_amber_rounded;
      case SessionNoteType.report:
        return Icons.fact_check_rounded;
      case SessionNoteType.idea:
        return Icons.lightbulb_outline_rounded;
      case SessionNoteType.general:
        return Icons.notes_rounded;
    }
  }

  static SessionNoteType fromDb(String? raw) {
    switch (raw) {
      case 'plan':
        return SessionNoteType.plan;
      case 'challenge':
        return SessionNoteType.challenge;
      case 'report':
        return SessionNoteType.report;
      case 'idea':
        return SessionNoteType.idea;
      default:
        return SessionNoteType.general;
    }
  }
}

/// یادداشت حین کار (SessionNote) با اتصال سه‌گانه به رکورد، کار/هدف و پروژه
class SessionNote {
  final String id;
  final AppRealm realm;
  final SessionNoteType noteType;
  final String? timeRecordId;
  final String? outcomeId;
  final String? projectId;
  final String content;
  final List<String> imagePaths;
  final DateTime createdAt;

  SessionNote({
    required this.id,
    this.realm = AppRealm.work,
    this.noteType = SessionNoteType.report,
    this.timeRecordId,
    this.outcomeId,
    this.projectId,
    required this.content,
    this.imagePaths = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  SessionNote copyWith({
    String? id,
    AppRealm? realm,
    SessionNoteType? noteType,
    String? timeRecordId,
    bool clearTimeRecordId = false,
    String? outcomeId,
    bool clearOutcomeId = false,
    String? projectId,
    bool clearProjectId = false,
    String? content,
    List<String>? imagePaths,
    DateTime? createdAt,
  }) {
    return SessionNote(
      id: id ?? this.id,
      realm: realm ?? this.realm,
      noteType: noteType ?? this.noteType,
      timeRecordId:
          clearTimeRecordId ? null : (timeRecordId ?? this.timeRecordId),
      outcomeId: clearOutcomeId ? null : (outcomeId ?? this.outcomeId),
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      content: content ?? this.content,
      imagePaths: imagePaths ?? this.imagePaths,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'realm': realm.dbValue,
      'note_type': noteType.dbValue,
      'time_record_id': timeRecordId,
      'outcome_id': outcomeId,
      'project_id': projectId,
      'content': content,
      'image_paths_json': jsonEncode(imagePaths),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SessionNote.fromMap(Map<String, dynamic> map) {
    List<String> images = [];
    try {
      final decoded = jsonDecode(map['image_paths_json'] as String? ?? '[]');
      if (decoded is List) {
        images = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return SessionNote(
      id: map['id'] as String,
      realm: AppRealmX.fromDb(map['realm'] as String?),
      noteType: SessionNoteTypeX.fromDb(map['note_type'] as String?),
      timeRecordId: map['time_record_id'] as String?,
      outcomeId: map['outcome_id'] as String?,
      projectId: map['project_id'] as String?,
      content: map['content'] as String? ?? '',
      imagePaths: images,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
