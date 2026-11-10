import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/date_time_utils.dart';
import '../../core/jalali_date.dart';
import '../../models/outcome_item.dart';
import '../../models/pomodoro_state.dart';
import '../../models/project_node.dart';
import '../../models/scheduled_block.dart';
import '../../models/session_note.dart';
import '../../models/time_record.dart';
import '../../providers/app_state_provider.dart';
import '../shared/unified_project_selector.dart';
import 'activity_log_tab.dart';

enum CalendarViewSpan { day1, day3, day7 }

enum CalendarDisplayMode { grid, timesheet }

enum CalendarRealmFilter { allDay, workOnly, lifeOnly }

class CalendarGridTab extends StatefulWidget {
  const CalendarGridTab({super.key});

  @override
  State<CalendarGridTab> createState() => _CalendarGridTabState();
}

class _CalendarGridTabState extends State<CalendarGridTab> {
  CalendarViewSpan _span = CalendarViewSpan.day7;
  CalendarDisplayMode _calendarDisplayMode = CalendarDisplayMode.grid;
  CalendarRealmFilter _realmFilter = CalendarRealmFilter.allDay;
  DateTime _focusedDate = DateTime.now();
  final ScrollController _verticalScrollController = ScrollController();
  Timer? _minuteTicker;
  bool _isSyncing = false;

  // متغیرهای زوم محور زمان (ارتفاع هر ساعت)
  double _hourHeight = 60.0;
  static const double _minHourHeight = 36.0;
  static const double _maxHourHeight = 160.0;
  static const double _timeAxisWidth = 56.0;

  // متغیرهای وضعیت درگ و جابه‌جایی یا تغییر اندازه آیتم‌ها
  String? _activeDragId;
  bool _isResizingTop = false;
  bool _isResizingBottom = false;
  double _dragAccumulatedDy = 0.0;

  @override
  void initState() {
    super.initState();
    _minuteTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_verticalScrollController.hasClients) {
        final currentHour = DateTime.now().hour;
        final targetOffset =
            ((currentHour - 1.5) * _hourHeight).clamp(0.0, 24 * _hourHeight);
        _verticalScrollController.jumpTo(targetOffset);
      }
    });
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    _verticalScrollController.dispose();
    super.dispose();
  }

  int get _daysCount {
    switch (_span) {
      case CalendarViewSpan.day1:
        return 1;
      case CalendarViewSpan.day3:
        return 3;
      case CalendarViewSpan.day7:
        return 7;
    }
  }

  List<DateTime> get _displayedDays {
    final cleanFocus = DateTimeUtils.startOfDay(_focusedDate);

    if (_span == CalendarViewSpan.day7) {
      // چالش ۶: محاسبه استاندارد آغاز هفته جلالی از بامداد شنبه
      final startOfSat = DateTimeUtils.startOfJalaliWeek(cleanFocus);
      return List.generate(7, (i) => startOfSat.add(Duration(days: i)));
    } else if (_span == CalendarViewSpan.day3) {
      final start = cleanFocus.subtract(const Duration(days: 1));
      return List.generate(3, (i) => start.add(Duration(days: i)));
    } else {
      return [cleanFocus];
    }
  }

  bool _matchesRealmFilter(AppRealm realm) {
    switch (_realmFilter) {
      case CalendarRealmFilter.allDay:
        return true;
      case CalendarRealmFilter.workOnly:
        return realm == AppRealm.work;
      case CalendarRealmFilter.lifeOnly:
        return realm == AppRealm.life;
    }
  }

  void _navigate(int direction) {
    setState(() {
      _focusedDate = _focusedDate.add(Duration(days: _daysCount * direction));
    });
  }

  void _goToToday() {
    setState(() {
      _focusedDate = DateTime.now();
    });
    if (_verticalScrollController.hasClients) {
      final currentHour = DateTime.now().hour;
      final targetOffset =
          ((currentHour - 1.5) * _hourHeight).clamp(0.0, 24 * _hourHeight);
      _verticalScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _changeZoom(double delta) {
    setState(() {
      _hourHeight = (_hourHeight + delta).clamp(_minHourHeight, _maxHourHeight);
    });
  }

  void _setZoomPreset(double height) {
    setState(() {
      _hourHeight = height.clamp(_minHourHeight, _maxHourHeight);
    });
  }

  String _formatRangeHeader(List<DateTime> days) {
    if (days.isEmpty) return '';
    final first = days.first;
    final last = days.last;
    final jFirst = JalaliDate.fromDateTime(first);
    final jLast = JalaliDate.fromDateTime(last);

    if (days.length == 1) {
      return JalaliDate.formatWithWeekDayAndYear(first);
    }

    if (jFirst.month == jLast.month && jFirst.year == jLast.year) {
      return '${jFirst.day} الی ${jLast.day} ${jFirst.monthName} ${jFirst.year}';
    } else if (jFirst.year == jLast.year) {
      return '${jFirst.day} ${jFirst.monthName} الی ${jLast.day} ${jLast.monthName} ${jFirst.year}';
    } else {
      return '${jFirst.formatShort()} ${jFirst.year} الی ${jLast.formatShort()} ${jLast.year}';
    }
  }

  /// ثبت رکورد زمانی دستی (با تگ «دستی»)
  void _showAddManualLogModal(BuildContext context, DateTime defaultStart) {
    final provider = context.read<AppStateProvider>();
    final titleCtrl = TextEditingController();
    AppRealm selectedRealm = provider.dashboardRealm;
    ClockType selectedClock = ClockType.pomodoro;
    String? selectedProjectId;
    String? selectedOutcomeId;
    DateTime start = defaultStart;
    DateTime end = defaultStart.add(const Duration(minutes: 30));

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final realmColor = selectedRealm == AppRealm.life
                ? AppColors.lifeGreen
                : AppColors.workBlue;
            final durationMin = end.difference(start).inMinutes;
            final openOutcomes =
                provider.getOpenOutcomes(realm: selectedRealm);

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: realmColor.withAlpha(110)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: realmColor.withAlpha(35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.history_edu_rounded,
                        color: realmColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'ثبت گزارش زمانی دستی (تگ دستی)',
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
                        onSelectionChanged: (s) => setModalState(() {
                          selectedRealm = s.first;
                          selectedOutcomeId = null;
                          if (selectedProjectId != null) {
                            final p = provider.getProjectById(selectedProjectId);
                            if (p != null && p.realm != selectedRealm) {
                              selectedProjectId = null;
                            }
                          }
                        }),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<ClockType>(
                        style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        segments: const [
                          ButtonSegment(
                            value: ClockType.pomodoro,
                            icon: Icon(Icons.bolt_rounded, size: 15),
                            label: Text('پومودورو هدفمند'),
                          ),
                          ButtonSegment(
                            value: ClockType.stopwatch,
                            icon: Icon(Icons.timer_outlined, size: 15),
                            label: Text('کرنومتر آزاد'),
                          ),
                        ],
                        selected: {selectedClock},
                        onSelectionChanged: (s) =>
                            setModalState(() => selectedClock = s.first),
                      ),
                      const SizedBox(height: 10),
                      if (openOutcomes.isNotEmpty) ...[
                        DropdownButtonFormField<String?>(
                          initialValue: selectedOutcomeId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'اتصال به کار باز موجود (اختیاری)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          dropdownColor: AppColors.surfaceElevated,
                          items: [
                            const DropdownMenuItem(
                                value: null,
                                child: Text('تعریف عنوان آزاد (بدون اتصال)')),
                            ...openOutcomes.map((o) => DropdownMenuItem(
                                  value: o.id,
                                  child: Text(o.title,
                                      overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (oid) {
                            setModalState(() {
                              selectedOutcomeId = oid;
                              if (oid != null) {
                                final out = provider.getOutcomeById(oid);
                                if (out != null) {
                                  titleCtrl.text = out.title;
                                  selectedProjectId = out.projectId;
                                }
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: titleCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'عنوان فعالیت انجام‌شده',
                          hintText: 'مثلاً: جلسه با کارفرما یا پیاده‌روی',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                              icon: const Icon(Icons.access_time_rounded,
                                  size: 16),
                              label: Text(
                                'شروع: ${intl.DateFormat('HH:mm').format(start)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final p = await showTimePicker(
                                  context: ctx,
                                  initialTime: TimeOfDay.fromDateTime(start),
                                );
                                if (p != null) {
                                  setModalState(() {
                                    start = DateTime(start.year, start.month,
                                        start.day, p.hour, p.minute);
                                    if (!end.isAfter(start)) {
                                      end = start
                                          .add(const Duration(minutes: 30));
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon:
                                  const Icon(Icons.alarm_on_rounded, size: 16),
                              label: Text(
                                'پایان: ${intl.DateFormat('HH:mm').format(end)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final p = await showTimePicker(
                                  context: ctx,
                                  initialTime: TimeOfDay.fromDateTime(end),
                                );
                                if (p != null) {
                                  final candidate = DateTime(end.year,
                                      end.month, end.day, p.hour, p.minute);
                                  if (candidate.isAfter(start)) {
                                    setModalState(() => end = candidate);
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.draftWarning.withAlpha(60)),
                        ),
                        child: Text(
                          'برچسب: دستی • مدت: $durationMin دقیقه (${JalaliDate.formatWithWeekDay(start)})',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
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
                  label: const Text('ثبت گزارش دستی'),
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    await provider.createManualTimeRecord(
                      realm: selectedRealm,
                      clockMode: selectedClock,
                      title: titleCtrl.text.trim(),
                      outcomeId: selectedOutcomeId,
                      projectId: selectedProjectId,
                      startTime: start,
                      endTime: end,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(titleCtrl.dispose);
  }

  /// افزودن بلوک برنامه‌ریزی‌شده
  void _showAddBlockModal(BuildContext context, DateTime defaultStart) {
    final provider = context.read<AppStateProvider>();
    final titleCtrl = TextEditingController();
    AppRealm selectedRealm = provider.dashboardRealm;
    String? selectedProjectId;
    String? selectedOutcomeId;
    DateTime start = defaultStart;
    DateTime end = defaultStart.add(const Duration(hours: 1));

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final realmColor = selectedRealm == AppRealm.life
                ? AppColors.lifeGreen
                : AppColors.workBlue;
            final durationMin = end.difference(start).inMinutes;
            final openOutcomes =
                provider.getOpenOutcomes(realm: selectedRealm);

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: realmColor.withAlpha(110)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: realmColor.withAlpha(35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.event_note_rounded,
                        color: realmColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'برنامه‌ریزی بلوک زمانی جدید',
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
                            label: Text('برنامه کار'),
                          ),
                          ButtonSegment(
                            value: AppRealm.life,
                            icon: Icon(Icons.spa_rounded, size: 15),
                            label: Text('برنامه زندگی'),
                          ),
                        ],
                        selected: {selectedRealm},
                        onSelectionChanged: (s) => setModalState(() {
                          selectedRealm = s.first;
                          selectedOutcomeId = null;
                          if (selectedProjectId != null) {
                            final p = provider.getProjectById(selectedProjectId);
                            if (p != null && p.realm != selectedRealm) {
                              selectedProjectId = null;
                            }
                          }
                        }),
                      ),
                      const SizedBox(height: 10),
                      if (openOutcomes.isNotEmpty) ...[
                        DropdownButtonFormField<String?>(
                          initialValue: selectedOutcomeId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'کار/هدف متصل (اختیاری)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          dropdownColor: AppColors.surfaceElevated,
                          items: [
                            const DropdownMenuItem(
                                value: null,
                                child: Text('بدون اتصال به کار باز')),
                            ...openOutcomes.map((o) => DropdownMenuItem(
                                  value: o.id,
                                  child: Text(o.title,
                                      overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (oid) {
                            setModalState(() {
                              selectedOutcomeId = oid;
                              if (oid != null) {
                                final out = provider.getOutcomeById(oid);
                                if (out != null) {
                                  if (titleCtrl.text.trim().isEmpty) {
                                    titleCtrl.text = out.title;
                                  }
                                  selectedProjectId = out.projectId;
                                }
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: titleCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'عنوان برنامه (مثلاً: کدنویسی یا ورزش)',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                              icon: const Icon(Icons.access_time_rounded,
                                  size: 16),
                              label: Text(
                                'شروع: ${intl.DateFormat('HH:mm').format(start)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final p = await showTimePicker(
                                  context: ctx,
                                  initialTime: TimeOfDay.fromDateTime(start),
                                );
                                if (p != null) {
                                  setModalState(() {
                                    start = DateTime(start.year, start.month,
                                        start.day, p.hour, p.minute);
                                    if (!end.isAfter(start)) {
                                      end =
                                          start.add(const Duration(hours: 1));
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon:
                                  const Icon(Icons.alarm_on_rounded, size: 16),
                              label: Text(
                                'پایان: ${intl.DateFormat('HH:mm').format(end)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final p = await showTimePicker(
                                  context: ctx,
                                  initialTime: TimeOfDay.fromDateTime(end),
                                );
                                if (p != null) {
                                  final candidate = DateTime(end.year,
                                      end.month, end.day, p.hour, p.minute);
                                  if (candidate.isAfter(start)) {
                                    setModalState(() => end = candidate);
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'مدت برنامه‌ریزی: $durationMin دقیقه (${JalaliDate.formatWithWeekDay(start)})',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
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
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('ثبت در تقویم'),
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    final block = ScheduledBlock(
                      id: const Uuid().v4(),
                      realm: selectedRealm,
                      title: titleCtrl.text.trim(),
                      projectId: selectedProjectId,
                      outcomeId: selectedOutcomeId,
                      startTime: start,
                      endTime: end,
                    );
                    await provider.saveScheduledBlock(block);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(titleCtrl.dispose);
  }

  void _showBlockDetailsModal(
      BuildContext context, ScheduledBlock block, ProjectNode? project) {
    final provider = context.read<AppStateProvider>();
    final fallbackColor =
        block.isLife ? AppColors.lifeGreen : AppColors.workBlue;
    final color = project != null
        ? Color(int.parse(project.colorHex.replaceFirst('#', '0xFF')))
        : fallbackColor;
    final breadcrumb = provider.getProjectBreadcrumbString(block.projectId);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withAlpha(120)),
        ),
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                block.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: fallbackColor.withAlpha(32),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                block.realm.labelFa,
                style: TextStyle(
                  fontSize: 10,
                  color: fallbackColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (block.source == 'gcal') ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Google Calendar',
                    style: TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
              ),
            ],
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (breadcrumb.isNotEmpty) ...[
              Text('پروژه: $breadcrumb',
                  style: TextStyle(fontSize: 13, color: color)),
              const SizedBox(height: 6),
            ],
            Text(
              'زمان: ${intl.DateFormat('HH:mm').format(block.startTime)} الی ${intl.DateFormat('HH:mm').format(block.endTime)} (${block.plannedDurationSeconds ~/ 60} دقیقه)',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'تاریخ: ${JalaliDate.formatWithWeekDayAndYear(block.startTime)}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.draftWarning),
            onPressed: () async {
              await provider.deleteScheduledBlock(block.id);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('حذف برنامه'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('بستن'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: color),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text('شروع فوری (${block.realm.labelFa})'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await provider.activateScheduledBlockTask(block);
            },
          ),
        ],
      ),
    );
  }

  void _showRecordDetailsModal(
    BuildContext context,
    TimeRecord record,
    ProjectNode? project,
    OutcomeItem? outcome,
  ) {
    final provider = context.read<AppStateProvider>();
    final color = record.isLife
        ? AppColors.lifeGreen
        : (record.isStopwatch ? AppColors.stopwatch : AppColors.workBlue);
    final isManual = record.tagIds.contains('دستی') ||
        record.tagIds.contains('manual') ||
        record.isEdited;
    final breadcrumb = provider.getProjectBreadcrumbString(record.projectId);
    final notes = provider.getNotesForRecord(record.id);
    final displayTitle = outcome?.title ??
        (record.titleSnapshot.isEmpty ? 'تسک بدون عنوان' : record.titleSnapshot);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withAlpha(120)),
        ),
        title: Row(
          children: [
            Icon(
              record.isLife
                  ? Icons.spa_rounded
                  : (record.isStopwatch
                      ? Icons.timer_outlined
                      : Icons.work_rounded),
              color: color,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayTitle,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(35),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                record.realm.labelFa,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (isManual) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.draftWarning.withAlpha(35),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'دستی/ویرایش‌شده',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: AppColors.draftWarning,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (breadcrumb.isNotEmpty) ...[
                  Text('پروژه: $breadcrumb',
                      style: TextStyle(fontSize: 13, color: color)),
                  const SizedBox(height: 6),
                ],
                Text(
                  'قلمرو و ساعت: ${record.realm.labelFa} • ${record.clockMode.labelFa}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  'مدت واقعی: ${DateTimeUtils.formatDurationFa(record.isOpen ? provider.activeRecordElapsedSeconds : record.durationSeconds)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (record.earnedBreakSeconds > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'استراحت ذخیره شده از این کار: ${DateTimeUtils.formatDurationFa(record.earnedBreakSeconds)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.lifeGreen),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'بازه زمانی: ${intl.DateFormat('HH:mm').format(record.startTime)} تا ${record.endTime != null ? intl.DateFormat('HH:mm').format(record.endTime!) : "اکنون (در حال اجرا)"}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  'تاریخ: ${JalaliDate.formatWithWeekDayAndYear(record.startTime)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (record.editNote != null && record.editNote!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'توضیح ممیزی: ${record.editNote}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.draftWarning),
                  ),
                ],
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(color: AppColors.border),
                  Text(
                    'یادداشت‌های متصل به این جلسه (${notes.length}):',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ...notes.map((n) => Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.noteType.labelFa,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: n.noteType.color,
                              ),
                            ),
                            if (n.content.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(n.content,
                                  style: const TextStyle(fontSize: 11.5)),
                            ],
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () async {
              await provider.deleteTimeRecord(record.id);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('حذف'),
          ),
          // تبدیل یک‌کلیکی کار <-> زندگی (چالش ۲)
          OutlinedButton.icon(
            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
            label: Text(
              record.isWork ? 'تبدیل به زندگی' : 'تبدیل به کار',
              style: const TextStyle(fontSize: 11.5),
            ),
            onPressed: () async {
              await provider.swapSavedRecordRealm(record.id);
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'رکورد به قلمرو ${record.isWork ? "زندگی" : "کار"} تبدیل و بانک استراحت بروزرسانی شد.',
                    ),
                  ),
                );
              }
            },
          ),
          if (!record.isOpen)
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('ویرایش'),
              onPressed: () {
                Navigator.of(ctx).pop();
                showTimeRecordEditDialog(context, record);
              },
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final palette = provider.activePalette;
    final displayedDays = _displayedDays;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCalendarToolbar(provider, palette, displayedDays),
          const SizedBox(height: 10),

          if (_calendarDisplayMode == CalendarDisplayMode.timesheet)
            const Expanded(child: ActivityLogTab())
          else ...[
            _buildStickyDayHeaders(displayedDays, palette),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  border: Border.all(color: palette.border, width: 1.0),
                ),
                child: Listener(
                  onPointerSignal: (pointerSignal) {
                    if (HardwareKeyboard.instance.isControlPressed &&
                        pointerSignal is PointerScrollEvent) {
                      final zoomDelta = -pointerSignal.scrollDelta.dy * 0.08;
                      _changeZoom(zoomDelta);
                    }
                  },
                  child: SingleChildScrollView(
                    controller: _verticalScrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTimeAxisColumn(),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: palette.border,
                        ),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: displayedDays.map((day) {
                              return Expanded(
                                child: _buildDayColumn(day, provider, palette),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendarToolbar(
    AppStateProvider provider,
    RealmPalette palette,
    List<DateTime> displayedDays,
  ) {
    return Card(
      elevation: 0,
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<CalendarDisplayMode>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                selectedBackgroundColor: palette.accent.withAlpha(45),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              segments: const [
                ButtonSegment(
                  value: CalendarDisplayMode.grid,
                  icon: Icon(Icons.calendar_view_week_rounded, size: 15),
                  label: Text('نمای تقویم'),
                ),
                ButtonSegment(
                  value: CalendarDisplayMode.timesheet,
                  icon: Icon(Icons.table_chart_rounded, size: 15),
                  label: Text('جدول تایم‌شیت'),
                ),
              ],
              selected: {_calendarDisplayMode},
              onSelectionChanged: (set) =>
                  setState(() => _calendarDisplayMode = set.first),
            ),

            if (_calendarDisplayMode == CalendarDisplayMode.grid) ...[
              // فیلتر ۳ حالته کار | زندگی | ۲۴ ساعته
              SegmentedButton<CalendarRealmFilter>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  selectedBackgroundColor: palette.accent.withAlpha(45),
                  textStyle: const TextStyle(fontSize: 11.5),
                ),
                segments: const [
                  ButtonSegment(
                    value: CalendarRealmFilter.workOnly,
                    label: Text('فقط کار'),
                  ),
                  ButtonSegment(
                    value: CalendarRealmFilter.lifeOnly,
                    label: Text('فقط زندگی'),
                  ),
                  ButtonSegment(
                    value: CalendarRealmFilter.allDay,
                    label: Text('۲۴ ساعته'),
                  ),
                ],
                selected: {_realmFilter},
                onSelectionChanged: (set) =>
                    setState(() => _realmFilter = set.first),
              ),

              SegmentedButton<CalendarViewSpan>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11.5),
                ),
                segments: const [
                  ButtonSegment(
                    value: CalendarViewSpan.day1,
                    label: Text('1D'),
                  ),
                  ButtonSegment(
                    value: CalendarViewSpan.day3,
                    label: Text('3D'),
                  ),
                  ButtonSegment(
                    value: CalendarViewSpan.day7,
                    label: Text('7D'),
                  ),
                ],
                selected: {_span},
                onSelectionChanged: (set) => setState(() => _span = set.first),
              ),

              Wrap(
                spacing: 4,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'بازه قبلی',
                    onPressed: () => _navigate(-1),
                    visualDensity: VisualDensity.compact,
                  ),
                  ActionChip(
                    label: const Text('امروز', style: TextStyle(fontSize: 11)),
                    backgroundColor: palette.surfaceElevated,
                    side: BorderSide(color: palette.border),
                    onPressed: _goToToday,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'بازه بعدی',
                    onPressed: () => _navigate(1),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatRangeHeader(displayedDays),
                    style: GoogleFonts.vazirmatn(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),

              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_rounded, size: 14),
                          tooltip: 'کاهش زوم ساعت‌ها',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _changeZoom(-15),
                        ),
                        InkWell(
                          onTap: () {
                            if (_hourHeight < 55) {
                              _setZoomPreset(60);
                            } else if (_hourHeight < 80) {
                              _setZoomPreset(90);
                            } else if (_hourHeight < 110) {
                              _setZoomPreset(130);
                            } else {
                              _setZoomPreset(45);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Text(
                              '${(_hourHeight / 60.0 * 100).round()}%',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_rounded, size: 14),
                          tooltip: 'افزایش زوم ساعت‌ها',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _changeZoom(15),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.draftWarning.withAlpha(30),
                      foregroundColor: AppColors.draftWarning,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.edit_calendar_rounded, size: 15),
                    label: const Text('ثبت دستی +',
                        style: TextStyle(fontSize: 11)),
                    onPressed: () => _showAddManualLogModal(
                      context,
                      DateTime(_focusedDate.year, _focusedDate.month,
                          _focusedDate.day, 12, 0),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: palette.accent.withAlpha(35),
                      foregroundColor: palette.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('برنامه جدید',
                        style: TextStyle(fontSize: 11)),
                    onPressed: () => _showAddBlockModal(
                      context,
                      DateTime(_focusedDate.year, _focusedDate.month,
                          _focusedDate.day, 9, 0),
                    ),
                  ),
                  IconButton(
                    tooltip: 'همگام‌سازی با Google Calendar',
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    onPressed: _isSyncing
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _isSyncing = true);
                            try {
                              await provider.syncGoogleCalendar();
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'تقویم گوگل با موفقیت همگام‌سازی شد.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } finally {
                              if (mounted) setState(() => _isSyncing = false);
                            }
                          },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStickyDayHeaders(List<DateTime> days, RealmPalette palette) {
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: palette.border, width: 1.0),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: _timeAxisWidth,
            height: 52,
            child: Center(
              child: Icon(Icons.schedule_rounded,
                  size: 15, color: AppColors.textMuted),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: palette.border),
          Expanded(
            child: Row(
              children: days.map((day) {
                final isToday = day.year == now.year &&
                    day.month == now.month &&
                    day.day == now.day;
                final jDate = JalaliDate.fromDateTime(day);
                final weekDayName = JalaliDate.getWeekDayName(day);

                return Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: palette.border,
                          width: 0.8,
                        ),
                      ),
                      color: isToday
                          ? palette.accent.withAlpha(24)
                          : Colors.transparent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                weekDayName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: isToday
                                      ? palette.accent
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (isToday && days.length <= 3) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'امروز',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          jDate.formatShort(),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isToday
                                ? palette.accent
                                : AppColors.textSecondary,
                            fontWeight: isToday ? FontWeight.bold : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeAxisColumn() {
    return SizedBox(
      width: _timeAxisWidth,
      child: Column(
        children: List.generate(24, (hour) {
          return Container(
            height: _hourHeight,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayColumn(
    DateTime day,
    AppStateProvider provider,
    RealmPalette palette,
  ) {
    final now = DateTime.now();
    final bool isToday = day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;

    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final plannedBlocks = provider.scheduledBlocks.where((b) {
      return _matchesRealmFilter(b.realm) &&
          b.startTime.isBefore(dayEnd) &&
          b.endTime.isAfter(dayStart);
    }).toList();

    final actualRecords = provider.timeRecords.where((r) {
      if (!_matchesRealmFilter(r.realm)) return false;
      final end = r.id == provider.activeRecord?.id
          ? now
          : (r.endTime ??
              r.startTime.add(Duration(seconds: r.durationSeconds)));
      return r.startTime.isBefore(dayEnd) && end.isAfter(dayStart);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final colWidth = constraints.maxWidth;
        final double halfLaneWidth =
            ((colWidth - 5.0) / 2.0).clamp(16.0, 500.0);
        const double actualLaneLeft = 1.5;
        final double plannedLaneLeft = (colWidth / 2.0) + 1.0;

        return Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: palette.border,
                width: 0.8,
              ),
            ),
            color:
                isToday ? palette.accent.withAlpha(8) : Colors.transparent,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: (details) {
              final double clickedY = details.localPosition.dy;
              final int hour = (clickedY / _hourHeight).floor().clamp(0, 23);
              _showAddBlockModal(
                context,
                dayStart.add(Duration(hours: hour)),
              );
            },
            child: SizedBox(
              height: 24 * _hourHeight,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: colWidth / 2.0,
                    width: 0.8,
                    child: Container(color: Colors.white.withAlpha(10)),
                  ),
                  ...List.generate(24, (hour) {
                    final top = hour * _hourHeight;
                    return Positioned(
                      top: top,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 1,
                            color: Colors.white.withAlpha(12),
                          ),
                          SizedBox(height: _hourHeight / 2 - 1),
                          Container(
                            height: 1,
                            color: Colors.white.withAlpha(5),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (isToday)
                    Positioned(
                      top: (now.hour * _hourHeight) +
                          (now.minute * _hourHeight / 60.0),
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1.5,
                              color: Colors.redAccent.withAlpha(200),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ۱. لاین برنامه‌ریزی (Planned Blocks)
                  ...plannedBlocks.map((b) {
                    final isThisActive = _activeDragId == b.id;
                    final effectiveStart =
                        b.startTime.isBefore(dayStart) ? dayStart : b.startTime;
                    final effectiveEnd =
                        b.endTime.isAfter(dayEnd) ? dayEnd : b.endTime;

                    if (!effectiveEnd.isAfter(effectiveStart)) {
                      return const SizedBox.shrink();
                    }

                    final double baseTop = (effectiveStart.hour * _hourHeight) +
                        (effectiveStart.minute * _hourHeight / 60.0) +
                        (effectiveStart.second * _hourHeight / 3600.0);
                    final double durationMins = (effectiveEnd
                                .difference(effectiveStart)
                                .inSeconds /
                            60.0)
                        .clamp(4.0, 1440.0);
                    final double baseHeight = (durationMins * _hourHeight / 60.0)
                        .clamp(20.0, 24 * _hourHeight);

                    double renderedTop = baseTop;
                    double renderedHeight = baseHeight;

                    if (isThisActive) {
                      if (_isResizingBottom) {
                        renderedHeight = (baseHeight + _dragAccumulatedDy)
                            .clamp(20.0, 24 * _hourHeight);
                      } else if (_isResizingTop) {
                        renderedTop = (baseTop + _dragAccumulatedDy)
                            .clamp(0.0, 24 * _hourHeight);
                        renderedHeight = (baseHeight - _dragAccumulatedDy)
                            .clamp(20.0, 24 * _hourHeight);
                      } else {
                        renderedTop = (baseTop + _dragAccumulatedDy)
                            .clamp(0.0, 24 * _hourHeight);
                      }
                    }

                    final project = provider.getProjectById(b.projectId);
                    final fallbackCol =
                        b.isLife ? AppColors.lifeGreen : AppColors.workBlue;
                    final Color pColor = project != null
                        ? Color(int.parse(
                            project.colorHex.replaceFirst('#', '0xFF')))
                        : fallbackCol;

                    return Positioned(
                      top: renderedTop,
                      left: plannedLaneLeft,
                      width: halfLaneWidth,
                      height: renderedHeight,
                      child: _InteractiveCalendarBlock(
                        id: b.id,
                        title: b.title,
                        startTime: effectiveStart,
                        endTime: effectiveEnd,
                        color: pColor,
                        isPlanned: true,
                        height: renderedHeight,
                        onTap: () =>
                            _showBlockDetailsModal(context, b, project),
                        onDragStart: () {
                          setState(() {
                            _activeDragId = b.id;
                            _dragAccumulatedDy = 0.0;
                            _isResizingTop = false;
                            _isResizingBottom = false;
                          });
                        },
                        onDragUpdate: (dy) {
                          setState(() => _dragAccumulatedDy += dy);
                        },
                        onDragEnd: () async {
                          final deltaMinutes =
                              ((_dragAccumulatedDy / _hourHeight * 60.0) / 5.0)
                                      .round() *
                                  5;
                          setState(() {
                            _activeDragId = null;
                            _dragAccumulatedDy = 0.0;
                          });
                          if (deltaMinutes != 0) {
                            final newStart =
                                b.startTime.add(Duration(minutes: deltaMinutes));
                            final newEnd =
                                b.endTime.add(Duration(minutes: deltaMinutes));
                            await provider.saveScheduledBlock(
                              b.copyWith(startTime: newStart, endTime: newEnd),
                            );
                          }
                        },
                        onResizeBottomUpdate: (dy) {
                          setState(() {
                            _activeDragId = b.id;
                            _isResizingBottom = true;
                            _dragAccumulatedDy += dy;
                          });
                        },
                        onResizeBottomEnd: () async {
                          final deltaMinutes =
                              ((_dragAccumulatedDy / _hourHeight * 60.0) / 5.0)
                                      .round() *
                                  5;
                          setState(() {
                            _activeDragId = null;
                            _isResizingBottom = false;
                            _dragAccumulatedDy = 0.0;
                          });
                          if (deltaMinutes != 0) {
                            final candidateEnd =
                                b.endTime.add(Duration(minutes: deltaMinutes));
                            if (candidateEnd.difference(b.startTime).inMinutes >=
                                5) {
                              await provider.saveScheduledBlock(
                                b.copyWith(endTime: candidateEnd),
                              );
                            }
                          }
                        },
                      ),
                    );
                  }),

                  // ۲. لاین عملکرد واقعی (Actual TimeRecords)
                  ...actualRecords.map((r) {
                    final isThisActive = _activeDragId == r.id;
                    final fullEnd = r.id == provider.activeRecord?.id
                        ? now
                        : (r.endTime ??
                            r.startTime
                                .add(Duration(seconds: r.durationSeconds)));
                    final effectiveStart =
                        r.startTime.isBefore(dayStart) ? dayStart : r.startTime;
                    final effectiveEnd =
                        fullEnd.isAfter(dayEnd) ? dayEnd : fullEnd;

                    if (!effectiveEnd.isAfter(effectiveStart)) {
                      return const SizedBox.shrink();
                    }

                    final double baseTop = (effectiveStart.hour * _hourHeight) +
                        (effectiveStart.minute * _hourHeight / 60.0) +
                        (effectiveStart.second * _hourHeight / 3600.0);
                    final double durationMins = (effectiveEnd
                                .difference(effectiveStart)
                                .inSeconds /
                            60.0)
                        .clamp(4.0, 1440.0);
                    final double baseHeight = (durationMins * _hourHeight / 60.0)
                        .clamp(20.0, 24 * _hourHeight);

                    double renderedTop = baseTop;
                    double renderedHeight = baseHeight;

                    if (isThisActive) {
                      if (_isResizingBottom) {
                        renderedHeight = (baseHeight + _dragAccumulatedDy)
                            .clamp(20.0, 24 * _hourHeight);
                      } else {
                        renderedTop = (baseTop + _dragAccumulatedDy)
                            .clamp(0.0, 24 * _hourHeight);
                      }
                    }

                    final project = provider.getProjectById(r.projectId);
                    final outcome = r.outcomeId != null
                        ? provider.getOutcomeById(r.outcomeId!)
                        : null;

                    final Color col = r.isLife
                        ? AppColors.lifeGreen
                        : (r.isStopwatch
                            ? AppColors.stopwatch
                            : AppColors.workBlue);

                    final bool isManual = r.tagIds.contains('دستی') ||
                        r.tagIds.contains('manual') ||
                        r.isEdited;

                    final title = outcome?.title ??
                        (r.titleSnapshot.isEmpty
                            ? 'تسک بدون عنوان'
                            : r.titleSnapshot);

                    return Positioned(
                      top: renderedTop,
                      left: actualLaneLeft,
                      width: halfLaneWidth,
                      height: renderedHeight,
                      child: _InteractiveCalendarBlock(
                        id: r.id,
                        title: title,
                        startTime: effectiveStart,
                        endTime: effectiveEnd,
                        color: col,
                        isPlanned: false,
                        isManual: isManual,
                        isLife: r.isLife,
                        isStopwatch: r.isStopwatch,
                        height: renderedHeight,
                        onTap: () => _showRecordDetailsModal(
                            context, r, project, outcome),
                        onDragStart: () {
                          if (r.isOpen) return;
                          setState(() {
                            _activeDragId = r.id;
                            _dragAccumulatedDy = 0.0;
                            _isResizingBottom = false;
                          });
                        },
                        onDragUpdate: (dy) {
                          if (r.isOpen) return;
                          setState(() => _dragAccumulatedDy += dy);
                        },
                        onDragEnd: () async {
                          if (r.isOpen) return;
                          final deltaMinutes =
                              ((_dragAccumulatedDy / _hourHeight * 60.0) / 5.0)
                                      .round() *
                                  5;
                          setState(() {
                            _activeDragId = null;
                            _dragAccumulatedDy = 0.0;
                          });
                          if (deltaMinutes != 0) {
                            final newStart = r.startTime
                                .add(Duration(minutes: deltaMinutes));
                            final newEnd = r.endTime
                                    ?.add(Duration(minutes: deltaMinutes)) ??
                                newStart
                                    .add(Duration(seconds: r.durationSeconds));
                            await provider.updateTimeRecordTimes(
                              id: r.id,
                              newStartTime: newStart,
                              newEndTime: newEnd,
                              editNote: 'جابه‌جایی دستی در تقویم',
                            );
                          }
                        },
                        onResizeBottomUpdate: (dy) {
                          if (r.isOpen) return;
                          setState(() {
                            _activeDragId = r.id;
                            _isResizingBottom = true;
                            _dragAccumulatedDy += dy;
                          });
                        },
                        onResizeBottomEnd: () async {
                          if (r.isOpen) return;
                          final deltaMinutes =
                              ((_dragAccumulatedDy / _hourHeight * 60.0) / 5.0)
                                      .round() *
                                  5;
                          setState(() {
                            _activeDragId = null;
                            _isResizingBottom = false;
                            _dragAccumulatedDy = 0.0;
                          });
                          if (deltaMinutes != 0) {
                            final oldEnd = r.endTime ??
                                r.startTime
                                    .add(Duration(seconds: r.durationSeconds));
                            final candidateEnd =
                                oldEnd.add(Duration(minutes: deltaMinutes));
                            final newDurationSec =
                                candidateEnd.difference(r.startTime).inSeconds;
                            if (newDurationSec >= 60) {
                              await provider.updateTimeRecordTimes(
                                id: r.id,
                                newStartTime: r.startTime,
                                newEndTime: candidateEnd,
                                editNote: 'تغییر بازه زمانی در تقویم',
                              );
                            }
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InteractiveCalendarBlock extends StatelessWidget {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final Color color;
  final bool isPlanned;
  final bool isManual;
  final bool isLife;
  final bool isStopwatch;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final ValueChanged<double> onResizeBottomUpdate;
  final VoidCallback onResizeBottomEnd;

  const _InteractiveCalendarBlock({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.color,
    this.isPlanned = false,
    this.isManual = false,
    this.isLife = false,
    this.isStopwatch = false,
    required this.height,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeBottomUpdate,
    required this.onResizeBottomEnd,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${intl.DateFormat('HH:mm').format(startTime)} - ${intl.DateFormat('HH:mm').format(endTime)}';

    return GestureDetector(
      onVerticalDragStart: (_) => onDragStart(),
      onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
      onVerticalDragEnd: (_) => onDragEnd(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              color:
                  isPlanned ? color.withAlpha(30) : color.withAlpha(205),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isPlanned
                    ? color.withAlpha(160)
                    : Colors.white.withAlpha(50),
                width: 0.9,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isPlanned ? 35 : 70),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3.5, vertical: 2),
                      child: _buildAdaptiveContent(timeStr),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 7,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (d) =>
                          onResizeBottomUpdate(d.delta.dy),
                      onVerticalDragEnd: (_) => onResizeBottomEnd(),
                      child: Center(
                        child: Container(
                          width: 18,
                          height: 2.2,
                          decoration: BoxDecoration(
                            color: isPlanned
                                ? color.withAlpha(180)
                                : Colors.white.withAlpha(180),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdaptiveContent(String timeStr) {
    final textColor = isPlanned ? color : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isVeryNarrow = availableWidth < 52.0;
        final canShowManualBadge = availableWidth >= 66.0;

        Widget? manualBadgeWidget;
        if (isManual) {
          if (canShowManualBadge) {
            manualBadgeWidget = Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.draftWarning.withAlpha(60),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'دستی',
                style: TextStyle(
                  fontSize: 7.5,
                  color: AppColors.draftWarning,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          } else {
            manualBadgeWidget = Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: AppColors.draftWarning,
                shape: BoxShape.circle,
              ),
            );
          }
        }

        if (availableWidth < 22.0) {
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _buildLeadingIcon(size: 8),
            ),
          );
        }

        if (height < 28.0) {
          return Row(
            children: [
              if (availableWidth >= 26.0) ...[
                _buildLeadingIcon(size: 9),
                const SizedBox(width: 2),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              if (manualBadgeWidget != null && availableWidth >= 32.0) ...[
                const SizedBox(width: 2),
                manualBadgeWidget,
              ],
            ],
          );
        } else if (height < 46.0) {
          return Row(
            children: [
              if (availableWidth >= 26.0) ...[
                _buildLeadingIcon(size: 10),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              if (manualBadgeWidget != null && availableWidth >= 34.0) ...[
                const SizedBox(width: 2),
                manualBadgeWidget,
              ],
              if (!isVeryNarrow) ...[
                const SizedBox(width: 3),
                Flexible(
                  fit: FlexFit.loose,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      intl.DateFormat('HH:mm').format(startTime),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8.0,
                        color: isPlanned ? AppColors.textMuted : Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _buildLeadingIcon(size: 10),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: height > 70 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (manualBadgeWidget != null) ...[
                    const SizedBox(width: 2),
                    manualBadgeWidget,
                  ],
                ],
              ),
              const SizedBox(height: 1.5),
              Flexible(
                fit: FlexFit.loose,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    timeStr,
                    maxLines: 1,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8.5,
                      color: isPlanned ? AppColors.textMuted : Colors.white70,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildLeadingIcon({required double size}) {
    if (isPlanned) {
      return Container(
        width: size - 3,
        height: size - 3,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    final iconData = isLife
        ? Icons.spa_rounded
        : (isStopwatch
            ? Icons.timer_outlined
            : Icons.check_circle_outline_rounded);
    return Icon(iconData, size: size, color: Colors.white);
  }
}
