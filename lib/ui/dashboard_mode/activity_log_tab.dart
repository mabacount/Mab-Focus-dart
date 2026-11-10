import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/jalali_date.dart';
import '../../models/task_log_entry.dart';
import '../../models/work_note_entry.dart';
import '../../providers/app_state_provider.dart';
import '../shared/work_note_dialog.dart';

class ActivityLogTab extends StatefulWidget {
  const ActivityLogTab({super.key});

  @override
  State<ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends State<ActivityLogTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // فیلترهای گزارش کارکرد
  String _filterType = 'all'; // all | work | break | stopwatch
  String? _selectedProjectId;
  bool _onlyToday = false;

  // فیلترهای یادداشت‌ها
  String? _noteFilterProjectId;
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

  String _formatDuration(int seconds) {
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<TaskLogEntry> _filterLogs(List<TaskLogEntry> list) {
    final now = DateTime.now();
    return list.where((l) {
      if (_onlyToday) {
        if (l.startTime.year != now.year ||
            l.startTime.month != now.month ||
            l.startTime.day != now.day) {
          return false;
        }
      }
      if (_selectedProjectId != null) {
        if (l.macroProjectId != _selectedProjectId &&
            l.subProjectId != _selectedProjectId) {
          return false;
        }
      }
      if (_filterType == 'work') return l.isWork;
      if (_filterType == 'break') return l.isBreakEntry;
      if (_filterType == 'stopwatch') return l.isStopwatch;
      return true;
    }).toList();
  }

  List<WorkNoteEntry> _filterNotes(List<WorkNoteEntry> list) {
    final query = _noteSearchCtrl.text.trim().toLowerCase();
    return list.where((n) {
      if (_noteFilterProjectId != null && n.projectId != _noteFilterProjectId) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchesTitle = n.taskTitle.toLowerCase().contains(query);
        final matchesContent = n.content.toLowerCase().contains(query);
        if (!matchesTitle && !matchesContent) return false;
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
    final notesCount = provider.workNotes.length;

    return Column(
      children: [
        // هدر تب‌ها برای سوییچ بین لاگ‌های کارکرد و دفترچه یادداشت‌ها
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.focus,
                labelColor: AppColors.focus,
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
                      backgroundColor: AppColors.focus,
                      child: const Icon(Icons.note_alt_rounded, size: 18),
                    ),
                    text: 'دفترچه یادداشت‌های کاری',
                  ),
                ],
              ),
              const Spacer(),
              // دکمه ثبت فوری یادداشت
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('ثبت گزارش کار +',
                    style: TextStyle(fontSize: 11.5)),
                onPressed: () => WorkNoteDialog.openStandalone(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),

        // بدنه تب‌ها
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildActivityLogsView(provider),
              _buildWorkNotesView(provider),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== ۱. نمای گزارش کارکرد و تایم‌شیت ====================

  Widget _buildActivityLogsView(AppStateProvider provider) {
    final filtered = _filterLogs(provider.taskLogs);
    final totalSec = filtered.fold<int>(0, (sum, i) => sum + i.durationSeconds);
    final projects = provider.projects;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // نوار فیلتر و خروجی اکسل
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('امروز'),
                    selected: _onlyToday,
                    onSelected: (v) => setState(() => _onlyToday = v),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _filterType,
                    isExpanded: false,
                    dropdownColor: AppColors.surfaceElevated,
                    items: const [
                      DropdownMenuItem(
                          value: 'all', child: Text('همه رکوردها')),
                      DropdownMenuItem(
                          value: 'work', child: Text('فقط کارکرد تمرکز')),
                      DropdownMenuItem(
                          value: 'break', child: Text('فقط استراحت‌ها')),
                      DropdownMenuItem(
                          value: 'stopwatch', child: Text('کرنومتر / خواب')),
                    ],
                    onChanged: (v) => setState(() => _filterType = v ?? 'all'),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    value: _selectedProjectId,
                    isExpanded: false,
                    dropdownColor: AppColors.surfaceElevated,
                    hint: const Text('فیلتر پروژه: همه'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('همه پروژه‌ها')),
                      ...projects.map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.isMacro ? p.name : '↳ ${p.name}'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedProjectId = v),
                  ),
                  const Spacer(),
                  Text(
                    'مجموع: ${_formatDuration(totalSec)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.focus,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.breakTime),
                    icon: const Icon(Icons.table_view_rounded, size: 16),
                    label: const Text('خروجی اکسل ۱۵ ستونی (.xlsx)'),
                    onPressed: () async {
                      final path = await provider.exportLogsToExcel(filtered);
                      if (mounted && path != null) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('فایل در مسیر زیر ذخیره شد: $path')));
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // لیست رکوردها
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('هیچ رکوردی برای نمایش یافت نشد.',
                        style: TextStyle(color: AppColors.textMuted)))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final log = filtered[i];
                      final project = provider.getProjectById(
                          log.subProjectId ?? log.macroProjectId);

                      return Card(
                        child: ListTile(
                          dense: true,
                          title: Row(
                            children: [
                              Text(
                                log.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              if (project != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Color(int.parse(project.colorHex
                                            .replaceFirst('#', '0xFF')))
                                        .withAlpha(35),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    project.name,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Color(int.parse(project.colorHex
                                          .replaceFirst('#', '0xFF'))),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              if (log.isEdited) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message:
                                      'زمان اولیه: ${_formatDuration(log.originalDurationSeconds ?? log.durationSeconds)}',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: AppColors.edited.withAlpha(40),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Text('[Edited]',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.edited,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${DateFormat('yyyy/MM/dd HH:mm').format(log.startTime)} | نوع: ${log.entryType}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_formatDuration(log.durationSeconds),
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 16, color: Colors.redAccent),
                                onPressed: () => provider.deleteTaskLog(log.id),
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

  // ==================== ۲. نمای دفترچه یادداشت‌های کاری ====================

  Widget _buildWorkNotesView(AppStateProvider provider) {
    final filtered = _filterNotes(provider.workNotes);
    final projects = provider.projects;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // نوار ابزار جستجو و خروجی اکسل یادداشت‌ها
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _noteSearchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'جست‌وجو در متن یا عنوان یادداشت‌ها...',
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _noteFilterProjectId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'فیلتر پروژه',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      dropdownColor: AppColors.surfaceElevated,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('همه پروژه‌ها')),
                        ...projects.map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.isMacro ? p.name : '↳ ${p.name}'),
                            )),
                      ],
                      onChanged: (v) =>
                          setState(() => _noteFilterProjectId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // دکمه خروجی اکسل یادداشت‌ها
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.focus,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.file_download_rounded, size: 18),
                    label: const Text('خروجی اکسل یادداشت‌ها (.xlsx)'),
                    onPressed: () async {
                      final path =
                          await provider.exportWorkNotesToExcel(filtered);
                      if (mounted && path != null) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'فایل اکسل یادداشت‌ها در مسیر زیر ذخیره شد: $path'),
                          backgroundColor: AppColors.breakTime,
                        ));
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // لیست یا کارت‌های یادداشت‌ها
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
                          'هیچ یادداشتی ثبت نشده است.',
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
                      final project =
                          provider.getProjectById(note.projectId);
                      final jalaliDate =
                          JalaliDate.formatWithWeekDay(note.createdAt);
                      final timeStr =
                          '${note.createdAt.hour.toString().padLeft(2, '0')}:${note.createdAt.minute.toString().padLeft(2, '0')}';

                      return Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // هدر کارت یادداشت
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.focus.withAlpha(30),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.edit_note_rounded,
                                        size: 18, color: AppColors.focus),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      note.taskTitle,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  if (project != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Color(int.parse(project.colorHex
                                                .replaceFirst('#', '0xFF')))
                                            .withAlpha(35),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        project.name,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: Color(int.parse(project
                                              .colorHex
                                              .replaceFirst('#', '0xFF'))),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    '$jalaliDate — ساعت $timeStr',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18, color: Colors.redAccent),
                                    tooltip: 'حذف یادداشت',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('حذف یادداشت'),
                                          content: const Text(
                                              'آیا از حذف این یادداشت اطمینان دارید؟'),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.of(c).pop(false),
                                                child: const Text('انصراف')),
                                            FilledButton(
                                                style: FilledButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.redAccent),
                                                onPressed: () =>
                                                    Navigator.of(c).pop(true),
                                                child: const Text('حذف')),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await provider.deleteWorkNote(note.id);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // متن یادداشت
                              if (note.content.isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: SelectableText(
                                    note.content,
                                    style: const TextStyle(
                                        fontSize: 12.5, height: 1.5),
                                  ),
                                ),

                              // عکس‌های الصاقی با قابلیت بزرگ‌نمایی
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
                                        child: Tooltip(
                                          message:
                                              'کلیک برای مشاهده در اندازه اصلی',
                                          child: Container(
                                            width: 80,
                                            height: 80,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: AppColors.border),
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
