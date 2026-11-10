import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/platform_helper.dart';
import '../models/pomodoro_state.dart';
import '../models/time_record.dart';
import '../providers/app_state_provider.dart';
import 'dashboard_mode/dashboard_screen.dart';
import 'widget_mode/floating_widget_view.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  Future<void> _showCrashRecoveryCloseDialog(
    BuildContext context,
    AppStateProvider provider,
    TimeRecord recovered,
  ) async {
    final now = DateTime.now();
    DateTime selectedTime = recovered.startTime.add(const Duration(minutes: 25));
    if (selectedTime.isAfter(now)) selectedTime = now;
    AppRealm nextRealm = recovered.isWork ? AppRealm.life : AppRealm.work;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('اصلاح زمان پایان رکورد بازمانده',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'رکورد «${recovered.title}» (${recovered.realm.labelFa}) از ساعت ${DateFormat('HH:mm').format(recovered.startTime)} باز مانده است.',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.access_time_rounded, size: 16),
                  label: Text(
                      'زمان واقعی پایان رکورد: ${DateFormat('HH:mm').format(selectedTime)}'),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(selectedTime),
                    );
                    if (picked != null) {
                      var candidate = DateTime(
                        recovered.startTime.year,
                        recovered.startTime.month,
                        recovered.startTime.day,
                        picked.hour,
                        picked.minute,
                      );
                      // اگر پایان به بعد از نیمه‌شب افتاد
                      if (candidate.isBefore(recovered.startTime)) {
                        candidate = candidate.add(const Duration(days: 1));
                      }
                      if (candidate.isAfter(now)) {
                        candidate = now;
                      }
                      setDialogState(() => selectedTime = candidate);
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text('از آن زمان تا اکنون در چه قلمرویی بوده‌اید؟',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                SegmentedButton<AppRealm>(
                  segments: const [
                    ButtonSegment(
                      value: AppRealm.work,
                      label: Text('کار (آبی)'),
                      icon: Icon(Icons.work_rounded, size: 15),
                    ),
                    ButtonSegment(
                      value: AppRealm.life,
                      label: Text('زندگی (سبز)'),
                      icon: Icon(Icons.coffee_rounded, size: 15),
                    ),
                  ],
                  selected: {nextRealm},
                  onSelectionChanged: (set) =>
                      setDialogState(() => nextRealm = set.first),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await provider.closeRecoveredRecordAtTimeAndStartNew(
                    closedAt: selectedTime,
                    nextRealm: nextRealm,
                  );
                },
                child: const Text('تایید و ثبت پیوسته'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final posture = provider.pomodoroState.windowPosture;
        final isWidgetMode =
            PlatformHelper.isDesktop && posture != WindowPosture.dashboard;

        if (isWidgetMode) {
          return const FloatingWidgetView();
        }

        final isWorkState = provider.pomodoroState.isWork;
        final recovered = provider.recoveredOpenRecord;
        final isWideViewport = MediaQuery.of(context).size.width >= 900;

        return Stack(
          children: [
            const DashboardScreen(),
            if (recovered != null)
              Positioned(
                top: 64,
                left: 14,
                right: 14,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 680),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.draftWarning, width: 1.3),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.restore_rounded,
                                  size: 18, color: AppColors.draftWarning),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'بازیابی جلسه ناتمام: «${recovered.title}» (${recovered.realm.labelFa}) از ساعت ${DateFormat('HH:mm').format(recovered.startTime)} ادامه یافت.',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            alignment: WrapAlignment.end,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _showCrashRecoveryCloseDialog(
                                    context, provider, recovered),
                                child: const Text('بستن در ساعت دلخواه',
                                    style: TextStyle(
                                        color: AppColors.draftWarning,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold)),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.lifeGreen,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: provider.dismissRecoveredRecordNotice,
                                child: const Text('ادامه همین جلسه',
                                    style: TextStyle(fontSize: 11.5)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (provider.lastErgonomicNudgeMessage != null)
              Positioned(
                bottom: isWideViewport ? 24 : 92,
                left: 14,
                right: 14,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 560),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.overtime, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.notification_important_rounded,
                                  color: AppColors.overtime),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  provider.lastErgonomicNudgeMessage!,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close,
                                    size: 18, color: AppColors.textSecondary),
                                onPressed: provider.clearErgonomicNudge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                provider.clearErgonomicNudge();
                                provider.switchRealm(isWorkState
                                    ? AppRealm.life
                                    : AppRealm.work);
                              },
                              child: Text(
                                isWorkState
                                    ? 'ورود به زندگی (استراحت)'
                                    : 'بازگشت به کار',
                                style: TextStyle(
                                    color: isWorkState
                                        ? AppColors.lifeGreen
                                        : AppColors.workBlue,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
