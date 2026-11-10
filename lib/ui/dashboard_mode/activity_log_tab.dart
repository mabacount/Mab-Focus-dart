import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/date_time_utils.dart';
import '../../core/jalali_date.dart';
import '../../models/pomodoro_state.dart';
import '../../models/session_note.dart';
import '../../models/time_record.dart';
import '../../providers/app_state_provider.dart';
import '../../services/database_service.dart';
import '../shared/unified_project_selector.dart';
import '../shared/work_note_dialog.dart';

/// دیالوگ ویرایش ممیزی‌دار یک رکورد زمانی (قابل استفاده در تایم‌شیت و تقویم)
Future<void> showTimeRecordEditDialog(
  BuildContext context,
  TimeRecord record,
) async {
  final provider = context.read<AppStateProvider>();
  final titleCtrl = TextEditingController(text: record.titleSnapshot);
  final editNoteCtrl = TextEditingController(text: record.editNote ?? '');
  AppRealm selectedRealm = record.realm;
  String? selectedProjectId = record.projectId;
  DateTime start = record.startTime;
  DateTime end = record.endTime ??
      record.startTime.add(Duration(seconds: record.durationSeconds));

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final realmColor = selectedRealm == AppRealm.life
            ? AppColors.lifeGreen
            : AppColors.workBlue;
        final durationSec = end.difference(start).inSeconds.clamp(60, 86400);

        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: realmColor.withAlpha(110)),
          ),
          title: Row(
            children: [
              Icon(Icons.edit_calendar_rounded, color: realmColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'ویرایش ممیزی‌دار رکورد زمانی [Edited]',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<AppRealm>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      selectedBackgroundColor: realmColor.withAlpha(45),
                      selectedForegroundColor: realmColor,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: AppRealm.work,
                        icon: Icon(Icons.work_rounded, size: 15),
                        label: Text('قلمرو کار'),
                      ),
                      ButtonSegment(
                        value: AppRealm.life,
                        icon: Icon(Icons.spa_rounded, size: 15),
                        label: Text('قلمرو زندگی'),
                      ),
                    ],
                    selected: {selectedRealm},
                    onSelectionChanged: (s) {
                      setModalState(() {
                        selectedRealm = s.first;
                        if (selectedProjectId != null) {
                          final p = provider.getProjectById(selectedProjectId);
                          if (p != null && p.realm != selectedRealm) {
                            selectedProjectId = null;
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'عنوان رکورد',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  UnifiedProjectSelector(
                    projects: provider.projects,
                    realmFilter: selectedRealm,
                    selectedProjectId: selectedProjectId,
                    accentColor: realmColor,
                    onSelected: (pid) =>
                        setModalState(() => selectedProjectId = pid),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time_rounded, size: 16),
                          label: Text(
                            'شروع: ${DateFormat('HH:mm').format(start)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.fromDateTime(start),
                            );
                            if (t != null) {
                              setModalState(() {
                                start = DateTime(start.year, start.month,
                                    start.day, t.hour, t.minute);
                                if (!end.isAfter(start)) {
                                  end = start.add(const Duration(minutes: 5));
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.alarm_on_rounded, size: 16),
                          label: Text(
                            'پایان: ${DateFormat('HH:mm').format(end)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.fromDateTime(end),
                            );
                            if (t != null) {
                              final candidate = DateTime(
                                  end.year, end.month, end.day, t.hour, t.minute);
                              if (candidate.isAfter(start)) {
                                setModalState(() => end = candidate);
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'مدت محاسبه‌شده: ${(durationSec / 60).toStringAsFixed(1)} دقیقه • تاریخ: ${JalaliDate.formatWithWeekDay(start)}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: editNoteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'علت ویرایش (ممیزی سیستم)',
                      hintText: 'مثلاً: فراموشی ثبت زمان پایان',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('انصراف'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: realmColor),
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('ذخیره ویرایش'),
              onPressed: () async {
                final cleanTitle = titleCtrl.text.trim();
                if (cleanTitle.isEmpty) return;

                await provider.editTimeRecordWithAudit(
                  id: record.id,
                  newTitle: cleanTitle,
                  newRealm: selectedRealm,
                  newOutcomeId:
                      selectedRealm == record.realm ? record.outcomeId : null,
                  clearOutcomeId:
                      selectedRealm != record.realm || record.outcomeId == null,
                  newProjectId: selectedProjectId,
                  clearProjectId: selectedProjectId == null,
                  newTagIds: record.tagIds,
                  newStartTime: start,
                  newEndTime: end,
                  newDurationSeconds:
                      end.difference(start).inSeconds.clamp(1, 86400),
                  editNote: editNoteCtrl.text.trim().isEmpty
                      ? 'ویرایش دستی توسط کاربر'
                      : editNoteCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
    titleCtrl.dispose();
    editNoteCtrl.dispose();
  });
}

class ActivityLogTab extends StatefulWidget {
  const ActivityLogTab({super.key});

  @override
  State<ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends State<ActivityLogTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // فیلترهای گزارش کارکرد
  AppRealm? _recordRealmFilter; // null = همه ۲۴ ساعت
  String _clockFilter = 'all'; // all | pomodoro | stopwatch | untitled
  String? _selectedProjectId;
  bool _onlyToday = false;

  // فیلترهای یادداشت‌ها
  AppRealm? _noteRealmFilter;
  String? _noteFilterProjectId;
  SessionNoteType? _noteTypeFilter;
  final TextEditingController _noteSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteSearchCtrl.dispose();
    super.dispose();
  }

  List<TimeRecord> _filterRecords(
    List<TimeRecord> list,
    AppStateProvider provider,
  ) {
    final now = DateTime.now();
    final Set<String>? projFamily = _selectedProjectId != null
        ? DatabaseService.getProjectAndDescendantIds(
            _selectedProjectId!, provider.projects)
        : null;

    return list.where((r) {
      if (_recordRealmFilter != null && r.realm != _recordRealmFilter) {
        return false;
      }
      if (_onlyToday) {
        if (r.startTime.year != now.year ||
            r.startTime.month != now.month ||
            r.startTime.day != now.day) {
          return false;
        }
      }
      if (projFamily != null) {
        if (r.projectId == null || !projFamily.contains(r.projectId)) {
          return false;
        }
      }
      if (_clockFilter == 'pomodoro') return r.isPomodoro;
      if (_clockFilter == 'stopwatch') return r.isStopwatch;
      if (_clockFilter == 'untitled') return r.isUntitledDraft;
      return true;
    }).toList();
  }

  List<SessionNote> _filterNotes(
    List<SessionNote> list,
    AppStateProvider provider,
  ) {
    final query = _noteSearchCtrl.text.trim().toLowerCase();
    final Set<String>? projFamily = _noteFilterProjectId != null
        ? DatabaseService.getProjectAndDescendantIds(
            _noteFilterProjectId!, provider.projects)
        : null;

    return list.where((n) {
      if (_noteRealmFilter != null && n.realm != _noteRealmFilter) {
        return false;
      }
      if (_noteTypeFilter != null && n.noteType != _noteTypeFilter) {
        return false;
      }
      if (projFamily != null) {
        if (n.projectId == null || !projFamily.contains(n.projectId)) {
          return false;
        }
      }
      if (query.isNotEmpty) {
        final outcome =
            n.outcomeId != null ? provider.getOutcomeById(n.outcomeId!) : null;
        final rec = n.timeRecordId != null
            ? provider.getTimeRecordById(n.timeRecordId!)
            : null;
        final projName = provider.getProjectBreadcrumbString(n.projectId);

        final matchesContent = n.content.toLowerCase().contains(query);
        final matchesOutcome =
            (outcome?.title ?? '').toLowerCase().contains(query);
        final matchesRecord =
            (rec?.titleSnapshot ?? '').toLowerCase().contains(query);
        final matchesProj = projName.toLowerCase().contains(query);
        if (!matchesContent &&
            !matchesOutcome &&
            !matchesRecord &&
            !matchesProj) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void _showImagePreview(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(path)),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final palette = provider.activePalette;
    final notesCount = provider.sessionNotes.length;

    return Column(
      children: [
        // هدر تب‌ها
        Container(
          color: palette.surface,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: palette.accent,
                  labelColor: palette.accent,
                  unselectedLabelColor: AppColors.textSecondary,
                  tabs: [
                    const Tab(
                      icon: Icon(Icons.table_chart_rounded, size: 18),
                      text: 'گزارش کارکرد و تایم‌شیت',
                    ),
                    Tab(
                      icon: Badge(
                        isLabelVisible: notesCount > 0,
                        label: Text('$notesCount'),
                        backgroundColor: palette.accent,
                        child: const Icon(Icons.note_alt_rounded, size: 18),
                      ),
                      text: 'دفترچه یادداشت‌های جلسات',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: palette.accent.withAlpha(35),
                  foregroundColor: palette.accent,
                ),
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('ثبت یادداشت +',
                    style: TextStyle(fontSize: 11.5)),
                onPressed: () => WorkNoteDialog.openStandalone(context),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.border),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildActivityLogsView(provider, palette),
              _buildSessionNotesView(provider, palette),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== ۱. نمای گزارش کارکرد و تایم‌شیت ====================

  Widget _buildActivityLogsView(
    AppStateProvider provider,
    RealmPalette palette,
  ) {
    final filtered = _filterRecords(provider.timeRecords, provider);
    final totalSec =
        filtered.fold<int>(0, (sum, item) => sum + item.durationSeconds);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('امروز',
                            style: TextStyle(fontSize: 11.5)),
                        selected: _onlyToday,
                        selectedColor: palette.accent.withAlpha(45),
                        onSelected: (v) => setState(() => _onlyToday = v),
                      ),
                      SegmentedButton<AppRealm?>(
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          selectedBackgroundColor: palette.accent.withAlpha(45),
                        ),
                        segments: const [
                          ButtonSegment(
                              value: null, label: Text('۲۴ ساعته')),
                          ButtonSegment(
                              value: AppRealm.work, label: Text('کار')),
                          ButtonSegment(
                              value: AppRealm.life, label: Text('زندگی')),
                        ],
                        selected: {_recordRealmFilter},
                        onSelectionChanged: (s) =>
                            setState(() => _recordRealmFilter = s.first),
                      ),
                      DropdownButton<String>(
                        value: _clockFilter,
                        dropdownColor: palette.surfaceElevated,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                              value: 'all', child: Text('همه ساعت‌ها')),
                          DropdownMenuItem(
                              value: 'pomodoro', child: Text('پومودورو')),
                          DropdownMenuItem(
                              value: 'stopwatch', child: Text('کرنومتر آزاد')),
                          DropdownMenuItem(
                              value: 'untitled', child: Text('نیازمند عنوان')),
                        ],
                        onChanged: (v) =>
                            setState(() => _clockFilter = v ?? 'all'),
                      ),
                      SizedBox(
                        width: 220,
                        child: UnifiedProjectSelector(
                          projects: provider.projects,
                          realmFilter: _recordRealmFilter,
                          selectedProjectId: _selectedProjectId,
                          emptyLabel: 'فیلتر پروژه: همه',
                          accentColor: palette.accent,
                          onSelected: (pid) =>
                              setState(() => _selectedProjectId = pid),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'مجموع (${filtered.length}): ${DateTimeUtils.formatDurationHms(totalSec)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: palette.accent,
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.lifeGreen),
                        icon: const Icon(Icons.table_view_rounded, size: 16),
                        label: const Text('اکسل ۱۶ ستونی',
                            style: TextStyle(fontSize: 11.5)),
                        onPressed: () async {
                          final path =
                              await provider.exportRecordsToExcel(filtered);
                          if (mounted && path != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('فایل اکسل در مسیر زیر ذخیره شد: $path'),
                                backgroundColor: AppColors.lifeGreen,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'هیچ رکوردی برای نمایش با این فیلتر یافت نشد.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final rec = filtered[i];
                      final realmColor = rec.isLife
                          ? AppColors.lifeGreen
                          : AppColors.workBlue;
                      final outcome = rec.outcomeId != null
                          ? provider.getOutcomeById(rec.outcomeId!)
                          : null;
                      final breadcrumb =
                          provider.getProjectBreadcrumbString(rec.projectId);
                      final notes = provider.getNotesForRecord(rec.id);

                      return Card(
                        color: palette.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: palette.border),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Container(
                            width: 4,
                            height: 36,
                            decoration: BoxDecoration(
                              color: realmColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          title: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: realmColor.withAlpha(34),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  rec.realm.labelFa,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: realmColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                outcome?.title ?? rec.titleSnapshot,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              if (breadcrumb.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    breadcrumb,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              if (rec.isEdited)
                                Tooltip(
                                  message:
                                      'زمان اولیه: ${DateTimeUtils.formatDurationHms(rec.originalDurationSeconds ?? rec.durationSeconds)}',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.edited.withAlpha(40),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '[Edited]',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.edited,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              if (notes.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: palette.accent.withAlpha(32),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${notes.length} یادداشت',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: palette.accent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${JalaliDate.formatWithWeekDay(rec.startTime)} ${DateFormat('HH:mm').format(rec.startTime)}'
                            ' • ${rec.clockMode.labelFa}'
                            '${rec.earnedBreakSeconds > 0 ? " • +${DateTimeUtils.formatDurationHms(rec.earnedBreakSeconds)} بانک" : ""}'
                            '${rec.isOpen ? " • (در حال اجرا)" : ""}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateTimeUtils.formatDurationHms(rec.isOpen
                                    ? provider.activeRecordElapsedSeconds
                                    : rec.durationSeconds),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: realmColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip:
                                    'تبدیل به ${rec.isWork ? "زندگی" : "کار"} (چالش ۲)',
                                icon: Icon(Icons.swap_horiz_rounded,
                                    size: 18, color: realmColor),
                                onPressed: () =>
                                    provider.swapSavedRecordRealm(rec.id),
                              ),
                              if (!rec.isOpen)
                                IconButton(
                                  tooltip: 'ویرایش رکورد',
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 17),
                                  onPressed: () =>
                                      showTimeRecordEditDialog(context, rec),
                                ),
                              IconButton(
                                tooltip: 'حذف رکورد',
                                icon: const Icon(Icons.delete_outline,
                                    size: 17, color: Colors.redAccent),
                                onPressed: () =>
                                    provider.deleteTimeRecord(rec.id),
                              ),
                            ],
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

  // ==================== ۲. نمای دفترچه یادداشت‌های جلسات ====================

  Widget _buildSessionNotesView(
    AppStateProvider provider,
    RealmPalette palette,
  ) {
    final filtered = _filterNotes(provider.sessionNotes, provider);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: palette.surface,
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
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(minWidth: 200, maxWidth: 320),
                        child: TextField(
                          controller: _noteSearchCtrl,
                          decoration: const InputDecoration(
                            hintText: 'جست‌وجو در متن یا عنوان کار...',
                            prefixIcon: Icon(Icons.search_rounded, size: 18),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      SegmentedButton<AppRealm?>(
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          selectedBackgroundColor: palette.accent.withAlpha(45),
                        ),
                        segments: const [
                          ButtonSegment(value: null, label: Text('همه')),
                          ButtonSegment(
                              value: AppRealm.work, label: Text('کار')),
                          ButtonSegment(
                              value: AppRealm.life, label: Text('زندگی')),
                        ],
                        selected: {_noteRealmFilter},
                        onSelectionChanged: (s) =>
                            setState(() => _noteRealmFilter = s.first),
                      ),
                      SizedBox(
                        width: 220,
                        child: UnifiedProjectSelector(
                          projects: provider.projects,
                          realmFilter: _noteRealmFilter,
                          selectedProjectId: _noteFilterProjectId,
                          emptyLabel: 'فیلتر پروژه: همه',
                          accentColor: palette.accent,
                          onSelected: (pid) =>
                              setState(() => _noteFilterProjectId = pid),
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: palette.accent),
                        icon: const Icon(Icons.file_download_rounded, size: 17),
                        label: const Text('خروجی اکسل یادداشت‌ها',
                            style: TextStyle(fontSize: 11.5)),
                        onPressed: () async {
                          final path = await provider
                              .exportSessionNotesToExcel(filtered);
                          if (mounted && path != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'فایل اکسل یادداشت‌ها ذخیره شد: $path'),
                                backgroundColor: AppColors.lifeGreen,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('همه انواع',
                              style: TextStyle(fontSize: 11)),
                          selected: _noteTypeFilter == null,
                          onSelected: (_) =>
                              setState(() => _noteTypeFilter = null),
                        ),
                        const SizedBox(width: 6),
                        ...SessionNoteType.values.map((t) => Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: FilterChip(
                                avatar:
                                    Icon(t.icon, size: 14, color: t.color),
                                label: Text(t.labelFa,
                                    style: const TextStyle(fontSize: 11)),
                                selected: _noteTypeFilter == t,
                                onSelected: (_) => setState(() =>
                                    _noteTypeFilter =
                                        _noteTypeFilter == t ? null : t),
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_note_rounded,
                            size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 8),
                        const Text(
                          'هیچ یادداشتی برای نمایش یافت نشد.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('ثبت اولین یادداشت'),
                          onPressed: () =>
                              WorkNoteDialog.openStandalone(context),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) {
                      final note = filtered[idx];
                      final realmColor = note.realm == AppRealm.life
                          ? AppColors.lifeGreen
                          : AppColors.workBlue;
                      final outcome = note.outcomeId != null
                          ? provider.getOutcomeById(note.outcomeId!)
                          : null;
                      final record = note.timeRecordId != null
                          ? provider.getTimeRecordById(note.timeRecordId!)
                          : null;
                      final breadcrumb =
                          provider.getProjectBreadcrumbString(note.projectId);
                      final targetTitle = outcome?.title ??
                          record?.titleSnapshot ??
                          'یادداشت جلسه';
                      final jalaliDate =
                          JalaliDate.formatWithWeekDay(note.createdAt);
                      final timeStr =
                          DateFormat('HH:mm').format(note.createdAt);

                      return Card(
                        color: palette.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: palette.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                alignment: WrapAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: note.noteType.color
                                              .withAlpha(35),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(note.noteType.icon,
                                                size: 13,
                                                color: note.noteType.color),
                                            const SizedBox(width: 4),
                                            Text(
                                              note.noteType.labelFa,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: note.noteType.color,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: realmColor.withAlpha(30),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          note.realm.labelFa,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: realmColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 280),
                                        child: Text(
                                          targetTitle,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (breadcrumb.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: palette.accent.withAlpha(30),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            breadcrumb,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: palette.accent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(
                                        '$jalaliDate — $timeStr',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18, color: Colors.redAccent),
                                        tooltip: 'حذف یادداشت',
                                        onPressed: () async {
                                          final confirm =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (c) => AlertDialog(
                                              title: const Text('حذف یادداشت'),
                                              content: const Text(
                                                  'آیا از حذف این یادداشت اطمینان دارید؟'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(c)
                                                          .pop(false),
                                                  child: const Text('انصراف'),
                                                ),
                                                FilledButton(
                                                  style: FilledButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.redAccent),
                                                  onPressed: () =>
                                                      Navigator.of(c).pop(true),
                                                  child: const Text('حذف'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await provider
                                                .deleteSessionNote(note.id);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (note.content.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: palette.surfaceElevated,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: palette.border),
                                  ),
                                  child: SelectableText(
                                    note.content,
                                    style: const TextStyle(
                                        fontSize: 12.5, height: 1.5),
                                  ),
                                ),
                              ],
                              if (note.imagePaths.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 80,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: note.imagePaths.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (c, imgIdx) {
                                      final path = note.imagePaths[imgIdx];
                                      final file = File(path);
                                      return InkWell(
                                        onTap: () =>
                                            _showImagePreview(context, path),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: palette.border),
                                            color: Colors.black26,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: file.existsSync()
                                              ? Image.file(file,
                                                  fit: BoxFit.cover)
                                              : const Icon(
                                                  Icons.broken_image_rounded,
                                                  size: 24,
                                                  color: AppColors.textMuted),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
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
