import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/date_time_utils.dart';
import '../../providers/app_state_provider.dart';
import '../../services/music_player_service.dart';
import '../../services/txt_logger_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final TextEditingController _focusCtrl = TextEditingController();
  final TextEditingController _shortCtrl = TextEditingController();
  final TextEditingController _longCtrl = TextEditingController();
  final TextEditingController _ratioCtrl = TextEditingController();
  final TextEditingController _cycleTargetCtrl = TextEditingController();
  final TextEditingController _autoResetCtrl = TextEditingController();

  final TextEditingController _gcalTokenCtrl = TextEditingController();
  final TextEditingController _workPlanCalCtrl = TextEditingController();
  final TextEditingController _lifePlanCalCtrl = TextEditingController();
  final TextEditingController _workLogCalCtrl = TextEditingController();
  final TextEditingController _lifeLogCalCtrl = TextEditingController();

  String _txtPreview = '';

  @override
  void initState() {
    super.initState();
    final p = context.read<AppStateProvider>();
    _focusCtrl.text = p.focusDurationMinutes.toString();
    _shortCtrl.text = p.shortBreakDurationMinutes.toString();
    _longCtrl.text = p.longBreakDurationMinutes.toString();
    _ratioCtrl.text = p.breakRatio.toString();
    _cycleTargetCtrl.text = p.cycleWorkTargetMinutes.toString();
    _autoResetCtrl.text = p.cycleAutoResetMinutes.toString();

    _gcalTokenCtrl.text = p.gcalToken;
    _workPlanCalCtrl.text = p.workPlanCalendarId;
    _lifePlanCalCtrl.text = p.lifePlanCalendarId;
    _workLogCalCtrl.text = p.workLogCalendarId;
    _lifeLogCalCtrl.text = p.lifeLogCalendarId;
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final c = await TxtLoggerService.instance.readLogFileContent();
    if (mounted) setState(() => _txtPreview = c);
  }

  @override
  void dispose() {
    _focusCtrl.dispose();
    _shortCtrl.dispose();
    _longCtrl.dispose();
    _ratioCtrl.dispose();
    _cycleTargetCtrl.dispose();
    _autoResetCtrl.dispose();
    _gcalTokenCtrl.dispose();
    _workPlanCalCtrl.dispose();
    _lifePlanCalCtrl.dispose();
    _workLogCalCtrl.dispose();
    _lifeLogCalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final music = context.watch<MusicPlayerService>();
    final palette = provider.activePalette;
    final state = provider.pomodoroState;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ۱. وضعیت زنده بانک استراحت Flowmodoro و دکمه ریست دستی (چالش ۱)
          Card(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 600;
                      final titleRow = Row(
                        children: [
                          Icon(Icons.bolt_rounded,
                              color: palette.accent, size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'وضعیت لحظه‌ای بانک استراحت و چرخه Flowmodoro',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14.5),
                            ),
                          ),
                        ],
                      );
                      final resetBtn = FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              AppColors.draftWarning.withAlpha(35),
                          foregroundColor: AppColors.draftWarning,
                        ),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('ریست دستی چرخه Flowmodoro'),
                        onPressed: () async {
                          await provider.resetFlowmodoroCycle();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'چرخه کار، ذخیره استراحت و بدهی استراحت با موفقیت ریست شد.'),
                              ),
                            );
                          }
                        },
                      );
                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            titleRow,
                            const SizedBox(height: 8),
                            Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: resetBtn),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: titleRow),
                          const SizedBox(width: 12),
                          resetBtn,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: state.cycleProgress,
                      minHeight: 8,
                      backgroundColor: palette.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _BankStatChip(
                        label: 'کار انباشته چرخه (W_cycle)',
                        value:
                            '${DateTimeUtils.formatDurationHms(state.cycleWorkSeconds)} / ${DateTimeUtils.formatDurationHms(state.cycleWorkTargetSeconds)}',
                        color: AppColors.workBlue,
                      ),
                      _BankStatChip(
                        label: 'ذخیره استراحت کوتاه (B_earned)',
                        value: DateTimeUtils.formatDurationHms(
                            state.earnedShortBreakSeconds),
                        color: AppColors.lifeGreen,
                      ),
                      _BankStatChip(
                        label: 'بدهی کسر از استراحت طولانی (D_break)',
                        value: DateTimeUtils.formatDurationHms(
                            state.breakDebtSeconds),
                        color: state.breakDebtSeconds > 0
                            ? AppColors.overtime
                            : AppColors.textSecondary,
                      ),
                      _BankStatChip(
                        label: 'حالت استراحت بعدی',
                        value: state.cycleWorkSeconds >=
                                state.cycleWorkTargetSeconds
                            ? 'استراحت طولانی (${provider.longBreakDurationMinutes}m پایه)'
                            : 'استراحت کوتاه (حداقل ${provider.shortBreakDurationMinutes}m)',
                        color: AppColors.golden,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ۲. تنظیمات زمان‌بندی موتور Flowmodoro
          Card(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('پارامترهای زمان‌بندی Flowmodoro و ریست خودکار',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _numField(_focusCtrl, 'هدف تمرکز (دقیقه)'),
                      _numField(_shortCtrl, 'کف استراحت (دقیقه)'),
                      _numField(_longCtrl, 'استراحت طولانی پایه (دقیقه)'),
                      _numField(_ratioCtrl, 'نسبت کار به استراحت (پیش‌فرض ۵)'),
                      _numField(_cycleTargetCtrl, 'سقف کار چرخه (دقیقه)'),
                      _numField(_autoResetCtrl, 'آستانه خواب/ریست (دقیقه)'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: palette.accent),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text('ذخیره تنظیمات ریتم'),
                      onPressed: () async {
                        await provider.updateTimerSettings(
                          focusMinutes: int.tryParse(_focusCtrl.text) ?? 25,
                          shortBreakMinutes:
                              int.tryParse(_shortCtrl.text) ?? 5,
                          longBreakMinutes: int.tryParse(_longCtrl.text) ?? 60,
                          breakRatio: int.tryParse(_ratioCtrl.text) ?? 5,
                          cycleWorkTargetMinutes:
                              int.tryParse(_cycleTargetCtrl.text) ?? 100,
                          cycleAutoResetMinutes:
                              int.tryParse(_autoResetCtrl.text) ?? 90,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('تنظیمات Flowmodoro ذخیره شد.')),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ۳. پلیر موسیقی تمرکز ADHD
          Card(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('موسیقی تمرکز ویژه ADHD',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('تعداد ترک‌های بارگذاری‌شده: ${music.tracks.length}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: palette.accent),
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('انتخاب پوشه موسیقی از هارد'),
                        onPressed: () async {
                          final selectedFolder =
                              await FilePicker.platform.getDirectoryPath();
                          if (selectedFolder != null) {
                            final count = await music
                                .loadTracksFromFolder(selectedFolder);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('$count فایل صوتی بارگذاری شد.'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'ادامه پخش موسیقی در قلمرو زندگی (پیش‌فرض: خاموش)',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: music.playDuringBreaks,
                          onChanged: music.setPlayDuringBreaks,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ۴. تنظیمات دوگانه Google Calendar API v3 (چالش ۷)
          Card(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'همگام‌سازی دوگانه Google Calendar API v3 (بدون تکرار با PATCH)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'اگر پروژه‌ای دارای Calendar ID اختصاصی (یا ارث‌بری از مادر) باشد، رکوردهای آن در تقویم همان پروژه و در غیر این صورت در تقویم کار یا زندگی زیر ثبت و آپدیت می‌شوند.',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _gcalTokenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'OAuth 2.0 Access Token گوگل',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _workPlanCalCtrl,
                          decoration: const InputDecoration(
                            labelText: 'تقویم برنامه کار (Work Plan ID)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _lifePlanCalCtrl,
                          decoration: const InputDecoration(
                            labelText: 'تقویم برنامه زندگی (Life Plan ID)',
                            hintText: 'اختیاری (مثلاً شناسه تقویم دوم)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _workLogCalCtrl,
                          decoration: const InputDecoration(
                            labelText: 'تقویم لاگ کار (Work Log ID)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _lifeLogCalCtrl,
                          decoration: const InputDecoration(
                            labelText: 'تقویم لاگ زندگی (Life Log ID)',
                            hintText: 'اختیاری',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: palette.accent),
                      icon: const Icon(Icons.cloud_done_rounded, size: 16),
                      label: const Text('ذخیره تنظیمات گوگل کلندر'),
                      onPressed: () async {
                        await provider.updateGCalCalendars(
                          token: _gcalTokenCtrl.text,
                          workPlanId: _workPlanCalCtrl.text,
                          lifePlanId: _lifePlanCalCtrl.text,
                          workLogId: _workLogCalCtrl.text,
                          lifeLogId: _lifeLogCalCtrl.text,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'تنظیمات توکن و تقویم‌های کار/زندگی ذخیره شد.'),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ۵. فایل لاگ متنی
          Card(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'فایل متنی خودکار ChronoFlow_WorkLog.txt',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      IconButton(
                        tooltip: 'به‌روزرسانی پیش‌نمایش',
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        onPressed: _loadPreview,
                      ),
                    ],
                  ),
                  Text('مسیر: ${provider.txtLogPath}',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 11, color: palette.accent)),
                  const SizedBox(height: 8),
                  Container(
                    height: 140,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _txtPreview.isEmpty
                            ? '(هنوز داده‌ای در فایل متنی ثبت نشده است)'
                            : _txtPreview,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label) {
    return SizedBox(
      width: 175,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _BankStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BankStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10.5, color: AppColors.textSecondary)),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
