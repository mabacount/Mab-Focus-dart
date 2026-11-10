import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/date_time_utils.dart';
import '../../core/jalali_date.dart';
import '../../models/outcome_item.dart';
import '../../models/pomodoro_state.dart';
import '../../providers/app_state_provider.dart';
import '../../services/database_service.dart';
import '../shared/unified_project_selector.dart';

enum _OutcomeFilterMode { open, completed, all }

class OpenOutcomesTab extends StatefulWidget {
  const OpenOutcomesTab({super.key});

  @override
  State<OpenOutcomesTab> createState() => _OpenOutcomesTabState();
}

class _OpenOutcomesTabState extends State<OpenOutcomesTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _quickTitleCtrl = TextEditingController();

  _OutcomeFilterMode _filterMode = _OutcomeFilterMode.open;
  String? _filterProjectId;
  String? _quickProjectId;
  AppRealm? _lastSeenRealm;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _quickTitleCtrl.dispose();
    super.dispose();
  }

  Color _parseHex(String hex, Color fallback) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  void _syncSelectionWithRealm(AppStateProvider provider) {
    final realm = provider.dashboardRealm;
    if (_lastSeenRealm != realm) {
      _lastSeenRealm = realm;
      if (_filterProjectId != null) {
        final p = provider.getProjectById(_filterProjectId);
        if (p == null || p.realm != realm) {
          _filterProjectId = null;
        }
      }
      if (_quickProjectId != null) {
        final p = provider.getProjectById(_quickProjectId);
        if (p == null || p.realm != realm) {
          _quickProjectId = null;
        }
      }
    }
  }

  Future<void> _addQuickOutcome(
    BuildContext context,
    AppStateProvider provider, {
    required bool startImmediately,
  }) async {
    final title = _quickTitleCtrl.text.trim();
    if (title.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final accent = provider.activePalette.accent;
    final realm = provider.dashboardRealm;
    if (startImmediately) {
      await provider.createAndStartOutcome(
        realm: realm,
        title: title,
        projectId: _quickProjectId,
      );
    } else {
      final item = OutcomeItem(
        id: const Uuid().v4(),
        realm: realm,
        projectId: _quickProjectId,
        title: title,
        isCompleted: false,
      );
      await provider.saveOutcome(item);
    }

    _quickTitleCtrl.clear();
    if (mounted) {
      setState(() {});
      messenger.showSnackBar(
        SnackBar(
          content: Text(startImmediately
              ? 'هدف «$title» ایجاد شد و تایمر روی آن شروع به کار کرد.'
              : 'هدف «$title» به فهرست کارهای باز اضافه شد.'),
          backgroundColor: accent,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showEditOutcomeDialog(
    BuildContext context,
    AppStateProvider provider,
    OutcomeItem outcome,
  ) {
    final titleCtrl = TextEditingController(text: outcome.title);
    final descCtrl = TextEditingController(text: outcome.description);
    String? selectedProjectId = outcome.projectId;
    final palette = outcome.isLife ? RealmPalette.life : RealmPalette.work;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: palette.border),
          ),
          title: Row(
            children: [
              Icon(Icons.edit_note_rounded, color: palette.accent, size: 22),
              const SizedBox(width: 8),
              Text(
                'ویرایش کار / هدف (${outcome.realm.labelFa})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
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
                  decoration: const InputDecoration(
                    labelText: 'عنوان کار / نتیجه ملموس',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات یا معیار تکمیل (اختیاری)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                UnifiedProjectSelector(
                  projects: provider.projects,
                  realmFilter: outcome.realm,
                  selectedProjectId: selectedProjectId,
                  accentColor: palette.accent,
                  onSelected: (pid) =>
                      setDialogState(() => selectedProjectId = pid),
                ),
                const SizedBox(height: 8),
                const Text(
                  'تغییر پروژه این کار به صورت خودکار روی تمام برش‌های زمانی و یادداشت‌های متصل به آن اعمال می‌شود (قانون یکپارچگی پروژه).',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
              style: FilledButton.styleFrom(backgroundColor: palette.accent),
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('ذخیره تغییرات'),
              onPressed: () async {
                final clean = titleCtrl.text.trim();
                if (clean.isEmpty) return;
                await provider.saveOutcome(
                  outcome.copyWith(
                    title: clean,
                    description: descCtrl.text.trim(),
                    projectId: selectedProjectId,
                    clearProjectId: selectedProjectId == null,
                  ),
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      titleCtrl.dispose();
      descCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    _syncSelectionWithRealm(provider);

    final realm = provider.dashboardRealm;
    final palette = provider.activePalette;
    final openAll = provider.getOpenOutcomes(realm: realm);
    final completedAll = provider.getCompletedOutcomes(realm: realm);

    final Set<String>? projectFamilyFilter = _filterProjectId != null
        ? DatabaseService.getProjectAndDescendantIds(
            _filterProjectId!, provider.projects)
        : null;

    final query = _searchCtrl.text.trim().toLowerCase();

    final List<OutcomeItem> baseList;
    switch (_filterMode) {
      case _OutcomeFilterMode.open:
        baseList = openAll;
        break;
      case _OutcomeFilterMode.completed:
        baseList = completedAll;
        break;
      case _OutcomeFilterMode.all:
        baseList = [...openAll, ...completedAll];
        break;
    }

    final filtered = baseList.where((o) {
      if (projectFamilyFilter != null) {
        if (o.projectId == null || !projectFamilyFilter.contains(o.projectId)) {
          return false;
        }
      }
      if (query.isNotEmpty) {
        final matchTitle = o.title.toLowerCase().contains(query);
        final matchDesc = o.description.toLowerCase().contains(query);
        final matchProj = provider
            .getProjectBreadcrumbString(o.projectId)
            .toLowerCase()
            .contains(query);
        if (!matchTitle && !matchDesc && !matchProj) return false;
      }
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ۱. هدر قلمرو + باکس ایجاد سریع کار/هدف جدید
          Card(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final bool isNarrow = constraints.maxWidth < 680;
                      final headerInfo = Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: palette.accent.withAlpha(30),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              realm == AppRealm.life
                                  ? Icons.spa_rounded
                                  : Icons.checklist_rounded,
                              color: palette.accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'کارها و اهداف باز (${realm.labelFa})',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'کارهای باز در جست‌وجوی لحظه‌ای ویجت نمایش داده می‌شوند و با تیک زدن به بایگانی منتقل می‌شوند.',
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary.withAlpha(220),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      final chips = Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _CountChip(
                            label: 'باز: ${openAll.length}',
                            color: palette.accent,
                          ),
                          _CountChip(
                            label: 'تکمیل‌شده: ${completedAll.length}',
                            color: AppColors.textSecondary,
                          ),
                        ],
                      );
                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            headerInfo,
                            const SizedBox(height: 8),
                            chips,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: headerInfo),
                          const SizedBox(width: 12),
                          chips,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 720;
                      if (isCompact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _quickTitleCtrl,
                              decoration: InputDecoration(
                                hintText:
                                    'عنوان کار یا هدف جدید در قلمرو ${realm.labelFa}...',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                fillColor: AppColors.background,
                                filled: true,
                              ),
                              onSubmitted: (_) => _addQuickOutcome(
                                  context, provider,
                                  startImmediately: false),
                            ),
                            const SizedBox(height: 8),
                            UnifiedProjectSelector(
                              projects: provider.projects,
                              realmFilter: realm,
                              selectedProjectId: _quickProjectId,
                              accentColor: palette.accent,
                              onSelected: (pid) =>
                                  setState(() => _quickProjectId = pid),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.add_rounded, size: 16),
                                    label: const Text('افزودن به فهرست'),
                                    onPressed: () => _addQuickOutcome(
                                        context, provider,
                                        startImmediately: false),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: palette.accent),
                                    icon: const Icon(Icons.play_arrow_rounded,
                                        size: 16),
                                    label: const Text('ایجاد و شروع'),
                                    onPressed: () => _addQuickOutcome(
                                        context, provider,
                                        startImmediately: true),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: _quickTitleCtrl,
                              decoration: InputDecoration(
                                hintText:
                                    'عنوان کار یا هدف جدید در قلمرو ${realm.labelFa}...',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                fillColor: AppColors.background,
                                filled: true,
                              ),
                              onSubmitted: (_) => _addQuickOutcome(
                                  context, provider,
                                  startImmediately: false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: UnifiedProjectSelector(
                              projects: provider.projects,
                              realmFilter: realm,
                              selectedProjectId: _quickProjectId,
                              accentColor: palette.accent,
                              onSelected: (pid) =>
                                  setState(() => _quickProjectId = pid),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('افزودن'),
                            onPressed: () => _addQuickOutcome(
                                context, provider,
                                startImmediately: false),
                          ),
                          const SizedBox(width: 6),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: palette.accent),
                            icon:
                                const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('ایجاد و شروع'),
                            onPressed: () => _addQuickOutcome(
                                context, provider,
                                startImmediately: true),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ۲. نوار جستجو و فیلتر وضعیت و پروژه
          Card(
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
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'جست‌وجو در کارها و اهداف...',
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: UnifiedProjectSelector(
                      projects: provider.projects,
                      realmFilter: realm,
                      selectedProjectId: _filterProjectId,
                      emptyLabel: 'فیلتر پروژه: همه پروژه‌ها',
                      accentColor: palette.accent,
                      onSelected: (pid) =>
                          setState(() => _filterProjectId = pid),
                    ),
                  ),
                  SegmentedButton<_OutcomeFilterMode>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      selectedBackgroundColor: palette.accent.withAlpha(50),
                      selectedForegroundColor: palette.accent,
                    ),
                    segments: const [
                      ButtonSegment(
                          value: _OutcomeFilterMode.open, label: Text('باز')),
                      ButtonSegment(
                          value: _OutcomeFilterMode.completed,
                          label: Text('بایگانی')),
                      ButtonSegment(
                          value: _OutcomeFilterMode.all, label: Text('همه')),
                    ],
                    selected: {_filterMode},
                    onSelectionChanged: (s) =>
                        setState(() => _filterMode = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ۳. لیست کارها و اهداف
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _filterMode == _OutcomeFilterMode.completed
                              ? Icons.inventory_2_outlined
                              : Icons.task_alt_rounded,
                          size: 46,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _filterMode == _OutcomeFilterMode.completed
                              ? 'هیچ کار تکمیل‌شده‌ای در این فیلتر یافت نشد.'
                              : 'هیچ کار بازی در قلمرو ${realm.labelFa} ثبت نشده است.',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, idx) {
                      final outcome = filtered[idx];
                      final proj = provider.getProjectById(outcome.projectId);
                      final breadcrumb =
                          provider.getProjectBreadcrumbString(outcome.projectId);
                      final pColor = proj != null
                          ? _parseHex(proj.colorHex, palette.accent)
                          : palette.accent;
                      final totalSec =
                          provider.getTotalSecondsForOutcome(outcome.id);
                      final sliceCount =
                          provider.getRecordsForOutcome(outcome.id).length;
                      final noteCount =
                          provider.getNotesForOutcome(outcome.id).length;
                      final isActiveNow =
                          provider.activeOutcome?.id == outcome.id;

                      return Card(
                        color: palette.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isActiveNow
                                ? palette.accent
                                : palette.border,
                            width: isActiveNow ? 1.5 : 1.0,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: outcome.isCompleted,
                                activeColor: palette.accent,
                                onChanged: (val) async {
                                  if (val == true) {
                                    await provider
                                        .markOutcomeCompleted(outcome.id);
                                  } else {
                                    await provider.reopenOutcome(outcome.id);
                                  }
                                },
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          outcome.title,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            decoration: outcome.isCompleted
                                                ? TextDecoration.lineThrough
                                                : null,
                                            color: outcome.isCompleted
                                                ? AppColors.textSecondary
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                        if (isActiveNow)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: palette.accent
                                                  .withAlpha(45),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'در حال انجام',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: palette.accent,
                                              ),
                                            ),
                                          ),
                                        if (breadcrumb.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: pColor.withAlpha(32),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              breadcrumb,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: pColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (outcome.description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        outcome.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          'زمان کل: ${DateTimeUtils.formatDurationHms(totalSec)}',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 11,
                                            color: palette.accent,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '$sliceCount برش زمانی',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary),
                                        ),
                                        if (noteCount > 0)
                                          Text(
                                            '$noteCount یادداشت',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.edited),
                                          ),
                                        if (outcome.completedAt != null)
                                          Text(
                                            'تکمیل: ${JalaliDate.formatWithWeekDay(outcome.completedAt!)}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.lifeGreen),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (!outcome.isCompleted && !isActiveNow)
                                    FilledButton.tonalIcon(
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor:
                                            palette.accent.withAlpha(35),
                                        foregroundColor: palette.accent,
                                      ),
                                      icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 16),
                                      label: const Text('شروع',
                                          style: TextStyle(fontSize: 11.5)),
                                      onPressed: () => provider
                                          .startOrSwitchToOutcome(outcome),
                                    ),
                                  if (outcome.isCompleted)
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact),
                                      icon: const Icon(Icons.replay_rounded,
                                          size: 15),
                                      label: const Text('بازگشایی',
                                          style: TextStyle(fontSize: 11)),
                                      onPressed: () =>
                                          provider.reopenOutcome(outcome.id),
                                    ),
                                  IconButton(
                                    tooltip: 'ویرایش کار و پروژه متصل',
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    onPressed: () => _showEditOutcomeDialog(
                                        context, provider, outcome),
                                  ),
                                  IconButton(
                                    tooltip: 'حذف کار',
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18, color: Colors.redAccent),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('حذف کار/هدف'),
                                          content: Text(
                                              'آیا «${outcome.title}» حذف شود؟ رکوردهای زمانی قبلی در تاریخچه باقی می‌مانند.'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(c).pop(false),
                                              child: const Text('انصراف'),
                                            ),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.redAccent),
                                              onPressed: () =>
                                                  Navigator.of(c).pop(true),
                                              child: const Text('حذف'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await provider
                                            .deleteOutcome(outcome.id);
                                      }
                                    },
                                  ),
                                ],
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
}

class _CountChip extends StatelessWidget {
  final String label;
  final Color color;

  const _CountChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
