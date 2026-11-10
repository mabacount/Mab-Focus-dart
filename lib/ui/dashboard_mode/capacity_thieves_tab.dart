import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/date_time_utils.dart';
import '../../core/jalali_date.dart';
import '../../models/pomodoro_state.dart';
import '../../providers/app_state_provider.dart';
import '../../services/time_thief_analyzer.dart';

class CapacityThievesTab extends StatefulWidget {
  const CapacityThievesTab({super.key});

  @override
  State<CapacityThievesTab> createState() => _CapacityThievesTabState();
}

class _CapacityThievesTabState extends State<CapacityThievesTab> {
  AppRealm? _realmFilter; // null = نمای ترکیبی کار و زندگی

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final palette = provider.activePalette;
    final startOfWeek = DateTimeUtils.startOfJalaliWeek(DateTime.now());

    final reports = TimeThiefAnalyzer.calculateWeeklyCapacityReport(
      projects: provider.projects,
      records: provider.timeRecords,
      realmFilter: _realmFilter,
    );
    final thieves = TimeThiefAnalyzer.analyzeTimeThieves(
      plannedBlocks: provider.scheduledBlocks,
      actualRecords: provider.timeRecords,
      projects: provider.projects,
      realmFilter: _realmFilter,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // بخش اول: بنر اطلاعات سند ظرفیت هفتگی + فیلتر دو قلمرو
          Card(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool isNarrow = constraints.maxWidth < 700;
                  final infoRow = Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: palette.accent.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet_outlined,
                          color: palette.accent,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'سند ظرفیت هفتگی (Life Capacity Document)',
                              style: TextStyle(
                                  fontSize: 15.5, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'مبدأ هفته جلالی: ${JalaliDate.formatWithWeekDayAndYear(startOfWeek)} (بامداد شنبه) — تجمیع بازگشتی درخت بدون شمارش تکراری',
                              softWrap: true,
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  final seg = SegmentedButton<AppRealm?>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      selectedBackgroundColor: palette.accent.withAlpha(45),
                      selectedForegroundColor: palette.accent,
                    ),
                    segments: const [
                      ButtonSegment(value: null, label: Text('نمای ترکیبی')),
                      ButtonSegment(
                          value: AppRealm.work, label: Text('پروژه‌های کار')),
                      ButtonSegment(
                          value: AppRealm.life, label: Text('پروژه‌های زندگی')),
                    ],
                    selected: {_realmFilter},
                    onSelectionChanged: (s) =>
                        setState(() => _realmFilter = s.first),
                  );
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        infoRow,
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: seg,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: infoRow),
                      const SizedBox(width: 14),
                      seg,
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // کارت‌های پیشرفت بودجه پروژه‌ها
          const Text('تراز بودجه زمانی پروژه‌ها در هفته جاری',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (reports.isEmpty)
            Card(
              color: palette.surface,
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'هنوز برای پروژه‌ها سهمیه هفتگی تعیین نشده یا فعالیتی در این هفته ثبت نگردیده است.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ),
            )
          else
            ...reports.map((rep) {
              final double ratio = rep.usageRatio.clamp(0.0, 1.0);
              final realmColor = rep.project.isLife
                  ? AppColors.lifeGreen
                  : AppColors.workBlue;
              Color barColor = realmColor;
              if (rep.varianceMinutes > 0) {
                barColor = Colors.redAccent;
              } else if (ratio >= 0.85) {
                barColor = AppColors.draftWarning;
              }

              final breadcrumb =
                  provider.getProjectBreadcrumbString(rep.project.id);

              return Card(
                color: palette.surface,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: palette.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: realmColor.withAlpha(32),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  rep.project.realm.labelFa,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: realmColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                breadcrumb.isNotEmpty
                                    ? breadcrumb
                                    : rep.project.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          Text(
                            rep.quotaMinutes > 0
                                ? 'مصرف: ${rep.usedMinutes} از ${rep.quotaMinutes} دقیقه (${rep.varianceMinutes > 0 ? "+${rep.varianceMinutes} سرریز" : "${rep.varianceMinutes.abs()} باقی‌مانده"})'
                                : 'مصرف: ${rep.usedMinutes} دقیقه (بدون سقف)',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5, color: barColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: ratio,
                        color: barColor,
                        backgroundColor: palette.surfaceElevated,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 20),

          // بخش دوم: رادار کشف سارقان زمان
          const Text('رادار کشف سارقان زمان (Time-Thief Radar)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'رکوردهای واقعی که در ساعت برنامه‌ریزی‌شده یک بلوک دیگر رخ داده‌اند (با احترام به سلسله‌مراتب زیرپروژه‌ها و جدایی کار/زندگی):',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),

          if (thieves.isEmpty)
            Card(
              color: palette.surface,
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'عالی! هیچ تداخل و سرقت زمانی در برنامه‌های ثبت‌شده مشاهده نشد.',
                    style: TextStyle(color: AppColors.lifeGreen),
                  ),
                ),
              ),
            )
          else
            Card(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: palette.border),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: thieves.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: palette.border),
                itemBuilder: (context, index) {
                  final t = thieves[index];
                  final minStolen = (t.stolenSeconds / 60).round();
                  final timeStr =
                      '${JalaliDate.formatWithWeekDay(t.actualRecord.startTime)} ${DateFormat('HH:mm').format(t.actualRecord.startTime)}';

                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber_rounded,
                        color: AppColors.draftWarning, size: 22),
                    title: Text(
                      'برنامه آسیب‌دیده: ${t.plannedProject?.name ?? t.plannedBlock.title} (${t.plannedBlock.realm.labelFa})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(
                      '${t.reason} • ثبت در $timeStr (زمان بلعیده‌شده: $minStolen دقیقه)',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: Text(
                      '-$minStolen min',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
