import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../models/scheduled_block.dart';
import '../../providers/app_state_provider.dart';
import '../shared/unified_project_selector.dart';

enum CalendarViewSpan { day1, day3, day7 }

class CalendarGridTab extends StatefulWidget {
  const CalendarGridTab({super.key});

  @override
  State<CalendarGridTab> createState() => _CalendarGridTabState();
}

class _CalendarGridTabState extends State<CalendarGridTab> {
  CalendarViewSpan _span = CalendarViewSpan.day3;
  DateTime _focusedDate = DateTime.now();

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
    final start =
        DateTime(_focusedDate.year, _focusedDate.month, _focusedDate.day);
    return List.generate(_daysCount, (i) => start.add(Duration(days: i)));
  }

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
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text('برنامه‌ریزی بلوک زمانی جدید (Scheduled Block)',
                  style: TextStyle(fontSize: 15)),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText:
                            'عنوان برنامه (مثلاً: پیاده‌سازی احراز هویت)',
                        border: OutlineInputBorder(),
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
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(
                                'شروع: ${DateFormat('HH:mm').format(start)}'),
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
                            icon:
                                const Icon(Icons.access_time_filled, size: 16),
                            label: Text(
                                'پایان: ${DateFormat('HH:mm').format(end)}'),
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
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('انصراف')),
                FilledButton(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) {
                      return;
                    }
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
                  child: const Text('ثبت در تقویم'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final days = _displayedDays;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // نوار کنترل بالای تقویم
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  SegmentedButton<CalendarViewSpan>(
                    segments: const [
                      ButtonSegment(
                          value: CalendarViewSpan.day1,
                          label: Text('روزانه (1D)')),
                      ButtonSegment(
                          value: CalendarViewSpan.day3,
                          label: Text('۳ روزه (3D)')),
                      ButtonSegment(
                          value: CalendarViewSpan.day7,
                          label: Text('هفتگی (7D)')),
                    ],
                    selected: {_span},
                    onSelectionChanged: (set) =>
                        setState(() => _span = set.first),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() => _focusedDate =
                        _focusedDate.subtract(Duration(days: _daysCount))),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _focusedDate = DateTime.now()),
                    child: const Text('امروز'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _focusedDate =
                        _focusedDate.add(Duration(days: _daysCount))),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.surfaceElevated),
                    icon: const Icon(Icons.sync_rounded, size: 16),
                    label: const Text('همگام‌سازی Google Calendar',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () async {
                      await provider.syncGoogleCalendar();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('تقویم گوگل با موفقیت همگام شد.')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // شبکه ساعات تقویم
          Expanded(
            child: Card(
              child: Row(
                children: [
                  // ستون ساعات (00:00 تا 23:00)
                  SizedBox(
                    width: 50,
                    child: ListView.builder(
                      itemCount: 24,
                      itemBuilder: (_, hour) => Container(
                        height: 50,
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${hour.toString().padLeft(2, '0')}:00',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5, color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppColors.border),

                  // ستون‌های روزها (موازی برنامه و عملکرد واقعی)
                  Expanded(
                    child: Row(
                      children: days.map((day) {
                        final dayStart = DateTime(day.year, day.month, day.day);
                        final dayEnd = dayStart.add(const Duration(days: 1));

                        final planned = provider.scheduledBlocks
                            .where(
                              (b) =>
                                  b.startTime.isBefore(dayEnd) &&
                                  b.endTime.isAfter(dayStart),
                            )
                            .toList();

                        final actual = provider.taskLogs
                            .where(
                              (l) =>
                                  l.startTime.isBefore(dayEnd) &&
                                  (l.endTime ?? l.startTime).isAfter(dayStart),
                            )
                            .toList();

                        return Expanded(
                          child: Column(
                            children: [
                              // هدر روز
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                decoration: const BoxDecoration(
                                  border: Border(
                                      bottom:
                                          BorderSide(color: AppColors.border)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  DateFormat('EEEE yyyy/MM/dd', 'fa')
                                      .format(day),
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              // محتوای شبکه ساعت‌ها
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onDoubleTapDown: (details) {
                                    final double clickedY =
                                        details.localPosition.dy;
                                    final int hour =
                                        (clickedY / 50.0).floor().clamp(0, 23);
                                    _showAddBlockModal(context,
                                        dayStart.add(Duration(hours: hour)));
                                  },
                                  child: Stack(
                                    children: [
                                      // خطوط افقی ساعت‌ها
                                      Column(
                                        children: List.generate(
                                          24,
                                          (_) => const Divider(
                                              height: 50,
                                              color: AppColors.border),
                                        ),
                                      ),

                                      // بلوک‌های برنامه‌ریزی‌شده (Scheduled) در نیمه راست ستون
                                      ...planned.map((b) {
                                        final double top = (b.startTime.hour *
                                                50.0) +
                                            (b.startTime.minute * 50.0 / 60.0);
                                        final double height =
                                            (b.plannedDurationSeconds /
                                                    3600.0 *
                                                    50.0)
                                                .clamp(20.0, 400.0);
                                        return Positioned(
                                          top: top,
                                          right: 4,
                                          left: 4,
                                          height: height,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color:
                                                  AppColors.focus.withAlpha(40),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: AppColors.focus),
                                            ),
                                            child: Text(
                                              'برنامه: ${b.title}',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.focus),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        );
                                      }),

                                      // بلوک‌های واقعی کارکرد (Actual) در نیمه چپ ستون
                                      ...actual.map((l) {
                                        final double top = (l.startTime.hour *
                                                50.0) +
                                            (l.startTime.minute * 50.0 / 60.0);
                                        final double height =
                                            (l.durationSeconds / 3600.0 * 50.0)
                                                .clamp(18.0, 400.0);
                                        final Color col = l.isBreakEntry
                                            ? AppColors.breakTime
                                            : (l.isStopwatch
                                                ? AppColors.stopwatch
                                                : AppColors.focus);
                                        return Positioned(
                                          top: top,
                                          left: 8,
                                          right: 20,
                                          height: height,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: col.withAlpha(80),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(color: col),
                                            ),
                                            child: Text(
                                              'عمل: ${l.title}',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.white),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
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
}
