import 'dart:math' as math;

import '../models/outcome_item.dart';
import '../models/pomodoro_state.dart';
import '../models/project_node.dart';
import '../models/time_record.dart';
import 'database_service.dart';

class FilteredReportRecord {
  final TimeRecord record;
  final int clippedDurationSeconds;
  final int rawDurationSeconds;
  final DateTime effectiveStartTime;
  final DateTime effectiveEndTime;
  final bool isClipped;
  final bool isActive;
  final String? effectiveProjectId;
  final String resolvedTitle;
  final double effectiveHourlyRate;
  final double estimatedRevenue;

  const FilteredReportRecord({
    required this.record,
    required this.clippedDurationSeconds,
    required this.rawDurationSeconds,
    required this.effectiveStartTime,
    required this.effectiveEndTime,
    required this.isClipped,
    required this.isActive,
    required this.effectiveProjectId,
    required this.resolvedTitle,
    required this.effectiveHourlyRate,
    required this.estimatedRevenue,
  });
}

class ProjectReportBreakdown {
  final String? projectId; // null for unassigned bucket
  final String projectName;
  final String breadcrumb;
  final AppRealm? realm;
  final String colorHex;
  final int directSeconds;
  final int rollupSeconds;
  final int recordCount;
  final double estimatedRevenue;
  final double sharePercent;

  const ProjectReportBreakdown({
    required this.projectId,
    required this.projectName,
    required this.breadcrumb,
    required this.realm,
    required this.colorHex,
    required this.directSeconds,
    required this.rollupSeconds,
    required this.recordCount,
    required this.estimatedRevenue,
    required this.sharePercent,
  });

  bool get isUnassigned => projectId == null;
}

class MultiProjectReport {
  final int totalDurationSeconds;
  final int totalRecordCount;
  final double totalEstimatedRevenue;
  final int workSeconds;
  final int lifeSeconds;
  final List<FilteredReportRecord> filteredRecords;
  final List<ProjectReportBreakdown> projectBreakdowns;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final Set<String> selectedProjectIds;
  final bool includeDescendants;
  final bool includeUnassigned;
  final AppRealm? realmFilter;
  final ClockType? clockFilter;
  final bool isInvalidRange;

  const MultiProjectReport({
    required this.totalDurationSeconds,
    required this.totalRecordCount,
    required this.totalEstimatedRevenue,
    required this.workSeconds,
    required this.lifeSeconds,
    required this.filteredRecords,
    required this.projectBreakdowns,
    this.rangeStart,
    this.rangeEnd,
    this.selectedProjectIds = const {},
    this.includeDescendants = true,
    this.includeUnassigned = false,
    this.realmFilter,
    this.clockFilter,
    this.isInvalidRange = false,
  });
}

class ReportingService {
  const ReportingService._();

  static MultiProjectReport calculateReport({
    required List<TimeRecord> records,
    required List<ProjectNode> projects,
    required List<OutcomeItem> outcomes,
    Set<String> selectedProjectIds = const {},
    bool includeDescendants = true,
    bool includeUnassigned = false,
    DateTime? rangeStart,
    DateTime? rangeEnd,
    AppRealm? realmFilter,
    ClockType? clockFilter,
    bool onlyUntitled = false,
    String? activeRecordId,
    int activeRecordElapsedSeconds = 0,
  }) {
    final bool isInvalidRange =
        rangeStart != null && rangeEnd != null && rangeStart.isAfter(rangeEnd);

    if (rangeStart != null &&
        rangeEnd != null &&
        !rangeEnd.isAfter(rangeStart)) {
      return MultiProjectReport(
        totalDurationSeconds: 0,
        totalRecordCount: 0,
        totalEstimatedRevenue: 0.0,
        workSeconds: 0,
        lifeSeconds: 0,
        filteredRecords: const [],
        projectBreakdowns: const [],
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        selectedProjectIds: Set<String>.unmodifiable(selectedProjectIds),
        includeDescendants: includeDescendants,
        includeUnassigned: includeUnassigned,
        realmFilter: realmFilter,
        clockFilter: clockFilter,
        isInvalidRange: isInvalidRange,
      );
    }

    final Map<String, ProjectNode> projectMap = {
      for (final p in projects) p.id: p,
    };
    final Map<String, OutcomeItem> outcomeMap = {
      for (final o in outcomes) o.id: o,
    };

    Set<String>? allowedProjectIds;
    if (selectedProjectIds.isNotEmpty) {
      allowedProjectIds = <String>{};
      for (final pid in selectedProjectIds) {
        if (includeDescendants) {
          allowedProjectIds.addAll(
            DatabaseService.getProjectAndDescendantIds(pid, projects),
          );
        } else {
          allowedProjectIds.add(pid);
        }
      }
    }

    final List<FilteredReportRecord> filteredRecords = [];
    int totalDurationSeconds = 0;
    double totalEstimatedRevenue = 0.0;
    int workSeconds = 0;
    int lifeSeconds = 0;

    for (final rec in records) {
      if (realmFilter != null && rec.realm != realmFilter) continue;
      if (clockFilter != null && rec.clockMode != clockFilter) continue;
      if (onlyUntitled && !rec.isUntitledDraft) continue;

      final linkedOutcome =
          rec.outcomeId != null ? outcomeMap[rec.outcomeId] : null;
      final String? effectiveProjectId =
          rec.projectId ?? linkedOutcome?.projectId;

      if (allowedProjectIds != null) {
        final bool matchesProject = effectiveProjectId != null &&
            allowedProjectIds.contains(effectiveProjectId);
        final bool matchesUnassigned =
            effectiveProjectId == null && includeUnassigned;
        if (!matchesProject && !matchesUnassigned) continue;
      } else {
        final bool isOrphanProject = effectiveProjectId != null &&
            !projectMap.containsKey(effectiveProjectId);
        if (effectiveProjectId == null && !includeUnassigned) continue;
        if (isOrphanProject && !includeUnassigned) continue;
      }

      final bool isActive =
          activeRecordId != null && rec.id == activeRecordId;
      final int rawSec = isActive
          ? math.max(0, activeRecordElapsedSeconds)
          : math.max(0, rec.durationSeconds);

      final DateTime recStart = rec.startTime;
      final DateTime recEnd;
      if (isActive && rec.endTime == null) {
        recEnd = recStart.add(Duration(seconds: rawSec));
      } else if (rec.endTime != null) {
        recEnd = rec.endTime!.isBefore(recStart) ? recStart : rec.endTime!;
      } else {
        recEnd = recStart.add(Duration(seconds: rawSec));
      }

      final DateTime effectiveStart;
      final DateTime effectiveEnd;
      final bool isClipped;
      final int clippedSec;

      if (rangeStart == null && rangeEnd == null) {
        effectiveStart = recStart;
        effectiveEnd = recEnd;
        isClipped = false;
        clippedSec = rawSec;
      } else {
        final bool clippedStart =
            rangeStart != null && recStart.isBefore(rangeStart);
        final bool clippedEnd = rangeEnd != null && recEnd.isAfter(rangeEnd);
        effectiveStart = clippedStart ? rangeStart : recStart;
        effectiveEnd = clippedEnd ? rangeEnd : recEnd;

        if (!effectiveEnd.isAfter(effectiveStart)) continue;

        isClipped = clippedStart || clippedEnd;
        clippedSec = isClipped
            ? math.min(
                rawSec,
                effectiveEnd.difference(effectiveStart).inSeconds,
              )
            : rawSec;
        if (clippedSec <= 0) continue;
      }

      final String resolvedTitle =
          linkedOutcome?.title ?? rec.titleSnapshot;
      final double rate =
          DatabaseService.getEffectiveHourlyRate(effectiveProjectId, projects);
      final double revenue = (clippedSec / 3600.0) * rate;

      totalDurationSeconds += clippedSec;
      totalEstimatedRevenue += revenue;
      if (rec.isWork) {
        workSeconds += clippedSec;
      } else {
        lifeSeconds += clippedSec;
      }

      filteredRecords.add(
        FilteredReportRecord(
          record: rec,
          clippedDurationSeconds: clippedSec,
          rawDurationSeconds: rawSec,
          effectiveStartTime: effectiveStart,
          effectiveEndTime: effectiveEnd,
          isClipped: isClipped,
          isActive: isActive,
          effectiveProjectId: effectiveProjectId,
          resolvedTitle: resolvedTitle,
          effectiveHourlyRate: rate,
          estimatedRevenue: revenue,
        ),
      );
    }

    filteredRecords.sort(
      (a, b) => b.record.startTime.compareTo(a.record.startTime),
    );

    // Pre-group filtered records by effectiveProjectId for breakdown calculation.
    final Map<String?, List<FilteredReportRecord>> byProject = {};
    final List<FilteredReportRecord> unassignedRecords = [];

    for (final entry in filteredRecords) {
      byProject.putIfAbsent(entry.effectiveProjectId, () => []).add(entry);
      if (entry.effectiveProjectId == null ||
          (!projectMap.containsKey(entry.effectiveProjectId) &&
              selectedProjectIds.isEmpty)) {
        unassignedRecords.add(entry);
      }
    }

    final List<ProjectReportBreakdown> breakdowns = [];

    if (selectedProjectIds.isNotEmpty) {
      for (final pid in selectedProjectIds) {
        final proj = projectMap[pid];
        if (proj == null) {
          final directEntries = byProject[pid] ?? const <FilteredReportRecord>[];
          if (directEntries.isEmpty) continue;
          final int directSec = directEntries.fold<int>(
            0,
            (sum, e) => sum + e.clippedDurationSeconds,
          );
          final double rev = directEntries.fold<double>(
            0.0,
            (sum, e) => sum + e.estimatedRevenue,
          );
          final double share = totalDurationSeconds > 0
              ? (directSec / totalDurationSeconds) * 100.0
              : 0.0;
          breakdowns.add(
            ProjectReportBreakdown(
              projectId: pid,
              projectName: pid,
              breadcrumb: pid,
              realm: directEntries.first.record.realm,
              colorHex: '#6B7280',
              directSeconds: directSec,
              rollupSeconds: directSec,
              recordCount: directEntries.length,
              estimatedRevenue: rev,
              sharePercent: share,
            ),
          );
          continue;
        }

        final breakdown = _buildProjectBreakdown(
          proj: proj,
          projects: projects,
          byProject: byProject,
          includeDescendants: includeDescendants,
          totalDurationSeconds: totalDurationSeconds,
        );
        breakdowns.add(breakdown);
      }
    } else {
      for (final proj in projects) {
        if (realmFilter != null && proj.realm != realmFilter) continue;
        final breakdown = _buildProjectBreakdown(
          proj: proj,
          projects: projects,
          byProject: byProject,
          includeDescendants: includeDescendants,
          totalDurationSeconds: totalDurationSeconds,
        );
        if (breakdown.rollupSeconds > 0) {
          breakdowns.add(breakdown);
        }
      }
    }

    breakdowns.sort((a, b) {
      final byRollup = b.rollupSeconds.compareTo(a.rollupSeconds);
      if (byRollup != 0) return byRollup;
      return a.projectName.compareTo(b.projectName);
    });

    if (unassignedRecords.isNotEmpty) {
      final int unassignedSec = unassignedRecords.fold<int>(
        0,
        (sum, e) => sum + e.clippedDurationSeconds,
      );
      final double share = totalDurationSeconds > 0
          ? (unassignedSec / totalDurationSeconds) * 100.0
          : 0.0;
      breakdowns.add(
        ProjectReportBreakdown(
          projectId: null,
          projectName: 'بدون پروژه (آزاد)',
          breadcrumb: 'بدون پروژه (آزاد)',
          realm: realmFilter,
          colorHex: '#6B7280',
          directSeconds: unassignedSec,
          rollupSeconds: unassignedSec,
          recordCount: unassignedRecords.length,
          estimatedRevenue: 0.0,
          sharePercent: share,
        ),
      );
    }

    return MultiProjectReport(
      totalDurationSeconds: totalDurationSeconds,
      totalRecordCount: filteredRecords.length,
      totalEstimatedRevenue: totalEstimatedRevenue,
      workSeconds: workSeconds,
      lifeSeconds: lifeSeconds,
      filteredRecords: filteredRecords,
      projectBreakdowns: breakdowns,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      selectedProjectIds: Set<String>.unmodifiable(selectedProjectIds),
      includeDescendants: includeDescendants,
      includeUnassigned: includeUnassigned,
      realmFilter: realmFilter,
      clockFilter: clockFilter,
      isInvalidRange: false,
    );
  }

  static ProjectReportBreakdown _buildProjectBreakdown({
    required ProjectNode proj,
    required List<ProjectNode> projects,
    required Map<String?, List<FilteredReportRecord>> byProject,
    required bool includeDescendants,
    required int totalDurationSeconds,
  }) {
    final Set<String> scopeIds = includeDescendants
        ? DatabaseService.getProjectAndDescendantIds(proj.id, projects)
        : <String>{proj.id};

    final directEntries = byProject[proj.id] ?? const <FilteredReportRecord>[];
    final int directSeconds = directEntries.fold<int>(
      0,
      (sum, e) => sum + e.clippedDurationSeconds,
    );

    int rollupSeconds = 0;
    int recordCount = 0;
    double estimatedRevenue = 0.0;

    for (final sid in scopeIds) {
      final list = byProject[sid];
      if (list == null) continue;
      recordCount += list.length;
      for (final entry in list) {
        rollupSeconds += entry.clippedDurationSeconds;
        estimatedRevenue += entry.estimatedRevenue;
      }
    }

    final double sharePercent = totalDurationSeconds > 0
        ? (rollupSeconds / totalDurationSeconds) * 100.0
        : 0.0;
    final String breadcrumb =
        DatabaseService.getProjectBreadcrumb(proj.id, projects)
            .map((n) => n.name)
            .join(' > ');

    return ProjectReportBreakdown(
      projectId: proj.id,
      projectName: proj.name,
      breadcrumb: breadcrumb.isEmpty ? proj.name : breadcrumb,
      realm: proj.realm,
      colorHex: proj.colorHex,
      directSeconds: directSeconds,
      rollupSeconds: rollupSeconds,
      recordCount: recordCount,
      estimatedRevenue: estimatedRevenue,
      sharePercent: sharePercent,
    );
  }
}
