// کارتابل تکمیل مشخصات تسک‌های بدون عنوان بدون تگ ویرایش
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/task_log_entry.dart';
import '../../providers/app_state_provider.dart';

class UntitledInboxTab extends StatelessWidget {
  const UntitledInboxTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final drafts = provider.untitledDraftLogs;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.draftWarning.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.draftWarning.withAlpha(120)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.draftWarning),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'کارتابل تسک‌های بدون عنوان: تسک‌هایی که با «شروع فوری» ثبت شده‌اند در این بخش قرار می‌گیرند. تکمیل عنوان، پروژه و تگ در این صفحه به زمان واقعی دست نمی‌زند و تگ [Edited] روی رکورد درج نمی‌کند.',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: drafts.isEmpty
                    ? const Center(
                        child: Text(
                          'عالی! هیچ تسک بدون عنوانی در کارتابل وجود ندارد.',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        itemCount: drafts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return _UntitledDraftRowCard(draft: drafts[index]);
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

class _UntitledDraftRowCard extends StatefulWidget {
  final TaskLogEntry draft;

  const _UntitledDraftRowCard({required this.draft});

  @override
  State<_UntitledDraftRowCard> createState() => _UntitledDraftRowCardState();
}

class _UntitledDraftRowCardState extends State<_UntitledDraftRowCard> {
  final TextEditingController _titleController = TextEditingController();
  String? _selectedMacroId;
  String? _selectedSubId;
  final Set<String> _selectedTagIds = {};

  @override
  void initState() {
    super.initState();
    _selectedMacroId = widget.draft.macroProjectId;
    _selectedSubId = widget.draft.subProjectId;
    _selectedTagIds.addAll(widget.draft.tagIds);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final macros = provider.macroProjects;
    final subs = provider.getSubProjects(_selectedMacroId);
    final tags = provider.phaseTags;

    final startStr = DateFormat('yyyy/MM/dd | HH:mm')
        .format(widget.draft.startTime.toLocal());
    final durMin = (widget.draft.durationSeconds / 60.0).toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'زمان ثبت‌شده: $startStr  —  مدت: $durMin دقیقه',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: AppColors.draftWarning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: 'حذف این پیش‌نویس',
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.redAccent),
                  onPressed: () => provider.deleteTaskLog(widget.draft.id),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      hintText: 'عنوان واقعی تسک را وارد کنید...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String?>(
                    initialValue: macros.any((p) => p.id == _selectedMacroId)
                        ? _selectedMacroId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'پروژه کلان',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    dropdownColor: AppColors.surfaceElevated,
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('بدون پروژه کلان')),
                      ...macros.map((p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.name))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedMacroId = val;
                        _selectedSubId = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String?>(
                    initialValue: subs.any((p) => p.id == _selectedSubId)
                        ? _selectedSubId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'زیرپروژه',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    dropdownColor: AppColors.surfaceElevated,
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('بدون زیرپروژه')),
                      ...subs.map((p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.name))),
                    ],
                    onChanged: (val) => setState(() => _selectedSubId = val),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.breakTime,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                  icon:
                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('تکمیل و انتقال'),
                  onPressed: () async {
                    if (_titleController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('لطفاً ابتدا عنوان تسک را وارد کنید.')),
                      );
                      return;
                    }
                    await provider.completeUntitledDraft(
                      id: widget.draft.id,
                      title: _titleController.text.trim(),
                      macroProjectId: _selectedMacroId,
                      subProjectId: _selectedSubId,
                      tagIds: _selectedTagIds.toList(),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: tags.map((tag) {
                final isSelected = _selectedTagIds.contains(tag.id);
                return FilterChip(
                  label: Text(tag.name, style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  selectedColor: AppColors.focus,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedTagIds.add(tag.id);
                      } else {
                        _selectedTagIds.remove(tag.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
