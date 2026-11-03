import '../models/project_node.dart';
import '../models/task_log_entry.dart';
import '../models/scheduled_block.dart';

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
  final TaskLogEntry actualLog;
  final ProjectNode? actualProject;
  final int stolenSeconds;
  final String reason;

  const TimeThiefIncident({
    required this.plannedBlock,
    this.plannedProject,
    required this.actualLog,
    this.actualProject,
    required this.stolenSeconds,
    required this.reason,
  });
}

class TimeThiefAnalyzer {
  /// محاسبه مبدا هفته جاری (بامداد شنبه ساعت 00:00:00)
  static DateTime getStartOfCurrentWeek([DateTime? reference]) {
    final now = (reference ?? DateTime.now()).toLocal();
    // در دارت: دوشنبه=1 ... جمعه=5، شنبه=6، یکشنبه=7
    final int daysSinceSaturday = (now.weekday % 7 + 1) % 7;
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: daysSinceSaturday));
  }

  /// محاسبه کارنامه سند ظرفیت هفتگی
  static List<ProjectQuotaReport> calculateWeeklyCapacityReport({
    required List<ProjectNode> projects,
    required List<TaskLogEntry> logs,
    DateTime? referenceDate,
  }) {
    final startOfWeek = getStartOfCurrentWeek(referenceDate);
    final weeklyLogs =
        logs.where((l) => l.startTime.isAfter(startOfWeek)).toList();

    final Map<String, ProjectNode> projectMap = {
      for (final p in projects) p.id: p
    };
    final Map<String, int> projectUsedSeconds = {};

    for (final log in weeklyLogs) {
      if (log.isBreakEntry) {
        // اگر استراحت به پروژه‌ای متصل است، بررسی قوانین استراحت
        if (log.macroProjectId != null) {
          final macro = projectMap[log.macroProjectId];
          if (macro != null) {
            final countBreak = log.entryType == 'long_break'
                ? macro.countLongBreaksAsWork
                : macro.countShortBreaksAsWork;
            if (countBreak) {
              projectUsedSeconds[macro.id] =
                  (projectUsedSeconds[macro.id] ?? 0) + log.durationSeconds;
            }
          }
        }
        continue;
      }

      final targetId = log.subProjectId ?? log.macroProjectId;
      if (targetId != null) {
        projectUsedSeconds[targetId] =
            (projectUsedSeconds[targetId] ?? 0) + log.durationSeconds;

        // اگر زیرپروژه بود، به پروژه کلان مادر هم اضافه می‌شود
        if (log.subProjectId != null && log.macroProjectId != null) {
          projectUsedSeconds[log.macroProjectId!] =
              (projectUsedSeconds[log.macroProjectId!] ?? 0) +
                  log.durationSeconds;
        }
      }
    }

    final List<ProjectQuotaReport> reports = [];
    for (final proj in projects) {
      if (proj.weeklyQuotaMinutes <= 0 &&
          (projectUsedSeconds[proj.id] ?? 0) == 0) {
        continue;
      }
      final usedMin = ((projectUsedSeconds[proj.id] ?? 0) / 60).round();
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

  /// الگوریتم تقاطع زمانی برای کشف سارقان زمان
  static List<TimeThiefIncident> analyzeTimeThieves({
    required List<ScheduledBlock> plannedBlocks,
    required List<TaskLogEntry> actualLogs,
    required List<ProjectNode> projects,
  }) {
    final Map<String, ProjectNode> projectMap = {
      for (final p in projects) p.id: p
    };
    final List<TimeThiefIncident> thieves = [];

    for (final block in plannedBlocks) {
      final plannedProj =
          block.projectId != null ? projectMap[block.projectId] : null;

      for (final log in actualLogs) {
        final logEnd = log.endTime ??
            log.startTime.add(Duration(seconds: log.durationSeconds));

        // شرط تقاطع زمانی: max(B_start, L_start) < min(B_end, L_end)
        final overlapStart = log.startTime.isAfter(block.startTime)
            ? log.startTime
            : block.startTime;
        final overlapEnd =
            logEnd.isBefore(block.endTime) ? logEnd : block.endTime;

        if (overlapEnd.isAfter(overlapStart)) {
          final int overlapSeconds =
              overlapEnd.difference(overlapStart).inSeconds;
          if (overlapSeconds < 60) {
            continue;
          } // چشم‌پوشی از تداخل‌های زیر ۱ دقیقه

          final actualEffectiveProjId = log.subProjectId ?? log.macroProjectId;
          final bool isMatchingProject = block.projectId != null &&
              (actualEffectiveProjId == block.projectId ||
                  log.macroProjectId == block.projectId);

          // اگر کار انجام‌شده با برنامه هم‌خوانی نداشت، سرقت زمان رخ داده است
          if (!isMatchingProject || log.isBreakEntry) {
            final actualProj = actualEffectiveProjId != null
                ? projectMap[actualEffectiveProjId]
                : null;
            String reason;
            if (log.isBreakEntry) {
              reason = 'تداخل زمان استراحت در ساعت کاری برنامه‌ریزی‌شده';
            } else if (actualProj != null) {
              reason =
                  'اختصاص زمان به پروژه دیگر (${actualProj.name}) به جای (${plannedProj?.name ?? "برنامه"})';
            } else {
              reason =
                  'انجام تسک متفرقه (${log.title}) در ساعت برنامه‌ریزی‌شده';
            }

            thieves.add(
              TimeThiefIncident(
                plannedBlock: block,
                plannedProject: plannedProj,
                actualLog: log,
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
