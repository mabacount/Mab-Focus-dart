import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/jalali_date.dart';
import '../../models/project_node.dart';
import '../../providers/app_state_provider.dart';

class ProjectStudioTab extends StatefulWidget {
  const ProjectStudioTab({super.key});

  @override
  State<ProjectStudioTab> createState() => _ProjectStudioTabState();
}

class _ProjectStudioTabState extends State<ProjectStudioTab> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _weeklyQuotaCtrl = TextEditingController();
  final TextEditingController _rateCtrl = TextEditingController();
  String? _parentId;
  bool _countShortBreak = false;
  bool _countLongBreak = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _weeklyQuotaCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
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

  void _showProjectAnalytics(BuildContext context, ProjectNode project) {
    final provider = context.read<AppStateProvider>();
    final logs = provider.taskLogs
        .where((l) =>
            l.macroProjectId == project.id || l.subProjectId == project.id)
        .toList();
    final notes = provider.workNotes
        .where((n) => n.projectId == project.id)
        .toList();

    final totalSec =
        logs.fold<int>(0, (sum, item) => sum + item.durationSeconds);
    final hours = (totalSec / 3600.0).toStringAsFixed(1);
    final cost = ((totalSec / 3600.0) * project.hourlyRate).toStringAsFixed(0);

    // محاسبه پیشرفت بودجه هفتگی
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday % 7));
    final thisWeekLogs = logs.where((l) => l.startTime.isAfter(weekStart));
    final thisWeekMin =
        thisWeekLogs.fold<int>(0, (s, i) => s + i.durationSeconds) / 60.0;
    final quotaMin = project.weeklyQuotaMinutes > 0
        ? project.weeklyQuotaMinutes.toDouble()
        : 0.0;
    final quotaPercent =
        quotaMin > 0 ? (thisWeekMin / quotaMin).clamp(0.0, 1.0) : 0.0;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: AppColors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Color(int.parse(
                        project.colorHex.replaceFirst('#', '0xFF'))),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'گزارش و تحلیل استودیو: ${project.name}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            content: SizedBox(
              width: 580,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // پیل‌های آماری پروژه
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _AnalyticPill(
                            title: 'کل ساعت کارکرد', value: '$hours h'),
                        _AnalyticPill(
                            title: 'تعداد رکوردها', value: '${logs.length}'),
                        _AnalyticPill(
                            title: 'یادداشت‌های کاری',
                            value: '${notes.length}'),
                        if (project.hourlyRate > 0)
                          _AnalyticPill(
                              title: 'ارزش مالی',
                              value:
                                  '${NumberFormat('#,###').format(int.tryParse(cost) ?? 0)} تومان'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // نوار پیشرفت بودجه هفتگی
                  if (project.weeklyQuotaMinutes > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('پیشرفت بودجه هفتگی:',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                              Text(
                                '${thisWeekMin.toStringAsFixed(0)} از ${project.weeklyQuotaMinutes} دقیقه (${(quotaPercent * 100).toStringAsFixed(0)}%)',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: quotaPercent >= 1.0
                                      ? AppColors.breakTime
                                      : AppColors.focus,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: quotaPercent,
                              minHeight: 6,
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                quotaPercent >= 1.0
                                    ? AppColors.breakTime
                                    : AppColors.focus,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // تب‌های داخلی مودال (فعالیت‌ها / یادداشت‌ها)
                  const TabBar(
                    indicatorColor: AppColors.focus,
                    labelColor: AppColors.focus,
                    unselectedLabelColor: AppColors.textSecondary,
                    tabs: [
                      Tab(text: 'فعالیت‌ها و لاگ‌ها'),
                      Tab(text: 'یادداشت‌های گزارش کار'),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Expanded(
                    child: TabBarView(
                      children: [
                        // ۱. لیست لاگ‌های پروژه
                        logs.isEmpty
                            ? const Center(
                                child: Text('هیچ فعالیتی ثبت نشده است.',
                                    style:
                                        TextStyle(color: AppColors.textMuted)))
                            : ListView.separated(
                                itemCount: logs.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1, color: AppColors.border),
                                itemBuilder: (_, i) => ListTile(
                                  dense: true,
                                  title: Text(logs[i].title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    DateFormat('yyyy/MM/dd HH:mm')
                                        .format(logs[i].startTime),
                                    style: const TextStyle(fontSize: 10.5),
                                  ),
                                  trailing: Text(
                                    '${(logs[i].durationSeconds / 60).toStringAsFixed(1)} دقیقه',
                                    style: GoogleFonts.jetBrainsMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),

                        // ۲. لیست یادداشت‌های پروژه
                        notes.isEmpty
                            ? const Center(
                                child: Text(
                                    'هیچ یادداشتی برای این پروژه ثبت نشده است.',
                                    style:
                                        TextStyle(color: AppColors.textMuted)))
                            : ListView.separated(
                                itemCount: notes.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final note = notes[i];
                                  final dateStr = JalaliDate.formatWithWeekDay(
                                      note.createdAt);
                                  return Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceElevated,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: AppColors.border),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(note.taskTitle,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12)),
                                            Text(dateStr,
                                                style: GoogleFonts.jetBrainsMono(
                                                    fontSize: 10.5,
                                                    color: AppColors
                                                        .textSecondary)),
                                          ],
                                        ),
                                        if (note.content.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(note.content,
                                              style: const TextStyle(
                                                  fontSize: 11.5)),
                                        ],
                                        if (note.imagePaths.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            height: 48,
                                            child: ListView.separated(
                                              scrollDirection: Axis.horizontal,
                                              itemCount: note.imagePaths.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(width: 6),
                                              itemBuilder: (c, imgIdx) {
                                                final p = note.imagePaths[imgIdx];
                                                return InkWell(
                                                  onTap: () =>
                                                      _showImagePreview(ctx, p),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    child: Image.file(File(p),
                                                        width: 48,
                                                        height: 48,
                                                        fit: BoxFit.cover),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // دکمه خروجی اکسل کارکرد پروژه
              OutlinedButton.icon(
                icon: const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text('خروجی اکسل کارکرد پروژه'),
                onPressed: () async {
                  final path = await provider.exportLogsToExcel(logs);
                  if (ctx.mounted && path != null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('فایل در مسیر زیر ذخیره شد: $path'),
                      backgroundColor: AppColors.breakTime,
                    ));
                  }
                },
              ),
              // دکمه خروجی اکسل یادداشت‌های پروژه
              if (notes.isNotEmpty)
                OutlinedButton.icon(
                  icon: const Icon(Icons.note_alt_rounded, size: 16),
                  label: const Text('خروجی اکسل یادداشت‌ها'),
                  onPressed: () async {
                    final path = await provider.exportWorkNotesToExcel(notes);
                    if (ctx.mounted && path != null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('فایل در مسیر زیر ذخیره شد: $path'),
                        backgroundColor: AppColors.breakTime,
                      ));
                    }
                  },
                ),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('بستن')),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final macros = provider.macroProjects;
        final tags = provider.phaseTags;
        final allLogs = provider.taskLogs;
        final allNotes = provider.workNotes;

        // آمارهای کلی پروژه‌ها
        final totalSec = allLogs.fold<int>(0, (s, l) => s + l.durationSeconds);
        final totalHours = (totalSec / 3600.0).toStringAsFixed(1);
        final totalCost = macros.fold<double>(0.0, (sum, m) {
          final mSec = allLogs
              .where((l) => l.macroProjectId == m.id || l.subProjectId == m.id)
              .fold<int>(0, (s, l) => s + l.durationSeconds);
          return sum + ((mSec / 3600.0) * m.hourlyRate);
        });

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // کارت‌های آماری کلان و گزارش استودیو
              Row(
                children: [
                  Expanded(
                    child: _StudioStatCard(
                      icon: Icons.account_tree_rounded,
                      title: 'پروژه‌های کلان',
                      value: '${macros.length} پروژه',
                      color: AppColors.focus,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StudioStatCard(
                      icon: Icons.timer_outlined,
                      title: 'مجموع کارکرد پروژه‌ها',
                      value: '$totalHours ساعت',
                      color: AppColors.stopwatch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StudioStatCard(
                      icon: Icons.attach_money_rounded,
                      title: 'ارزش مالی کل کارکرد',
                      value:
                          '${NumberFormat('#,###').format(totalCost.round())} تومان',
                      color: AppColors.golden,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StudioStatCard(
                      icon: Icons.edit_note_rounded,
                      title: 'کل یادداشت‌های ثبت‌شده',
                      value: '${allNotes.length} یادداشت',
                      color: AppColors.breakTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // فرم تعریف پروژه جدید
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تعریف پروژه یا زیرپروژه جدید',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'نام پروژه',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String?>(
                              initialValue: _parentId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'مادر (خالی = کلان)',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              dropdownColor: AppColors.surfaceElevated,
                              items: [
                                const DropdownMenuItem(
                                    value: null,
                                    child: Text('پروژه کلان اصلی')),
                                ...macros.map((m) => DropdownMenuItem(
                                    value: m.id, child: Text(m.name))),
                              ],
                              onChanged: (val) =>
                                  setState(() => _parentId = val),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _weeklyQuotaCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'بودجه هفتگی (دقیقه)',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _rateCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'نرخ ساعتی (تومان)',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              dense: true,
                              title: const Text(
                                  'محاسبه استراحت ۵ دقیقه‌ای جزو کارکرد',
                                  style: TextStyle(fontSize: 12)),
                              value: _countShortBreak,
                              onChanged: (val) =>
                                  setState(() => _countShortBreak = val),
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              dense: true,
                              title: const Text(
                                  'محاسبه استراحت ۶۰ دقیقه‌ای جزو کارکرد',
                                  style: TextStyle(fontSize: 12)),
                              value: _countLongBreak,
                              onChanged: (val) =>
                                  setState(() => _countLongBreak = val),
                            ),
                          ),
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('ذخیره پروژه'),
                            onPressed: () async {
                              if (_nameCtrl.text.trim().isEmpty) return;
                              final node = ProjectNode(
                                id: const Uuid().v4(),
                                name: _nameCtrl.text.trim(),
                                parentId: _parentId,
                                weeklyQuotaMinutes:
                                    int.tryParse(_weeklyQuotaCtrl.text) ?? 0,
                                hourlyRate:
                                    double.tryParse(_rateCtrl.text) ?? 0.0,
                                countShortBreaksAsWork: _countShortBreak,
                                countLongBreaksAsWork: _countLongBreak,
                              );
                              await provider.saveProject(node);
                              _nameCtrl.clear();
                              _weeklyQuotaCtrl.clear();
                              _rateCtrl.clear();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // فهرست پروژه‌ها
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'فهرست پروژه‌ها و تحلیل عملکرد (روی هر پروژه کلیک کنید)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${macros.length} پروژه فعال',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ...macros.map((macro) {
                final subs = provider.getSubProjects(macro.id);
                final macroLogs = allLogs
                    .where((l) =>
                        l.macroProjectId == macro.id ||
                        l.subProjectId == macro.id)
                    .toList();
                final macroNotes = allNotes
                    .where((n) => n.projectId == macro.id)
                    .toList();
                final macroSec = macroLogs.fold<int>(
                    0, (s, l) => s + l.durationSeconds);
                final macroHours = (macroSec / 3600.0).toStringAsFixed(1);

                return Card(
                  child: ExpansionTile(
                    title: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Color(int.parse(macro.colorHex
                                .replaceFirst('#', '0xFF'))),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(macro.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.focus.withAlpha(25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$macroHours ساعت',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: AppColors.focus,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (macroNotes.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.breakTime.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${macroNotes.length} یادداشت',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.breakTime,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                        'وضعیت: ${macro.status} | زیرپروژه‌ها: ${subs.length}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.analytics_outlined,
                              size: 20, color: AppColors.focus),
                          tooltip: 'مشاهده گزارش تحلیلی و یادداشت‌های این پروژه',
                          onPressed: () =>
                              _showProjectAnalytics(context, macro),
                        ),
                        IconButton(
                          icon: Icon(
                              macro.isSuspended
                                  ? Icons.play_arrow
                                  : Icons.pause,
                              size: 18),
                          tooltip:
                              macro.isSuspended ? 'فعال کردن' : 'معلق کردن',
                          onPressed: () => provider.saveProject(macro.copyWith(
                              status:
                                  macro.isSuspended ? 'active' : 'suspended')),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: Colors.redAccent),
                          onPressed: () => provider.deleteProject(macro.id),
                        ),
                      ],
                    ),
                    children: [
                      // نوار اقدامات درون پروژه
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact),
                              icon: const Icon(Icons.analytics_rounded,
                                  size: 15, color: AppColors.focus),
                              label: const Text('گزارش تحلیلی و یادداشت‌ها',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () =>
                                  _showProjectAnalytics(context, macro),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact),
                              icon: const Icon(Icons.table_chart_rounded,
                                  size: 15, color: AppColors.breakTime),
                              label: const Text('خروجی اکسل کارکرد',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () async {
                                final path = await provider
                                    .exportLogsToExcel(macroLogs);
                                if (context.mounted && path != null) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Text(
                                        'فایل در مسیر زیر ذخیره شد: $path'),
                                    backgroundColor: AppColors.breakTime,
                                  ));
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      if (subs.isNotEmpty) ...[
                        const Divider(height: 1, color: AppColors.border),
                        ...subs.map(
                          (sub) => ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            title: Text('↳ ${sub.name}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.close,
                                  size: 16, color: Colors.redAccent),
                              onPressed: () => provider.deleteProject(sub.id),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),
              // تگ‌های فاز کاری
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تگ‌های فاز کاری',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: tags
                            .map((t) => Chip(
                                  label: Text(t.name),
                                  onDeleted: () =>
                                      provider.deletePhaseTag(t.id),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StudioStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _StudioStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticPill extends StatelessWidget {
  final String title;
  final String value;
  const _AnalyticPill({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.focus)),
      ],
    );
  }
}
