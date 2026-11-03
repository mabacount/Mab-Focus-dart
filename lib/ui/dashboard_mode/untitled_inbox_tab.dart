import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/task_log_entry.dart';
import '../../providers/app_state_provider.dart';
import '../shared/unified_project_selector.dart';

class UntitledInboxTab extends StatelessWidget {
  const UntitledInboxTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final drafts = provider.untitledDraftLogs;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.draftWarning.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.draftWarning.withAlpha(80)),
            ),
            child: const Text(
              'کارتابل تسک‌های بدون عنوان: تکمیل عنوان، پروژه و تگ در این بخش به زمان واقعی دست نمی‌زند و تگ [Edited] روی رکورد درج نمی‌کند.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: drafts.isEmpty
                ? const Center(
                    child: Text(
                        'عالی! هیچ تسک بدون عنوانی در کارتابل وجود ندارد.',
                        style: TextStyle(color: AppColors.textMuted)))
                : ListView.separated(
                    itemCount: drafts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _DraftRow(draft: drafts[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DraftRow extends StatefulWidget {
  final TaskLogEntry draft;
  const _DraftRow({required this.draft});

  @override
  State<_DraftRow> createState() => _DraftRowState();
}

class _DraftRowState extends State<_DraftRow> {
  final TextEditingController _ctrl = TextEditingController();
  String? _macroId;
  String? _subId;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final startStr =
        DateFormat('yyyy/MM/dd HH:mm').format(widget.draft.startTime);
    final min = (widget.draft.durationSeconds / 60).toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$startStr — $min دقیقه',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 12, color: AppColors.draftWarning)),
                IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: Colors.redAccent),
                    onPressed: () => provider.deleteTaskLog(widget.draft.id)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                        hintText: 'عنوان واقعی تسک را بنویسید...',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: UnifiedProjectSelector(
                    projects: provider.projects,
                    selectedMacroId: _macroId,
                    selectedSubId: _subId,
                    onSelected: (m, s) => setState(() {
                      _macroId = m;
                      _subId = s;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.breakTime),
                  onPressed: () async {
                    if (_ctrl.text.trim().isEmpty) return;
                    await provider.completeUntitledDraft(
                      id: widget.draft.id,
                      title: _ctrl.text.trim(),
                      macroProjectId: _macroId,
                      subProjectId: _subId,
                      tagIds: widget.draft.tagIds,
                    );
                  },
                  child: const Text('تکمیل مشخصات'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
