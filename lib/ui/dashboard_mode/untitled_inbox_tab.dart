import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/jalali_date.dart';
import '../../models/outcome_item.dart';
import '../../models/pomodoro_state.dart';
import '../../models/time_record.dart';
import '../../providers/app_state_provider.dart';
import '../shared/searchable_task_input.dart';
import '../shared/unified_project_selector.dart';

class UntitledInboxTab extends StatefulWidget {
  const UntitledInboxTab({super.key});

  @override
  State<UntitledInboxTab> createState() => _UntitledInboxTabState();
}

class _UntitledInboxTabState extends State<UntitledInboxTab> {
  AppRealm? _realmFilter;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final palette = provider.activePalette;
    final allDrafts = provider.untitledDraftRecords;
    final drafts = _realmFilter == null
        ? allDrafts
        : allDrafts.where((r) => r.realm == _realmFilter).toList();

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
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'کارتابل رکوردهای بدون عنوان: اتصال به هدف موجود یا تعریف کار جدید و تعیین پروژه بدون دست‌زدن به زمان واقعی (بدون برچسب [Edited]).',
                  style: TextStyle(fontSize: 12),
                ),
                SegmentedButton<AppRealm?>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    selectedBackgroundColor: palette.accent.withAlpha(45),
                  ),
                  segments: [
                    ButtonSegment(
                        value: null, label: Text('همه (${allDrafts.length})')),
                    const ButtonSegment(value: AppRealm.work, label: Text('کار')),
                    const ButtonSegment(
                        value: AppRealm.life, label: Text('زندگی')),
                  ],
                  selected: {_realmFilter},
                  onSelectionChanged: (s) =>
                      setState(() => _realmFilter = s.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: drafts.isEmpty
                ? const Center(
                    child: Text(
                      'عالی! هیچ رکورد بدون عنوانی در کارتابل وجود ندارد.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: drafts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _DraftRow(
                      key: ValueKey(drafts[i].id),
                      draft: drafts[i],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DraftRow extends StatefulWidget {
  final TimeRecord draft;
  const _DraftRow({super.key, required this.draft});

  @override
  State<_DraftRow> createState() => _DraftRowState();
}

class _DraftRowState extends State<_DraftRow> {
  final TextEditingController _ctrl = TextEditingController();
  late AppRealm _targetRealm;
  String? _projectId;
  OutcomeItem? _selectedOutcome;

  @override
  void initState() {
    super.initState();
    _targetRealm = widget.draft.realm;
    _projectId = widget.draft.projectId;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit(AppStateProvider provider) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _selectedOutcome == null) return;

    await provider.completeUntitledDraft(
      id: widget.draft.id,
      title: _selectedOutcome?.title ?? text,
      existingOutcomeId: _selectedOutcome?.id,
      projectId: _selectedOutcome?.projectId ?? _projectId,
      newRealm: _targetRealm,
      tagIds: widget.draft.tagIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final palette = provider.activePalette;
    final realmColor = _targetRealm == AppRealm.life
        ? AppColors.lifeGreen
        : AppColors.workBlue;
    final startStr =
        '${JalaliDate.formatWithWeekDay(widget.draft.startTime)} ${DateFormat('HH:mm').format(widget.draft.startTime)}';
    final min = (widget.draft.durationSeconds / 60).toStringAsFixed(1);
    final openOutcomes = provider.getOpenOutcomes(realm: _targetRealm);

    return Card(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: realmColor.withAlpha(90)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: realmColor.withAlpha(35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _targetRealm.labelFa,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: realmColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$startStr — $min دقیقه',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: AppColors.draftWarning,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ActionChip(
                      avatar: Icon(Icons.swap_horiz_rounded,
                          size: 14, color: realmColor),
                      label: Text(
                        _targetRealm == AppRealm.work
                            ? 'تبدیل به زندگی'
                            : 'تبدیل به کار',
                        style: const TextStyle(fontSize: 10.5),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _targetRealm = _targetRealm == AppRealm.work
                              ? AppRealm.life
                              : AppRealm.work;
                          _selectedOutcome = null;
                          if (_projectId != null) {
                            final p = provider.getProjectById(_projectId);
                            if (p != null && p.realm != _targetRealm) {
                              _projectId = null;
                            }
                          }
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: Colors.redAccent),
                      onPressed: () =>
                          provider.deleteTimeRecord(widget.draft.id),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 680;
                final inputWidget = SearchableTaskInput(
                  controller: _ctrl,
                  openOutcomes: openOutcomes,
                  projects: provider.projects,
                  accentColor: realmColor,
                  hintText: 'انتخاب کار باز موجود یا تایپ عنوان جدید...',
                  onSelectOutcome: (o) {
                    setState(() {
                      _selectedOutcome = o;
                      _projectId = o.projectId;
                    });
                  },
                  onChanged: (_) {
                    if (_selectedOutcome != null &&
                        _ctrl.text.trim() != _selectedOutcome!.title) {
                      setState(() => _selectedOutcome = null);
                    }
                  },
                  onSubmitted: () => _submit(provider),
                );
                final projWidget = UnifiedProjectSelector(
                  projects: provider.projects,
                  realmFilter: _targetRealm,
                  selectedProjectId: _projectId,
                  accentColor: realmColor,
                  onSelected: (pid) => setState(() => _projectId = pid),
                );
                final saveBtn = FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: realmColor),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('تکمیل و اتصال'),
                  onPressed: () => _submit(provider),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      inputWidget,
                      const SizedBox(height: 8),
                      projWidget,
                      const SizedBox(height: 8),
                      saveBtn,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: inputWidget),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: projWidget),
                    const SizedBox(width: 8),
                    saveBtn,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
