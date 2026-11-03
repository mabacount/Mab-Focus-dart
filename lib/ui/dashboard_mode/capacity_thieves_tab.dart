import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../providers/app_state_provider.dart';
import '../../services/time_thief_analyzer.dart';

class CapacityThievesTab extends StatelessWidget {
  const CapacityThievesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final startOfWeek = TimeThiefAnalyzer.getStartOfCurrentWeek();
    final reports = TimeThiefAnalyzer.calculateWeeklyCapacityReport(
      projects: provider.projects,
      logs: provider.taskLogs,
    );
    final thieves = TimeThiefAnalyzer.analyzeTimeThieves(
      plannedBlocks: provider.scheduledBlocks,
      actualLogs: provider.taskLogs,
      projects: provider.projects,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // بخش اول: بنر اطلاعات سند ظرفیت هفتگی
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.focus.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        color: AppColors.focus, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'سند ظرفیت هفتگی (Life Capacity Document)',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'مبدأ هفته جاری: ${DateFormat('yyyy/MM/dd | بامداد شنبه').format(startOfWeek)} — ظرفیت‌های هفتگی در ابتدای هر هفته صفر می‌شوند.',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // کارت‌های پیشرفت بودجه پروژه‌ها
          const Text('تراز بودجه زمانی پروژه‌ها در هفته جاری',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (reports.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                      'هنوز برای پروژه‌ها بودجه هفتگی تعیین نشده یا فعالیتی در این هفته ثبت نگردیده است.',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              ),
            )
          else
            ...reports.map((rep) {
              final double ratio = rep.usageRatio.clamp(0.0, 1.0);
              Color barColor = AppColors.focus;
              if (rep.varianceMinutes > 0) {
                barColor = Colors.redAccent;
              } else if (ratio >= 0.8) {
                barColor = AppColors.breakTime;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(rep.project.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13.5)),
                          Text(
                            'مصرف: ${rep.usedMinutes} دقیقه از ${rep.quotaMinutes} دقیقه بودجه '
                            '(${rep.varianceMinutes > 0 ? "+${rep.varianceMinutes} سرریز" : "${rep.varianceMinutes} باقی‌مانده"})',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 12, color: barColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: ratio,
                        color: barColor,
                        backgroundColor: AppColors.surfaceElevated,
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
            'فعالیت‌ها یا استراحت‌هایی که در ساعت برنامه‌ریزی‌شده یک پروژه رخ داده و وقت آن را بلعیده‌اند:',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),

          if (thieves.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                      'عالی! هیچ تداخل و سرقت زمانی در برنامه‌های ثبت‌شده مشاهده نشد.',
                      style: TextStyle(color: AppColors.breakTime)),
                ),
              ),
            )
          else
            Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: thieves.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, index) {
                  final t = thieves[index];
                  final minStolen = (t.stolenSeconds / 60).round();

                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber_rounded,
                        color: Colors.amber, size: 22),
                    title: Text(
                      'پروژه آسیب‌دیده: ${t.plannedProject?.name ?? t.plannedBlock.title}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(
                        '${t.reason}  —  میزان زمان دزدیده‌شده: $minStolen دقیقه',
                        style: const TextStyle(fontSize: 11.5)),
                    trailing: Text(
                      '-$minStolen min',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent),
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
