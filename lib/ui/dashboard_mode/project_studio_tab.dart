import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
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

  void _showProjectAnalytics(BuildContext context, ProjectNode project) {
    final provider = context.read<AppStateProvider>();
    final logs = provider.taskLogs
        .where((l) =>
            l.macroProjectId == project.id || l.subProjectId == project.id)
        .toList();
    final totalSec =
        logs.fold<int>(0, (sum, item) => sum + item.durationSeconds);
    final hours = (totalSec / 3600.0).toStringAsFixed(1);
    final cost = ((totalSec / 3600.0) * project.hourlyRate).toStringAsFixed(0);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('گزارش تحلیلی پروژه: ${project.name}',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _AnalyticPill(title: 'کل ساعت کارکرد', value: '$hours h'),
                    _AnalyticPill(
                        title: 'تعداد رکوردها', value: '${logs.length}'),
                    if (project.hourlyRate > 0)
                      _AnalyticPill(title: 'ارزش مالی', value: '$cost تومان'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('آخرین فعالیت‌های این پروژه:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: logs.isEmpty
                      ? const Center(
                          child: Text('رکوردی ثبت نشده است.',
                              style: TextStyle(color: AppColors.textMuted)))
                      : ListView.separated(
                          itemCount: logs.length.clamp(0, 10),
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (_, i) => ListTile(
                            dense: true,
                            title: Text(logs[i].title),
                            subtitle: Text(
                                '${(logs[i].durationSeconds / 60).toStringAsFixed(1)} دقیقه'),
                          ),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('بستن')),
          ],
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

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const Text(
                  'فهرست پروژه‌ها (روی هر پروژه کلیک کنید تا تحلیل آن را ببینید)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...macros.map((macro) {
                final subs = provider.getSubProjects(macro.id);
                return Card(
                  child: ExpansionTile(
                    title: InkWell(
                      onTap: () => _showProjectAnalytics(context, macro),
                      child: Row(
                        children: [
                          Text(macro.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          const Icon(Icons.analytics_outlined,
                              size: 16, color: AppColors.focus),
                        ],
                      ),
                    ),
                    subtitle: Text(
                        'وضعیت: ${macro.status} | زیرپروژه‌ها: ${subs.length}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                    children: subs
                        .map((sub) => ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              title: Text('↳ ${sub.name}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.close,
                                    size: 16, color: Colors.redAccent),
                                onPressed: () => provider.deleteProject(sub.id),
                              ),
                            ))
                        .toList(),
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
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.focus)),
      ],
    );
  }
}
