import '../core/date_time_utils.dart';
import '../models/pomodoro_state.dart';
import '../models/project_node.dart';
import '../models/scheduled_block.dart';
import '../models/time_record.dart';
import 'database_service.dart';

class ProjectQuotaReport {
  final ProjectNode project;
  final int usedMinutes;
  final int quotaMinutes;
  final int varianceMinutes; // مثبت = مصرف مازاد، منفی = ظرفیت باقی‌مانده
  final double usageRatio;

  const ProjectQuotaReport({
    required this.project,
    required this.usedMinutes,
    required this.quotaMinutes,
    required this.varianceMinutes,
    required this.usageRatio,
  });
}

class TimeThiefIncident {
  final ScheduledBlock plannedBlock;
  final ProjectNode? plannedProject;
  final TimeRecord actualRecord;
  final ProjectNode? actualProject;
  final int stolenSeconds;
  final String reason;

  const TimeThiefIncident({
    required this.plannedBlock,
    this.plannedProject,
    required this.actualRecord,
    this.actualProject,
    required this.stolenSeconds,
    required this.reason,
  });
}

class TimeThiefAnalyzer {
  /// محاسبه مبدا هفته جاری (بامداد شنبه ساعت 00:00:00 به وقت محلی)
  static DateTime getStartOfCurrentWeek([DateTime? reference]) {
    return DateTimeUtils.startOfJalaliWeek(reference ?? DateTime.now());
  }

  /// محاسبه کارنامه سند ظرفیت هفتگی با تجمیع بازگشتی درخت پروژه‌ها (بدون شمارش تکراری)
  static List<ProjectQuotaReport> calculateWeeklyCapacityReport({
    required List<ProjectNode> projects,
    required List<TimeRecord> records,
    AppRealm? realmFilter,
    DateTime? referenceDate,
  }) {
    final startOfWeek =
        DateTimeUtils.startOfJalaliWeek(referenceDate ?? DateTime.now());
    final weeklyRecords =
        records.where((r) => !r.startTime.isBefore(startOfWeek)).toList();

    final List<ProjectQuotaReport> reports = [];

    for (final proj in projects) {
      if (proj.isArchived) continue;
      if (realmFilter != null && proj.realm != realmFilter) continue;

      final Set<String> familyIds =
          DatabaseService.getProjectAndDescendantIds(proj.id, projects);

      int totalUsedSeconds = 0;
      for (final rec in weeklyRecords) {
        if (rec.projectId != null &&
            familyIds.contains(rec.projectId) &&
            rec.realm == proj.realm) {
          totalUsedSeconds += rec.durationSeconds;
        }
      }

      if (proj.weeklyQuotaMinutes <= 0 && totalUsedSeconds == 0) {
        continue;
      }

      final usedMin = (totalUsedSeconds / 60).round();
      final quotaMin = proj.weeklyQuotaMinutes;
      final variance = usedMin - quotaMin;
      final ratio = quotaMin > 0 ? (usedMin / quotaMin) : 1.0;

      reports.add(
        ProjectQuotaReport(
          project: proj,
          usedMinutes: usedMin,
          quotaMinutes: quotaMin,
          varianceMinutes: variance,
          usageRatio: ratio,
        ),
      );
    }

    reports.sort((a, b) => b.usedMinutes.compareTo(a.usedMinutes));
    return reports;
  }

  /// الگوریتم تقاطع زمانی برای کشف سارقان زمان (با پشتیبانی از درخت بی‌نهایت سطحی و دو قلمرو کار/زندگی)
  static List<TimeThiefIncident> analyzeTimeThieves({
    required List<ScheduledBlock> plannedBlocks,
    required List<TimeRecord> actualRecords,
    required List<ProjectNode> projects,
    AppRealm? realmFilter,
  }) {
    final Map<String, ProjectNode> projectMap = {
      for (final p in projects) p.id: p
    };
    final Map<String, Set<String>> familyCache = {};
    final List<TimeThiefIncident> thieves = [];

    Set<String> familyOf(String projectId) {
      return familyCache.putIfAbsent(
        projectId,
        () => DatabaseService.getProjectAndDescendantIds(projectId, projects),
      );
    }

    for (final block in plannedBlocks) {
      if (realmFilter != null && block.realm != realmFilter) continue;

      final plannedProj =
          block.projectId != null ? projectMap[block.projectId] : null;
      final Set<String>? plannedFamily =
          block.projectId != null ? familyOf(block.projectId!) : null;

      for (final rec in actualRecords) {
        final recEnd = rec.endTime ??
            rec.startTime.add(Duration(seconds: rec.durationSeconds));

        // شرط تقاطع زمانی: max(B_start, R_start) < min(B_end, R_end)
        final overlapStart = rec.startTime.isAfter(block.startTime)
            ? rec.startTime
            : block.startTime;
        final overlapEnd =
            recEnd.isBefore(block.endTime) ? recEnd : block.endTime;

        if (overlapEnd.isAfter(overlapStart)) {
          final int overlapSeconds =
              overlapEnd.difference(overlapStart).inSeconds;
          if (overlapSeconds < 60) {
            continue;
          } // چشم‌پوشی از تداخل‌های زیر ۱ دقیقه

          final bool realmMatches = rec.realm == block.realm;
          final bool projectMatches = plannedFamily == null
              ? true
              : (rec.projectId != null &&
                  plannedFamily.contains(rec.projectId));
          final bool isMatching = realmMatches && projectMatches;

          if (!isMatching) {
            final actualProj =
                rec.projectId != null ? projectMap[rec.projectId] : null;
            String reason;
            if (block.isWork && rec.isLife) {
              reason =
                  'تداخل زمان زندگی/استراحت («${rec.title}») در ساعت کاری برنامه‌ریزی‌شده';
            } else if (block.isLife && rec.isWork) {
              reason =
                  'تداخل فعالیت کاری («${rec.title}») در زمان برنامه‌ریزی‌شده زندگی';
            } else if (actualProj != null) {
              reason =
                  'اختصاص زمان به پروژه دیگر (${actualProj.name}) به جای (${plannedProj?.name ?? block.title})';
            } else {
              reason =
                  'انجام فعالیت متفرقه («${rec.title}») در ساعت برنامه‌ریزی‌شده';
            }

            thieves.add(
              TimeThiefIncident(
                plannedBlock: block,
                plannedProject: plannedProj,
                actualRecord: rec,
                actualProject: actualProj,
                stolenSeconds: overlapSeconds,
                reason: reason,
              ),
            );
          }
        }
      }
    }

    thieves.sort((a, b) => b.stolenSeconds.compareTo(a.stolenSeconds));
    return thieves;
  }
}
