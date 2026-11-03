// جدول تایم‌شیت، نشانگر بنفش [Edited] و مودال ویرایش زمان
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/task_log_entry.dart';
import '../../providers/app_state_provider.dart';

class ActivityLogTab extends StatefulWidget {
  const ActivityLogTab({super.key});

  @override
  State<ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends State<ActivityLogTab> {
  String? _filterMacroProjectId;
  String? _filterTagId;
  bool _onlyToday = false;

  String _formatDuration(int seconds) {
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<TaskLogEntry> _getFilteredLogs(AppStateProvider provider) {
    final now = DateTime.now();
    return provider.taskLogs.where((log) {
      if (_onlyToday) {
        final localStart = log.startTime.toLocal();
        if (localStart.year != now.year ||
            localStart.month != now.month ||
            localStart.day != now.day) {
          return false;
        }
      }
      if (_filterMacroProjectId != null &&
          log.macroProjectId != _filterMacroProjectId) {
        return false;
      }
      if (_filterTagId != null && !log.tagIds.contains(_filterTagId)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _showEditLogModal(BuildContext context, TaskLogEntry log) async {
    final provider = context.read<AppStateProvider>();
    final titleCtrl = TextEditingController(text: log.title);
    final noteCtrl = TextEditingController(text: log.editNote ?? '');

    String? selectedMacroId = log.macroProjectId;
    String? selectedSubId = log.subProjectId;
    final Set<String> selectedTags = {...log.tagIds};

    DateTime editedStart = log.startTime.toLocal();
    DateTime editedEnd = (log.endTime ??
            log.startTime.add(Duration(seconds: log.durationSeconds)))
        .toLocal();
    final durationMinutesCtrl = TextEditingController(
      text: (log.durationSeconds / 60.0).toStringAsFixed(1),
    );

    bool timeModified = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final macroList = provider.macroProjects;
            final subList = provider.getSubProjects(selectedMacroId);
            final allTags = provider.phaseTags;

            void checkTimeModification() {
              final parsedMin = double.tryParse(durationMinutesCtrl.text) ??
                  (log.durationSeconds / 60.0);
              final newSec = (parsedMin * 60).round();
              final startDiff = editedStart
                      .difference(log.startTime.toLocal())
                      .inSeconds
                      .abs() >
                  1;
              final origEnd = (log.endTime ??
                      log.startTime.add(Duration(seconds: log.durationSeconds)))
                  .toLocal();
              final endDiff = editedEnd.difference(origEnd).inSeconds.abs() > 1;
              final durDiff = (newSec - log.durationSeconds).abs() > 1;
              setModalState(() {
                timeModified = startDiff || endDiff || durDiff;
              });
            }

            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text('ویرایش رکورد و ممیزی زمان',
                  style: TextStyle(fontSize: 16)),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (timeModified || log.isEdited)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.edited.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.edited),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.verified_user_rounded,
                                  color: AppColors.edited, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'توجه: با تغییر زمان ثبت‌شده، برچسب دائمی [Edited / ویرایش‌شده] به همراه زمان اولیه روی این رکورد درج می‌گردد.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'عنوان تسک',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue:
                                  macroList.any((p) => p.id == selectedMacroId)
                                      ? selectedMacroId
                                      : null,
                              decoration: const InputDecoration(
                                labelText: 'پروژه کلان',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              dropdownColor: AppColors.surfaceElevated,
                              items: [
                                const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('بدون پروژه کلان')),
                                ...macroList.map((p) => DropdownMenuItem(
                                    value: p.id, child: Text(p.name))),
                              ],
                              onChanged: (val) {
                                setModalState(() {
                                  selectedMacroId = val;
                                  selectedSubId = null;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue:
                                  subList.any((p) => p.id == selectedSubId)
                                      ? selectedSubId
                                      : null,
                              decoration: const InputDecoration(
                                labelText: 'پروژه زیرمجموعه',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              dropdownColor: AppColors.surfaceElevated,
                              items: [
                                const DropdownMenuItem<String?>(
                                    value: null, child: Text('بدون زیرپروژه')),
                                ...subList.map((p) => DropdownMenuItem(
                                    value: p.id, child: Text(p.name))),
                              ],
                              onChanged: (val) {
                                setModalState(() {
                                  selectedSubId = val;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('تگ‌های فاز کاری:',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: allTags.map((tag) {
                          final selected = selectedTags.contains(tag.id);
                          return FilterChip(
                            label: Text(tag.name,
                                style: const TextStyle(fontSize: 11.5)),
                            selected: selected,
                            selectedColor: AppColors.focus,
                            onSelected: (val) {
                              setModalState(() {
                                if (val) {
                                  selectedTags.add(tag.id);
                                } else {
                                  selectedTags.remove(tag.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const Divider(height: 24, color: AppColors.border),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.access_time_rounded,
                                  size: 16),
                              label: Text(
                                  'شروع: ${DateFormat('HH:mm').format(editedStart)}'),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: ctx,
                                  initialTime:
                                      TimeOfDay.fromDateTime(editedStart),
                                );
                                if (picked != null) {
                                  editedStart = DateTime(
                                    editedStart.year,
                                    editedStart.month,
                                    editedStart.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  final diffSec = editedEnd
                                      .difference(editedStart)
                                      .inSeconds;
                                  if (diffSec > 0) {
                                    durationMinutesCtrl.text =
                                        (diffSec / 60.0).toStringAsFixed(1);
                                  }
                                  checkTimeModification();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.access_time_filled_rounded,
                                  size: 16),
                              label: Text(
                                  'پایان: ${DateFormat('HH:mm').format(editedEnd)}'),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: ctx,
                                  initialTime:
                                      TimeOfDay.fromDateTime(editedEnd),
                                );
                                if (picked != null) {
                                  editedEnd = DateTime(
                                    editedEnd.year,
                                    editedEnd.month,
                                    editedEnd.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  final diffSec = editedEnd
                                      .difference(editedStart)
                                      .inSeconds;
                                  if (diffSec > 0) {
                                    durationMinutesCtrl.text =
                                        (diffSec / 60.0).toStringAsFixed(1);
                                  }
                                  checkTimeModification();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: durationMinutesCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'مدت زمان نهایی (دقیقه)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => checkTimeModification(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText:
                              'توضیح یا علت ویرایش زمان (اختیاری - مثلاً فراموشی توقف تایمر)',
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
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        timeModified ? AppColors.edited : AppColors.focus,
                  ),
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('ذخیره تغییرات'),
                  onPressed: () async {
                    final parsedMin =
                        double.tryParse(durationMinutesCtrl.text) ??
                            (log.durationSeconds / 60.0);
                    final newDurationSec =
                        (parsedMin * 60).round().clamp(1, 86400);
                    final adjustedEnd = timeModified
                        ? editedStart.add(Duration(seconds: newDurationSec))
                        : editedEnd;

                    await provider.editTaskLogWithAudit(
                      id: log.id,
                      newTitle: titleCtrl.text,
                      newMacroProjectId: selectedMacroId,
                      newSubProjectId: selectedSubId,
                      newTagIds: selectedTags.toList(),
                      newStartTime: editedStart,
                      newEndTime: adjustedEnd,
                      newDurationSeconds: newDurationSec,
                      editNote: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                    );
                    if (ctx.mounted) {
                      Navigator.of(ctx).pop();
                    }
                  },
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
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final filteredLogs = _getFilteredLogs(provider);
        final totalSeconds = filteredLogs.fold<int>(
            0, (sum, item) => sum + item.durationSeconds);
        final totalOvertimeSeconds = filteredLogs.fold<int>(
            0, (sum, item) => sum + item.overtimeSeconds);
        final editedCount = filteredLogs.where((e) => e.isEdited).length;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ۱. کارت‌های خلاصه وضعیت در بالای صفحه
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SummaryStatCard(
                    title: 'مجموع زمان کارکرد',
                    value: _formatDuration(totalSeconds),
                    icon: Icons.timer_rounded,
                    accentColor: AppColors.focus,
                  ),
                  _SummaryStatCard(
                    title: 'مجموع اضافه‌کاری منفی',
                    value: _formatDuration(totalOvertimeSeconds),
                    icon: Icons.more_time_rounded,
                    accentColor: AppColors.overtime,
                  ),
                  _SummaryStatCard(
                    title: 'تعداد رکوردها (ویرایش‌شده)',
                    value: '${filteredLogs.length} ($editedCount)',
                    icon: Icons.verified_user_outlined,
                    accentColor: AppColors.edited,
                  ),
                  _SummaryStatCard(
                    title: 'تسک‌های بدون عنوان',
                    value: '${provider.untitledDraftLogs.length}',
                    icon: Icons.warning_amber_rounded,
                    accentColor: AppColors.draftWarning,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ۲. نوار فیلتر و دکمه خروجی اکسل
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('فقط امروز'),
                            selected: _onlyToday,
                            selectedColor: AppColors.focus.withAlpha(60),
                            onSelected: (val) =>
                                setState(() => _onlyToday = val),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: _filterMacroProjectId,
                              hint: const Text('همه پروژه‌های کلان',
                                  style: TextStyle(fontSize: 13)),
                              dropdownColor: AppColors.surfaceElevated,
                              items: [
                                const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('همه پروژه‌های کلان')),
                                ...provider.macroProjects.map(
                                  (p) => DropdownMenuItem<String?>(
                                      value: p.id, child: Text(p.name)),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => _filterMacroProjectId = val),
                            ),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: _filterTagId,
                              hint: const Text('همه تگ‌های فاز',
                                  style: TextStyle(fontSize: 13)),
                              dropdownColor: AppColors.surfaceElevated,
                              items: [
                                const DropdownMenuItem<String?>(
                                    value: null, child: Text('همه تگ‌های فاز')),
                                ...provider.phaseTags.map(
                                  (t) => DropdownMenuItem<String?>(
                                      value: t.id, child: Text(t.name)),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => _filterTagId = val),
                            ),
                          ),
                        ],
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.breakTime,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.table_view_rounded, size: 18),
                        label: const Text('خروجی اکسل کارفرما (.xlsx)'),
                        onPressed: () async {
                          final savedPath =
                              await provider.exportLogsToExcel(filteredLogs);
                          if (context.mounted && savedPath != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'فایل اکسل با موفقیت ذخیره شد: $savedPath')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ۳. فهرست رکوردها با نمایش نشانگر ممیزی [Edited]
              Expanded(
                child: filteredLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'هیچ رکوردی مطابق فیلترهای انتخابی یافت نشد.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filteredLogs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final log = filteredLogs[index];
                          final macro =
                              provider.getProjectById(log.macroProjectId);
                          final sub = provider.getProjectById(log.subProjectId);
                          final tagNames = log.tagIds
                              .map((id) => provider.getPhaseTagById(id)?.name)
                              .whereType<String>()
                              .join(' · ');

                          final dateStr = DateFormat('yyyy/MM/dd')
                              .format(log.startTime.toLocal());
                          final startStr = DateFormat('HH:mm:ss')
                              .format(log.startTime.toLocal());
                          final endStr = log.endTime != null
                              ? DateFormat('HH:mm:ss')
                                  .format(log.endTime!.toLocal())
                              : 'در حال اجرا';

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  // ستون عنوان و مسیر پروژه
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if (log.isUntitledDraft)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    left: 6),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.draftWarning
                                                      .withAlpha(35),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                      color: AppColors
                                                          .draftWarning),
                                                ),
                                                child: const Text(
                                                  'بدون عنوان',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: AppColors
                                                          .draftWarning),
                                                ),
                                              ),
                                            Flexible(
                                              child: Text(
                                                log.title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${macro?.name ?? 'بدون پروژه کلان'} > ${sub?.name ?? '-'}  |  ${tagNames.isEmpty ? 'بدون تگ' : tagNames}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // ستون تاریخ و بازه شروع تا پایان
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          dateStr,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$startStr - $endStr',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 12,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // ستون مدت نهایی و تگ بنفش [Edited] با Tooltip کامل
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      children: [
                                        Text(
                                          _formatDuration(log.durationSeconds),
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures()
                                            ],
                                          ),
                                        ),
                                        if (log.isEdited) ...[
                                          const SizedBox(width: 8),
                                          Tooltip(
                                            message:
                                                'ویرایش‌شده در: ${log.editedAt != null ? DateFormat('yyyy/MM/dd HH:mm').format(log.editedAt!.toLocal()) : '-'}\n'
                                                'مدت اولیه ثبت‌شده توسط تایمر: ${_formatDuration(log.originalDurationSeconds ?? log.durationSeconds)}\n'
                                                'علت ویرایش: ${log.editNote ?? 'ثبت نشده'}',
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: AppColors.edited
                                                    .withAlpha(40),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                    color: AppColors.edited),
                                              ),
                                              child: const Text(
                                                '[Edited]',
                                                style: TextStyle(
                                                  color: AppColors.edited,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  // دکمه‌های ویرایش و حذف
                                  IconButton(
                                    tooltip: 'ویرایش رکورد / اصلاح زمان',
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 19,
                                        color: AppColors.textSecondary),
                                    onPressed: () =>
                                        _showEditLogModal(context, log),
                                  ),
                                  IconButton(
                                    tooltip: 'حذف رکورد',
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 19,
                                        color: Colors.redAccent),
                                    onPressed: () =>
                                        provider.deleteTaskLog(log.id),
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
      },
    );
  }
}

class _SummaryStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;

  const _SummaryStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 235,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
