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
                        label: state.isLife
                            ? 'وضعیت و فرمول استراحت فعلی'
                            : 'وضعیت و فرمول استراحت بعدی',
                        value: provider.breakTargetExplanationFa,
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

          // ۳. پلیر و مدیریت پوشه‌های موسیقی در دیتابیس
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 520;
                      final titleWidget = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.music_note_rounded,
                              color: palette.accent, size: 22),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              'مدیریت پوشه‌های موسیقی و پخش تصادفی',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14.5),
                            ),
                          ),
                        ],
                      );
                      final addBtn = FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: palette.accent),
                        icon: const Icon(Icons.create_new_folder_rounded,
                            size: 16),
                        label: const Text('افزودن پوشه جدید'),
                        onPressed: () async {
                          final selectedFolder =
                              await FilePicker.platform.getDirectoryPath();
                          if (selectedFolder != null) {
                            await music.addFolder(selectedFolder);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'پوشه جدید در دیتابیس ذخیره و فعال شد.'),
                                ),
                              );
                            }
                          }
                        },
                      );
                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            titleWidget,
                            const SizedBox(height: 8),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: addBtn,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: titleWidget),
                          addBtn,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (music.playlists.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.folder_off_outlined,
                              size: 16, color: AppColors.textMuted),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'هیچ پوشه موسیقی ذخیره نشده است. با دکمه «افزودن پوشه جدید» مسیر پوشه آهنگ‌های خود را انتخاب کنید.',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    const Text('پوشه‌های ذخیره‌شده در دیتابیس:',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: music.playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (ctx, i) {
                        final pl = music.playlists[i];
                        final isActive = music.activePlaylist?.id == pl.id;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isActive
                                ? palette.accent.withAlpha(25)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive
                                  ? palette.accent.withAlpha(120)
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isActive
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                size: 16,
                                color: isActive
                                    ? palette.accent
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pl.name,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isActive
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isActive
                                            ? palette.accent
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      pl.folderPath,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isActive)
                                TextButton(
                                  onPressed: () => music.selectPlaylist(pl),
                                  child: const Text('انتخاب به‌عنوان فعال',
                                      style: TextStyle(fontSize: 11)),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: palette.accent.withAlpha(40),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('پوشه فعال فعلی',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 16, color: AppColors.overtime),
                                tooltip: 'حذف این پوشه',
                                onPressed: () async {
                                  await music.deletePlaylist(pl.id);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'پخش تصادفی (Random) در پوشه‌ها',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: const Text(
                            'آهنگ بعدی و قبلی به صورت شانسی انتخاب می‌شود',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textMuted),
                          ),
                          value: music.isShuffle,
                          onChanged: (_) => music.toggleShuffle(),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'ادامه پخش موسیقی در قلمرو زندگی',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: const Text(
                            'پیش‌فرض خاموش (قطع موزیک در زمان استراحت)',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textMuted),
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

          // ۴. اسلایدشوی طبیعت و صدای آبشار در حالت زندگی
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
                  Row(
                    children: [
                      const Icon(Icons.forest_rounded,
                          color: AppColors.lifeGreen, size: 22),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'اسلایدشوی تمام‌صفحه طبیعت و صدای آبشار در حالت زندگی',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14.5),
                        ),
                      ),
                      Switch(
                        value: provider.isLifeNatureSlideshowEnabled,
                        activeThumbColor: AppColors.lifeGreen,
                        onChanged: (val) async {
                          await provider.setLifeNatureSlideshowEnabled(val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'هنگام ورود به قلمرو زندگی (استراحت)، یک اسلایدشوی آرامش‌بخش از طبیعت، صدای زنده آبشار و طبیعت و نمایش تایمر استراحت روی تمام دسکتاپ‌ها پخش می‌شود.',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.lifeGreen,
                          side: const BorderSide(color: AppColors.lifeGreen),
                        ),
                        icon: const Icon(Icons.slideshow_rounded, size: 16),
                        label: const Text('پیش‌نمایش اسلایدشو طبیعت'),
                        onPressed: () async {
                          await provider.activateNatureSlideshow();
                        },
                      ),
                      const Text(
                        'دکمه بستن در بالای صفحه و کلید Esc برای خروج سریع در دسترس است.',
                        style: TextStyle(
                            fontSize: 10.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ۵. تنظیمات دوگانه Google Calendar API v3 (چالش ۷)
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
          const SizedBox(height: 16),

          // ۵. درباره نسخه و سیستم نسخه‌گذاری
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
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: palette.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'درباره نسخه و شناسنامه انتشار',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'نسخه فعلی: v4.1.0+2 — تداوم تمرکز (Focus Continuity)',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'منطق نسخه‌گذاری (MAJOR.MINOR.PATCH+BUILD): تغییر MAJOR برای بازطراحی معماری، MINOR برای قابلیت‌های کلیدی جدید، PATCH برای رفع باگ‌ها، و BUILD برای هر خروجی رسمی.',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary),
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
