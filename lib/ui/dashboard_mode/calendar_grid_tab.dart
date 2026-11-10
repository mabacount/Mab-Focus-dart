import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../core/jalali_date.dart';
import '../../models/project_node.dart';
import '../../models/scheduled_block.dart';
import '../../models/task_log_entry.dart';
import '../../providers/app_state_provider.dart';
import '../shared/unified_project_selector.dart';
import 'activity_log_tab.dart';

enum CalendarViewSpan { day1, day3, day7 }
enum CalendarDisplayMode { grid, timesheet }

class CalendarGridTab extends StatefulWidget {
  const CalendarGridTab({super.key});

  @override
  State<CalendarGridTab> createState() => _CalendarGridTabState();
}

class _CalendarGridTabState extends State<CalendarGridTab> {
  CalendarViewSpan _span = CalendarViewSpan.day7;
  CalendarDisplayMode _calendarDisplayMode = CalendarDisplayMode.grid;
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
    final cleanFocus =
        DateTime(_focusedDate.year, _focusedDate.month, _focusedDate.day);

    if (_span == CalendarViewSpan.day7) {
      final int daysSinceSaturday = (_focusedDate.weekday == DateTime.sunday)
          ? 1
          : (_focusedDate.weekday == DateTime.saturday
              ? 0
              : _focusedDate.weekday + 1);
      final startOfSat =
          cleanFocus.subtract(Duration(days: daysSinceSaturday));
      return List.generate(7, (i) => startOfSat.add(Duration(days: i)));
    } else if (_span == CalendarViewSpan.day3) {
      final start = cleanFocus.subtract(const Duration(days: 1));
      return List.generate(3, (i) => start.add(Duration(days: i)));
    } else {
      return [cleanFocus];
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

  /// ثبت گزارش کار دستی (با تگ «دستی»)
  void _showAddManualLogModal(BuildContext context, DateTime defaultStart) {
    final provider = context.read<AppStateProvider>();
    final titleCtrl = TextEditingController();
    String? selectedMacroId;
    String? selectedSubId;
    DateTime start = defaultStart;
    DateTime end = defaultStart.add(const Duration(minutes: 30));
    String entryType = 'work';

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final durationMin = end.difference(start).inMinutes;

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.focus.withAlpha(35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_edu_rounded,
                        color: AppColors.focus, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('ثبت گزارش کارکرد دستی (تگ دستی)',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'عنوان فعالیت انجام‌شده',
                        hintText: 'مثلاً: جلسه حضوری با کارفرما',
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'work',
                            label: Text('کار / تمرکز'),
                            icon: Icon(Icons.work_rounded, size: 14)),
                        ButtonSegment(
                            value: 'short_break',
                            label: Text('استراحت / زندگی'),
                            icon: Icon(Icons.coffee_rounded, size: 14)),
                        ButtonSegment(
                            value: 'stopwatch',
                            label: Text('کرنومتر آزاد'),
                            icon: Icon(Icons.timer_outlined, size: 14)),
                      ],
                      selected: {entryType},
                      onSelectionChanged: (set) =>
                          setModalState(() => entryType = set.first),
                    ),
                    const SizedBox(height: 12),
                    UnifiedProjectSelector(
                      projects: provider.projects,
                      selectedMacroId: selectedMacroId,
                      selectedSubId: selectedSubId,
                      onSelected: (mId, sId) {
                        setModalState(() {
                          selectedMacroId = mId;
                          selectedSubId = sId;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
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
                                  if (end.isBefore(start)) {
                                    end = start.add(const Duration(minutes: 30));
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
                              'پایان: ${intl.DateFormat('HH:mm').format(end)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              final p = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay.fromDateTime(end),
                              );
                              if (p != null) {
                                setModalState(() {
                                  end = DateTime(end.year, end.month, end.day,
                                      p.hour, p.minute);
                                });
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
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.draftWarning.withAlpha(40),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('برچسب: دستی',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: AppColors.draftWarning,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'مدت: $durationMin دقیقه (${JalaliDate.formatWithWeekDay(start)})',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('انصراف'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('ثبت گزارش دستی'),
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    await provider.createManualTaskLog(
                      title: titleCtrl.text.trim(),
                      macroProjectId: selectedMacroId,
                      subProjectId: selectedSubId,
                      startTime: start,
                      endTime: end,
                      entryType: entryType,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// افزودن بلوک برنامه‌ریزی‌شده
  void _showAddBlockModal(BuildContext context, DateTime defaultStart) {
    final provider = context.read<AppStateProvider>();
    final titleCtrl = TextEditingController();
    String? selectedMacroId;
    String? selectedSubId;
    DateTime start = defaultStart;
    DateTime end = defaultStart.add(const Duration(hours: 1));

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final durationMin = end.difference(start).inMinutes;

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.focus.withAlpha(35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.event_note_rounded,
                        color: AppColors.focus, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('برنامه‌ریزی بلوک زمانی جدید',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'عنوان برنامه (مثلاً: کدنویسی ماژول پرداخت)',
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    UnifiedProjectSelector(
                      projects: provider.projects,
                      selectedMacroId: selectedMacroId,
                      selectedSubId: selectedSubId,
                      onSelected: (mId, sId) {
                        setModalState(() {
                          selectedMacroId = mId;
                          selectedSubId = sId;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
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
                                  if (end.isBefore(start)) {
                                    end = start.add(const Duration(hours: 1));
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
                              'پایان: ${intl.DateFormat('HH:mm').format(end)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              final p = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay.fromDateTime(end),
                              );
                              if (p != null) {
                                setModalState(() {
                                  end = DateTime(end.year, end.month, end.day,
                                      p.hour, p.minute);
                                });
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
                        'مدت زمان برنامه‌ریزی: $durationMin دقیقه (${JalaliDate.formatWithWeekDay(start)})',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('انصراف'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('ثبت در تقویم'),
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    final block = ScheduledBlock(
                      id: const Uuid().v4(),
                      title: titleCtrl.text.trim(),
                      projectId: selectedSubId ?? selectedMacroId,
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
    );
  }

  void _showBlockDetailsModal(
      BuildContext context, ScheduledBlock block, ProjectNode? project) {
    final provider = context.read<AppStateProvider>();
    final color = project != null
        ? Color(int.parse(project.colorHex.replaceFirst('#', '0xFF')))
        : AppColors.focus;

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
            if (block.source == 'gcal')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Google Calendar',
                    style:
                        TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
              ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (project != null) ...[
              Text('پروژه: ${project.name}',
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
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('بستن'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: color),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('شروع فوری کار روی این تسک'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await provider.startInstantWork(
                title: block.title,
                macroProjectId: project?.isSubProject == true
                    ? project?.parentId
                    : project?.id,
                subProjectId:
                    project?.isSubProject == true ? project?.id : null,
              );
            },
          ),
        ],
      ),
    );
  }

  void _showLogDetailsModal(
      BuildContext context, TaskLogEntry log, ProjectNode? project) {
    final provider = context.read<AppStateProvider>();
    final color = log.isBreakEntry
        ? AppColors.breakTime
        : (log.isStopwatch ? AppColors.stopwatch : AppColors.focus);
    final isManual = log.tagIds.contains('دستی') ||
        log.tagIds.contains('manual') ||
        log.isEdited;

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
              log.isBreakEntry
                  ? Icons.coffee_rounded
                  : (log.isStopwatch
                      ? Icons.timer_outlined
                      : Icons.work_rounded),
              color: color,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                log.title.isEmpty ? 'تسک بدون عنوان' : log.title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            if (isManual)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.draftWarning.withAlpha(35),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('ثبت دستی',
                    style: TextStyle(
                        fontSize: 9.5,
                        color: AppColors.draftWarning,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (project != null) ...[
              Text('پروژه: ${project.name}',
                  style: TextStyle(fontSize: 13, color: color)),
              const SizedBox(height: 6),
            ],
            Text(
              'نوع: ${log.isBreakEntry ? "استراحت / زندگی" : (log.isStopwatch ? "کرنومتر آزاد" : "پومودورو هدفمند")}',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'مدت واقعی: ${log.durationSeconds ~/ 60} دقیقه و ${log.durationSeconds % 60} ثانیه',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              'بازه زمانی: ${intl.DateFormat('HH:mm').format(log.startTime)} تا ${log.endTime != null ? intl.DateFormat('HH:mm').format(log.endTime!) : "اکنون"}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'تاریخ: ${JalaliDate.formatWithWeekDayAndYear(log.startTime)}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (log.editNote != null && log.editNote!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'توضیح ویرایش: ${log.editNote}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.draftWarning),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.draftWarning),
            onPressed: () async {
              await provider.deleteTaskLog(log.id);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('حذف لاگ'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('متوجه شدم'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final displayedDays = _displayedDays;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ۱. نوار ابزار و کنترل زوم تقویم
          _buildCalendarToolbar(provider, displayedDays),
          const SizedBox(height: 10),

          if (_calendarDisplayMode == CalendarDisplayMode.timesheet)
            const Expanded(
              child: ActivityLogTab(),
            )
          else ...[
            // ۲. هدر روزها (ثابت بالای اسکرولر)
            _buildStickyDayHeaders(displayedDays),

            // ۳. شبکه ساعت‌ها با امکان اسکرول همگام و زوم ماوس (Ctrl + Scroll)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  border: Border.all(color: AppColors.border, width: 1.0),
                ),
                child: Listener(
                  onPointerSignal: (pointerSignal) {
                    // پشتیبانی از زوم روان با نگه داشتن کلید Ctrl و چرخ ماوس
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
                        // ستون ساعت‌ها (00:00 تا 23:00)
                        _buildTimeAxisColumn(),

                        const VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: AppColors.border,
                        ),

                        // ستون‌های روزها
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: displayedDays.map((day) {
                              return Expanded(
                                child: _buildDayColumn(day, provider),
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

  /// نوار ابزار بالای تقویم با کنترل‌های زوم و ثبت دستی
  Widget _buildCalendarToolbar(
      AppStateProvider provider, List<DateTime> displayedDays) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // سوییچر حالت اصلی: نمای تقویم هوشمند / جدول تایم‌شیت و کارکرد
            SegmentedButton<CalendarDisplayMode>(
              showSelectedIcon: true,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: CalendarDisplayMode.grid,
                  icon: Icon(Icons.calendar_view_week_rounded, size: 16),
                  label: Text('نمای تقویم'),
                ),
                ButtonSegment(
                  value: CalendarDisplayMode.timesheet,
                  icon: Icon(Icons.table_chart_rounded, size: 16),
                  label: Text('جدول تایم‌شیت و کارکرد'),
                ),
              ],
              selected: {_calendarDisplayMode},
              onSelectionChanged: (set) =>
                  setState(() => _calendarDisplayMode = set.first),
            ),

            if (_calendarDisplayMode == CalendarDisplayMode.grid) ...[
              // سوییچر نماها: روزانه، ۳ روزه، هفتگی
              SegmentedButton<CalendarViewSpan>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11.5),
                ),
                segments: const [
                  ButtonSegment(
                    value: CalendarViewSpan.day1,
                    label: Text('روزانه (1D)'),
                  ),
                  ButtonSegment(
                    value: CalendarViewSpan.day3,
                    label: Text('۳ روزه (3D)'),
                  ),
                  ButtonSegment(
                    value: CalendarViewSpan.day7,
                    label: Text('هفتگی (7D)'),
                  ),
                ],
                selected: {_span},
                onSelectionChanged: (set) => setState(() => _span = set.first),
              ),

            // ناوبری بازه زمانی و عنوان تاریخ شمسی
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'بازه قبلی',
                  onPressed: () => _navigate(-1),
                  visualDensity: VisualDensity.compact,
                ),
                ActionChip(
                  label: const Text('امروز', style: TextStyle(fontSize: 11.5)),
                  backgroundColor: AppColors.surfaceElevated,
                  side: const BorderSide(color: AppColors.border),
                  onPressed: _goToToday,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'بازه بعدی',
                  onPressed: () => _navigate(1),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Text(
                  _formatRangeHeader(displayedDays),
                  style: GoogleFonts.vazirmatn(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),

            // کنترل زوم محور زمان (سایز ساعت‌ها)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
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
                          // تغییر چرخشی بین پیش‌فرض‌ها
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
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            'زوم: ${(_hourHeight / 60.0 * 100).round()}%',
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
                        tooltip: 'افزایش زوم ساعت‌ها (مشاهده تسک‌های ریز)',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _changeZoom(15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // دکمه ثبت گزارش کارکرد دستی
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.draftWarning.withAlpha(30),
                    foregroundColor: AppColors.draftWarning,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.edit_calendar_rounded, size: 15),
                  label: const Text('گزارش دستی +',
                      style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _showAddManualLogModal(
                    context,
                    DateTime(_focusedDate.year, _focusedDate.month,
                        _focusedDate.day, 12, 0),
                  ),
                ),
                const SizedBox(width: 6),

                // دکمه افزودن برنامه جدید
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('برنامه جدید',
                      style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _showAddBlockModal(
                    context,
                    DateTime(_focusedDate.year, _focusedDate.month,
                        _focusedDate.day, 9, 0),
                  ),
                ),
                const SizedBox(width: 6),

                // دکمه همگام‌سازی گوگل کلندر
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

  /// هدر روزها (ثابت بالای اسکرولر)
  Widget _buildStickyDayHeaders(List<DateTime> days) {
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: AppColors.border, width: 1.0),
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
          const VerticalDivider(
              width: 1, thickness: 1, color: AppColors.border),
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
                          color: AppColors.border.withAlpha(80),
                          width: 0.8,
                        ),
                      ),
                      color: isToday
                          ? AppColors.focus.withAlpha(20)
                          : Colors.transparent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              weekDayName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isToday
                                    ? AppColors.focus
                                    : AppColors.textPrimary,
                              ),
                            ),
                            if (isToday) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.focus,
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
                                ? AppColors.focus
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

  /// ستون ساعت‌ها (00:00 تا 23:00) بر اساس مقدار داینامیک _hourHeight
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

  /// ستون هر روز شامل ۲ لاین موازی: برنامه‌ریزی (Planned) و عملکرد واقعی (Actual)
  /// با پشتیبانی از کشیدن لبه‌ها و درگ تغییر زمان
  Widget _buildDayColumn(DateTime day, AppStateProvider provider) {
    final now = DateTime.now();
    final bool isToday = day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;

    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final plannedBlocks = provider.scheduledBlocks.where((b) {
      return b.startTime.isBefore(dayEnd) && b.endTime.isAfter(dayStart);
    }).toList();

    final actualLogs = provider.taskLogs.where((l) {
      final end = l.endTime ?? l.startTime;
      return l.startTime.isBefore(dayEnd) && end.isAfter(dayStart);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final colWidth = constraints.maxWidth;
        // تقسیم دقیق ستون روز به دو لاین مجزا بدون همپوشانی: عملکرد واقعی (چپ) و برنامه‌ریزی (راست)
        final double halfLaneWidth =
            ((colWidth - 5.0) / 2.0).clamp(16.0, 500.0);
        final double actualLaneLeft = 1.5;
        final double plannedLaneLeft = (colWidth / 2.0) + 1.0;

        return Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AppColors.border.withAlpha(90),
                width: 0.8,
              ),
            ),
            color: isToday ? AppColors.focus.withAlpha(6) : Colors.transparent,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: (details) {
              final double clickedY = details.localPosition.dy;
              final int hour =
                  (clickedY / _hourHeight).floor().clamp(0, 23);
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
                  // خط جداکننده محو بین لاین عملکرد و برنامه‌ریزی
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: colWidth / 2.0,
                    width: 0.8,
                    child: Container(
                      color: Colors.white.withAlpha(10),
                    ),
                  ),

                  // خطوط افقی ساعت‌ها و نیم‌ساعت‌ها
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

                  // خط قرمز زمان حال
                  if (isToday) ...[
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
                  ],

                  // ۱. لاین برنامه‌ریزی (Planned Blocks) - سمت راست ستون
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
                    final double baseHeight =
                        (durationMins * _hourHeight / 60.0).clamp(20.0, 24 * _hourHeight);

                    double renderedTop = baseTop;
                    double renderedHeight = baseHeight;

                    if (isThisActive) {
                      if (_isResizingBottom) {
                        renderedHeight =
                            (baseHeight + _dragAccumulatedDy).clamp(20.0, 24 * _hourHeight);
                      } else if (_isResizingTop) {
                        renderedTop = (baseTop + _dragAccumulatedDy).clamp(0.0, 24 * _hourHeight);
                        renderedHeight =
                            (baseHeight - _dragAccumulatedDy).clamp(20.0, 24 * _hourHeight);
                      } else {
                        renderedTop = (baseTop + _dragAccumulatedDy).clamp(0.0, 24 * _hourHeight);
                      }
                    }

                    final project = provider.projects.cast<ProjectNode?>().firstWhere(
                          (p) => p?.id == b.projectId,
                          orElse: () => null,
                        );

                    final Color pColor = project != null
                        ? Color(int.parse(
                            project.colorHex.replaceFirst('#', '0xFF')))
                        : AppColors.focus;

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
                          setState(() {
                            _dragAccumulatedDy += dy;
                          });
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
                            final newStart = b.startTime
                                .add(Duration(minutes: deltaMinutes));
                            final newEnd = b.endTime
                                .add(Duration(minutes: deltaMinutes));
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
                            final candidateEnd = b.endTime
                                .add(Duration(minutes: deltaMinutes));
                            if (candidateEnd.difference(b.startTime).inMinutes >= 5) {
                              await provider.saveScheduledBlock(
                                b.copyWith(endTime: candidateEnd),
                              );
                            }
                          }
                        },
                      ),
                    );
                  }),

                  // ۲. لاین عملکرد واقعی (Actual Task Logs) - سمت چپ ستون
                  ...actualLogs.map((l) {
                    final isThisActive = _activeDragId == l.id;
                    final fullEnd = l.endTime ??
                        l.startTime.add(Duration(seconds: l.durationSeconds));
                    final effectiveStart =
                        l.startTime.isBefore(dayStart) ? dayStart : l.startTime;
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
                    final double baseHeight =
                        (durationMins * _hourHeight / 60.0).clamp(20.0, 24 * _hourHeight);

                    double renderedTop = baseTop;
                    double renderedHeight = baseHeight;

                    if (isThisActive) {
                      if (_isResizingBottom) {
                        renderedHeight =
                            (baseHeight + _dragAccumulatedDy).clamp(20.0, 24 * _hourHeight);
                      } else {
                        renderedTop = (baseTop + _dragAccumulatedDy).clamp(0.0, 24 * _hourHeight);
                      }
                    }

                    final project = provider.projects.cast<ProjectNode?>().firstWhere(
                          (p) => p?.id == (l.subProjectId ?? l.macroProjectId),
                          orElse: () => null,
                        );

                    final Color col = l.isBreakEntry
                        ? AppColors.breakTime
                        : (l.isStopwatch
                            ? AppColors.stopwatch
                            : AppColors.focus);

                    final bool isManual = l.tagIds.contains('دستی') ||
                        l.tagIds.contains('manual') ||
                        l.isEdited;

                    return Positioned(
                      top: renderedTop,
                      left: actualLaneLeft,
                      width: halfLaneWidth,
                      height: renderedHeight,
                      child: _InteractiveCalendarBlock(
                        id: l.id,
                        title: l.title.isEmpty ? 'تسک بدون عنوان' : l.title,
                        startTime: effectiveStart,
                        endTime: effectiveEnd,
                        color: col,
                        isPlanned: false,
                        isManual: isManual,
                        isBreak: l.isBreakEntry,
                        isStopwatch: l.isStopwatch,
                        height: renderedHeight,
                        onTap: () => _showLogDetailsModal(context, l, project),
                        onDragStart: () {
                          setState(() {
                            _activeDragId = l.id;
                            _dragAccumulatedDy = 0.0;
                            _isResizingBottom = false;
                          });
                        },
                        onDragUpdate: (dy) {
                          setState(() {
                            _dragAccumulatedDy += dy;
                          });
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
                            final newStart = l.startTime
                                .add(Duration(minutes: deltaMinutes));
                            final newEnd = l.endTime?.add(Duration(minutes: deltaMinutes)) ??
                                newStart.add(Duration(seconds: l.durationSeconds));
                            await provider.updateTaskLogTimes(
                              id: l.id,
                              newStartTime: newStart,
                              newEndTime: newEnd,
                              editNote: 'جابه‌جایی دستی در تقویم',
                            );
                          }
                        },
                        onResizeBottomUpdate: (dy) {
                          setState(() {
                            _activeDragId = l.id;
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
                            final oldEnd = l.endTime ??
                                l.startTime.add(Duration(seconds: l.durationSeconds));
                            final candidateEnd =
                                oldEnd.add(Duration(minutes: deltaMinutes));
                            final newDurationSec =
                                candidateEnd.difference(l.startTime).inSeconds;
                            if (newDurationSec >= 60) {
                              await provider.updateTaskLogTimes(
                                id: l.id,
                                newStartTime: l.startTime,
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

/// کامپوننت تعاملی بلوک‌های تقویم با چینش تطبیقی بر اساس ارتفاع (بدون هرگونه سرریز متنی)
/// و پشتیبانی از جابه‌جایی عمودی و کشیدن لبه پایینی برای تغییر اندازه
class _InteractiveCalendarBlock extends StatelessWidget {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final Color color;
  final bool isPlanned;
  final bool isManual;
  final bool isBreak;
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
    this.isBreak = false,
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
              color: isPlanned
                  ? color.withAlpha(30)
                  : color.withAlpha(200),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isPlanned ? color.withAlpha(160) : Colors.white.withAlpha(50),
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
                // محتوای کارت با چینش تطبیقی (بدون ایجاد خطای سرریز Overflow)
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

                // هندل تغییر اندازه انتهای بلوک در لبه پایینی
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

  /// چینش هوشمند محتوا با توجه به عرض و ارتفاع در دسترس جهت جلوگیری قطعی از Overflow
  Widget _buildAdaptiveContent(String timeStr) {
    final textColor = isPlanned ? color : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isVeryNarrow = availableWidth < 52.0;
        final canShowManualBadge = availableWidth >= 66.0;

        // ویجت برچسب دستی: در صورت باریک بودن ستون نقطه کهربایی، در صورت داشتن فضا برچسب متنی
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

        if (height < 28.0) {
          // تسک‌های بسیار کوتاه (کمتر از ۲۸ پیکسل): فقط یک ردیف فشرده
          return Row(
            children: [
              _buildLeadingIcon(size: 9),
              const SizedBox(width: 2),
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
              if (manualBadgeWidget != null) ...[
                const SizedBox(width: 2),
                manualBadgeWidget,
              ],
            ],
          );
        } else if (height < 46.0) {
          // تسک‌های متوسط (۲۸ تا ۴۶ پیکسل): عنوان و زمان در یک ردیف
          return Row(
            children: [
              _buildLeadingIcon(size: 10),
              const SizedBox(width: 3),
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
              if (manualBadgeWidget != null) ...[
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
          // تسک‌های کامل (بیشتر از ۴۶ پیکسل): چینش دوخطی بدون سرریز
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
    final iconData = isBreak
        ? Icons.coffee_rounded
        : (isStopwatch
            ? Icons.timer_outlined
            : Icons.check_circle_outline_rounded);
    return Icon(iconData, size: size, color: Colors.white);
  }
}
