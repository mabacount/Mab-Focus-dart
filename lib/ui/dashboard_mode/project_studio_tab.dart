import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/date_time_utils.dart';
import '../../core/jalali_date.dart';
import '../../models/outcome_item.dart';
import '../../models/phase_tag.dart';
import '../../models/pomodoro_state.dart';
import '../../models/project_node.dart';
import '../../models/session_note.dart';
import '../../models/time_record.dart';
import '../../providers/app_state_provider.dart';
import '../../services/database_service.dart';
import '../shared/unified_project_selector.dart';

class ProjectStudioTab extends StatefulWidget {
  const ProjectStudioTab({super.key});

  @override
  State<ProjectStudioTab> createState() => _ProjectStudioTabState();
}

class _ProjectStudioTabState extends State<ProjectStudioTab> {
  String? _selectedProjectId;
  AppRealm? _lastRealm;
  final Map<String, bool> _expandedIds = {};
  bool _includeArchived = false;
  bool _showMobileDetail = false;
  SessionNoteType? _noteTypeFilter;

  final TextEditingController _inlineOutcomeCtrl = TextEditingController();
  final TextEditingController _newTagCtrl = TextEditingController();

  static const List<String> _colorSwatches = [
    '#3B82F6',
    '#10B981',
    '#8B5CF6',
    '#F59E0B',
    '#EF4444',
    '#06B6D4',
    '#EC4899',
  ];

  @override
  void dispose() {
    _inlineOutcomeCtrl.dispose();
    _newTagCtrl.dispose();
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

  void _syncSelectedProject(AppStateProvider provider) {
    final realm = provider.dashboardRealm;
    final realmProjects = provider.getProjectsForRealm(
      realm,
      includeArchived: _includeArchived,
    );

    if (_lastRealm != realm) {
      _lastRealm = realm;
      _showMobileDetail = false;
    }

    if (_selectedProjectId != null) {
      final current = provider.getProjectById(_selectedProjectId);
      if (current == null ||
          current.realm != realm ||
          (!_includeArchived && current.isArchived)) {
        _selectedProjectId = null;
      }
    }

    if (_selectedProjectId == null && realmProjects.isNotEmpty) {
      final roots = provider.getRootProjects(
        realm,
        includeArchived: _includeArchived,
      );
      _selectedProjectId =
          roots.isNotEmpty ? roots.first.id : realmProjects.first.id;
    }
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

  Future<void> _showProjectFormDialog(
    BuildContext context,
    AppStateProvider provider, {
    ProjectNode? existing,
    String? initialParentId,
  }) async {
    final realm = existing?.realm ?? provider.dashboardRealm;
    final palette = realm == AppRealm.life ? RealmPalette.life : RealmPalette.work;

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final weeklyCtrl = TextEditingController(
      text: (existing?.weeklyQuotaMinutes ?? 0) > 0
          ? existing!.weeklyQuotaMinutes.toString()
          : '',
    );
    final rateCtrl = TextEditingController(
      text: (existing?.hourlyRate ?? 0) > 0
          ? existing!.hourlyRate.toStringAsFixed(0)
          : '',
    );
    final gcalCtrl =
        TextEditingController(text: existing?.googleCalendarId ?? '');

    String? parentId = existing != null ? existing.parentId : initialParentId;
    String selectedColor =
        existing?.colorHex ?? (realm == AppRealm.life ? '#10B981' : '#3B82F6');
    String status = existing?.status ?? 'active';

    // جلوگیری از چرخه مادر-فرزندی هنگام ویرایش
    final Set<String> forbiddenParentIds = existing != null
        ? DatabaseService.getProjectAndDescendantIds(
            existing.id, provider.projects)
        : <String>{};

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final selectableParents = provider.projects
              .where((p) => !forbiddenParentIds.contains(p.id))
              .toList();

          return AlertDialog(
            backgroundColor: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: palette.border),
            ),
            title: Row(
              children: [
                Icon(
                  existing == null
                      ? Icons.create_new_folder_rounded
                      : Icons.edit_rounded,
                  color: palette.accent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  existing == null
                      ? (initialParentId != null
                          ? 'ایجاد زیرپروژه (${realm.labelFa})'
                          : 'ایجاد پروژه جدید (${realm.labelFa})')
                      : 'ویرایش پروژه: ${existing.name}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'نام پروژه یا زیرپروژه',
                        hintText: 'مثلاً: اپلیکیشن موبایل / خواب شبانه',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    UnifiedProjectSelector(
                      projects: selectableParents,
                      realmFilter: realm,
                      selectedProjectId: parentId,
                      emptyLabel: 'پروژه ریشه (بدون مادر)',
                      accentColor: palette.accent,
                      onSelected: (pid) =>
                          setDialogState(() => parentId = pid),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: weeklyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'سهمیه هفتگی (دقیقه)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: rateCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'نرخ ساعتی (۰ = ارث از مادر)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: gcalCtrl,
                      decoration: const InputDecoration(
                        labelText: 'شناسه تقویم گوگل اختصاصی (اختیاری)',
                        hintText: 'خالی = ارث‌بری از مادر یا تقویم پیش‌فرض قلمرو',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(
                        labelText: 'وضعیت پروژه',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      dropdownColor: palette.surfaceElevated,
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('فعال')),
                        DropdownMenuItem(
                            value: 'suspended', child: Text('معلق (متوقف موقت)')),
                        DropdownMenuItem(
                            value: 'archived', child: Text('آرشیوشده')),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => status = val ?? 'active'),
                    ),
                    const SizedBox(height: 12),
                    const Text('رنگ پروژه:',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: _colorSwatches.map((hex) {
                        final col = _parseHex(hex, palette.accent);
                        final isSel =
                            selectedColor.toUpperCase() == hex.toUpperCase();
                        return InkWell(
                          onTap: () =>
                              setDialogState(() => selectedColor = hex),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSel ? Colors.white : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: isSel
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
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
                style: FilledButton.styleFrom(backgroundColor: palette.accent),
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('ذخیره پروژه'),
                onPressed: () async {
                  final cleanName = nameCtrl.text.trim();
                  if (cleanName.isEmpty) return;

                  final cleanGcal = gcalCtrl.text.trim();
                  final node = existing != null
                      ? existing.copyWith(
                          name: cleanName,
                          parentId: parentId,
                          clearParentId: parentId == null,
                          colorHex: selectedColor,
                          weeklyQuotaMinutes:
                              int.tryParse(weeklyCtrl.text) ?? 0,
                          hourlyRate: double.tryParse(rateCtrl.text) ?? 0.0,
                          googleCalendarId: cleanGcal,
                          clearGoogleCalendarId: cleanGcal.isEmpty,
                          status: status,
                        )
                      : ProjectNode(
                          id: const Uuid().v4(),
                          realm: realm,
                          name: cleanName,
                          parentId: parentId,
                          colorHex: selectedColor,
                          weeklyQuotaMinutes:
                              int.tryParse(weeklyCtrl.text) ?? 0,
                          hourlyRate: double.tryParse(rateCtrl.text) ?? 0.0,
                          googleCalendarId:
                              cleanGcal.isEmpty ? null : cleanGcal,
                          status: status,
                        );

                  await provider.saveProject(node);
                  if (mounted) {
                    setState(() {
                      _selectedProjectId = node.id;
                      if (parentId != null) _expandedIds[parentId!] = true;
                    });
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      weeklyCtrl.dispose();
      rateCtrl.dispose();
      gcalCtrl.dispose();
    });
  }

  void _showPhaseTagsDialog(
      BuildContext context, AppStateProvider provider, RealmPalette palette) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Consumer<AppStateProvider>(
        builder: (ctx, p, _) => AlertDialog(
          backgroundColor: palette.surface,
          title: const Text('مدیریت تگ‌های فاز فعالیت',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTagCtrl,
                        decoration: const InputDecoration(
                          hintText: 'نام تگ جدید (مثلاً: تست و بررسی)...',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: palette.accent),
                      onPressed: () async {
                        final name = _newTagCtrl.text.trim();
                        if (name.isEmpty) return;
                        await p.savePhaseTag(PhaseTag(
                          id: const Uuid().v4(),
                          name: name,
                        ));
                        _newTagCtrl.clear();
                      },
                      child: const Text('افزودن'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: p.phaseTags
                      .map((t) => Chip(
                            label: Text(t.name,
                                style: const TextStyle(fontSize: 12)),
                            onDeleted: () => p.deletePhaseTag(t.id),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('بستن'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    _syncSelectedProject(provider);

    final realm = provider.dashboardRealm;
    final palette = provider.activePalette;
    final scopedProjects = provider.getProjectsForRealm(
      realm,
      includeArchived: _includeArchived,
    );
    final scopedRecords =
        provider.timeRecords.where((r) => r.realm == realm).toList();
    final scopedNotes =
        provider.sessionNotes.where((n) => n.realm == realm).toList();
    final scopedOpenOutcomes = provider.getOpenOutcomes(realm: realm);

    final totalSec =
        scopedRecords.fold<int>(0, (sum, r) => sum + r.durationSeconds);
    final totalHours = (totalSec / 3600.0).toStringAsFixed(1);

    // محاسبه ارزش مالی با نرخ مؤثر بازگشتی روی هر رکورد قلمرو
    final double totalRevenue = scopedRecords.fold<double>(0.0, (sum, r) {
      final rate = provider.getEffectiveHourlyRate(r.projectId);
      return sum + ((r.durationSeconds / 3600.0) * rate);
    });

    final selectedProject = _selectedProjectId != null
        ? provider.getProjectById(_selectedProjectId)
        : null;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ۱. کارت‌های آماری بالای استودیو
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _StudioStatCard(
                  icon: Icons.account_tree_rounded,
                  title: 'پروژه‌های ${realm.labelFa}',
                  value: '${scopedProjects.length} پروژه',
                  color: palette.accent,
                  surface: palette.surface,
                  border: palette.border,
                ),
                _StudioStatCard(
                  icon: Icons.timer_outlined,
                  title: 'مجموع زمان ${realm.labelFa}',
                  value: '$totalHours ساعت',
                  color: AppColors.stopwatch,
                  surface: palette.surface,
                  border: palette.border,
                ),
                totalRevenue > 0
                    ? _StudioStatCard(
                        icon: Icons.attach_money_rounded,
                        title: 'ارزش با ارث‌بری نرخ',
                        value:
                            '${NumberFormat('#,###').format(totalRevenue.round())} ت',
                        color: AppColors.golden,
                        surface: palette.surface,
                        border: palette.border,
                      )
                    : _StudioStatCard(
                        icon: Icons.checklist_rounded,
                        title: 'کارهای باز ${realm.labelFa}',
                        value: '${scopedOpenOutcomes.length} کار',
                        color: AppColors.golden,
                        surface: palette.surface,
                        border: palette.border,
                      ),
                _StudioStatCard(
                  icon: Icons.edit_note_rounded,
                  title: 'یادداشت‌های ${realm.labelFa}',
                  value: '${scopedNotes.length} یادداشت',
                  color: AppColors.lifeGreen,
                  surface: palette.surface,
                  border: palette.border,
                ),
              ];

              if (constraints.maxWidth < 700) {
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.3,
                  children: cards,
                );
              }
              return Row(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          // ۲. نمای دوپانلی درخت پروژه‌ها + فضای کاری تجمیعی (Roll-up Workspace)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSplit = constraints.maxWidth >= 820;

                if (!isSplit) {
                  if (_showMobileDetail && selectedProject != null) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.arrow_forward_rounded,
                                  size: 16),
                              label: const Text('بازگشت به درخت پروژه‌ها'),
                              onPressed: () =>
                                  setState(() => _showMobileDetail = false),
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.label_outline, size: 15),
                              label: const Text('تگ‌ها',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () => _showPhaseTagsDialog(
                                  context, provider, palette),
                            ),
                          ],
                        ),
                        Expanded(
                          child: _buildDetailWorkspace(
                              context, provider, selectedProject, palette),
                        ),
                      ],
                    );
                  }
                  return _buildTreeExplorer(context, provider, palette,
                      isMobile: true);
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 330,
                      child: _buildTreeExplorer(context, provider, palette,
                          isMobile: false),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: selectedProject != null
                          ? _buildDetailWorkspace(
                              context, provider, selectedProject, palette)
                          : _buildEmptyDetailPlaceholder(
                              context, provider, palette),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeExplorer(
    BuildContext context,
    AppStateProvider provider,
    RealmPalette palette, {
    required bool isMobile,
  }) {
    final realm = provider.dashboardRealm;
    final roots = provider.getRootProjects(
      realm,
      includeArchived: _includeArchived,
    );

    return Card(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Icon(Icons.folder_copy_rounded,
                    size: 18, color: palette.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'درخت پروژه‌های ${realm.labelFa}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'مدیریت تگ‌های فاز',
                  icon: const Icon(Icons.label_outline_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      _showPhaseTagsDialog(context, provider, palette),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: palette.accent.withAlpha(38),
                    foregroundColor: palette.accent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('ریشه جدید',
                      style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _showProjectFormDialog(context, provider),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Checkbox(
                  value: _includeArchived,
                  visualDensity: VisualDensity.compact,
                  activeColor: palette.accent,
                  onChanged: (v) =>
                      setState(() => _includeArchived = v ?? false),
                ),
                const Text('نمایش پروژه‌های آرشیوشده',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          Expanded(
            child: roots.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.account_tree_outlined,
                              size: 42, color: AppColors.textMuted),
                          const SizedBox(height: 8),
                          Text(
                            'هنوز پروژه‌ای در قلمرو ${realm.labelFa} ساخته نشده است.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('ساخت اولین پروژه'),
                            onPressed: () =>
                                _showProjectFormDialog(context, provider),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (final root in roots)
                        ..._buildTreeNodeWidgets(
                          context,
                          provider,
                          root,
                          0,
                          palette,
                          isMobile: isMobile,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTreeNodeWidgets(
    BuildContext context,
    AppStateProvider provider,
    ProjectNode node,
    int depth,
    RealmPalette palette, {
    required bool isMobile,
  }) {
    final children = provider.getChildProjects(
      node.id,
      realm: node.realm,
      includeArchived: _includeArchived,
    );
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedIds[node.id] ?? true;
    final isSelected = _selectedProjectId == node.id;
    final pColor = _parseHex(node.colorHex, palette.accent);

    final rollupSec = provider
        .getTimeRecordsForProjectRollup(node.id)
        .fold<int>(0, (s, r) => s + r.durationSeconds);
    final rollupHoursStr = rollupSec >= 3600
        ? '${(rollupSec / 3600.0).toStringAsFixed(1)}h'
        : '${(rollupSec / 60).round()}m';

    final widgets = <Widget>[
      Padding(
        padding: EdgeInsetsDirectional.only(
          start: (depth * 14.0).clamp(0.0, 96.0),
          bottom: 3,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            _selectedProjectId = node.id;
            if (isMobile) _showMobileDetail = true;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? palette.accent.withAlpha(35)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? palette.accent : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                if (hasChildren)
                  InkWell(
                    onTap: () => setState(() => _expandedIds[node.id] = !isExpanded),
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_left_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 4),
                Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: pColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: depth == 0 ? 12.8 : 12.0,
                      fontWeight:
                          depth == 0 || isSelected ? FontWeight.bold : FontWeight.w500,
                      color: node.isArchived
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (node.isSleepProject)
                  const Tooltip(
                    message: 'پروژه خواب — ریست خودکار چرخه Flowmodoro',
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(Icons.bedtime_rounded,
                          size: 13, color: AppColors.lifeGreen),
                    ),
                  ),
                if (node.isSuspended)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(Icons.pause_circle_outline,
                        size: 13, color: AppColors.draftWarning),
                  ),
                if (rollupSec > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      rollupHoursStr,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'افزودن زیرپروژه به «${node.name}»',
                  icon: Icon(Icons.add_circle_outline,
                      size: 16, color: palette.accent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => _showProjectFormDialog(
                    context,
                    provider,
                    initialParentId: node.id,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];

    if (hasChildren && isExpanded) {
      for (final child in children) {
        widgets.addAll(_buildTreeNodeWidgets(
          context,
          provider,
          child,
          depth + 1,
          palette,
          isMobile: isMobile,
        ));
      }
    }

    return widgets;
  }

  Widget _buildEmptyDetailPlaceholder(
      BuildContext context, AppStateProvider provider, RealmPalette palette) {
    return Card(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspaces_outline,
                size: 52, color: palette.accent.withAlpha(140)),
            const SizedBox(height: 10),
            const Text(
              'یک پروژه را از درخت انتخاب کنید یا پروژه جدید بسازید.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: palette.accent),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('ساخت پروژه جدید'),
              onPressed: () => _showProjectFormDialog(context, provider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailWorkspace(
    BuildContext context,
    AppStateProvider provider,
    ProjectNode selected,
    RealmPalette palette,
  ) {
    final breadcrumb = provider.getProjectBreadcrumbString(selected.id);
    final pColor = _parseHex(selected.colorHex, palette.accent);
    final effectiveRate = provider.getEffectiveHourlyRate(selected.id);
    final isRateInherited = selected.hourlyRate <= 0 && effectiveRate > 0;
    final effectiveGcal = DatabaseService.getEffectiveGoogleCalendarId(
        selected.id, provider.projects);

    final rollupRecords = provider.getTimeRecordsForProjectRollup(selected.id);
    final rollupOutcomes = provider.getOutcomesForProjectRollup(selected.id);
    final openOutcomes =
        rollupOutcomes.where((o) => !o.isCompleted).toList();
    final completedOutcomes =
        rollupOutcomes.where((o) => o.isCompleted).toList();
    final allRollupNotes =
        provider.getSessionNotesForProjectRollup(selected.id);
    final filteredNotes = _noteTypeFilter == null
        ? allRollupNotes
        : allRollupNotes
            .where((n) => n.noteType == _noteTypeFilter)
            .toList();
    final directChildren = provider.getChildProjects(
      selected.id,
      realm: selected.realm,
      includeArchived: _includeArchived,
    );

    final totalSec =
        rollupRecords.fold<int>(0, (sum, r) => sum + r.durationSeconds);
    final totalHoursStr = (totalSec / 3600.0).toStringAsFixed(1);
    final totalValue = ((totalSec / 3600.0) * effectiveRate).round();

    // پیشرفت بودجه هفتگی از بامداد شنبه (چالش ۶)
    final startOfWeek = DateTimeUtils.startOfJalaliWeek(DateTime.now());
    final weekSec = rollupRecords
        .where((r) => !r.startTime.isBefore(startOfWeek))
        .fold<int>(0, (s, r) => s + r.durationSeconds);
    final weekMin = (weekSec / 60.0);
    final quotaMin = selected.weeklyQuotaMinutes.toDouble();
    final quotaPct = quotaMin > 0 ? (weekMin / quotaMin).clamp(0.0, 1.0) : 0.0;

    return Card(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      child: DefaultTabController(
        length: 4,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // هدر پروژه با مسير کامل، بج‌ها و اکشن‌ها
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                            color: pColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Text(
                          breadcrumb,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.create_new_folder_outlined,
                            size: 15),
                        label: const Text('+ زیرپروژه',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () => _showProjectFormDialog(
                          context,
                          provider,
                          initialParentId: selected.id,
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        label: const Text('ویرایش',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () => _showProjectFormDialog(
                          context,
                          provider,
                          existing: selected,
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        icon: Icon(
                          selected.isSuspended
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          size: 15,
                        ),
                        label: Text(
                          selected.isSuspended ? 'فعال' : 'تعلیق',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () => provider.saveProject(selected.copyWith(
                          status:
                              selected.isSuspended ? 'active' : 'suspended',
                        )),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.table_chart_rounded,
                            size: 15, color: AppColors.lifeGreen),
                        label: const Text('اکسل کارکرد',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () async {
                          final path = await provider
                              .exportRecordsToExcel(rollupRecords);
                          if (context.mounted && path != null) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('فایل اکسل ذخیره شد: $path'),
                              backgroundColor: AppColors.lifeGreen,
                            ));
                          }
                        },
                      ),
                      if (allRollupNotes.isNotEmpty)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                          icon: Icon(Icons.note_alt_rounded,
                              size: 15, color: palette.accent),
                          label: const Text('اکسل یادداشت‌ها',
                              style: TextStyle(fontSize: 11)),
                          onPressed: () async {
                            final path = await provider
                                .exportSessionNotesToExcel(allRollupNotes);
                            if (context.mounted && path != null) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('فایل یادداشت ذخیره شد: $path'),
                                backgroundColor: AppColors.lifeGreen,
                              ));
                            }
                          },
                        ),
                      IconButton(
                        tooltip: 'حذف پروژه و زیرمجموعه‌هایش',
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.redAccent),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('حذف پروژه'),
                              content: Text(
                                  'آیا «${selected.name}» و تمام زیرپروژه‌هایش حذف شوند؟ کارها و رکوردهای قدیمی حفظ و از اتصال پروژه خارج می‌شوند.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(c).pop(false),
                                  child: const Text('انصراف'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Colors.redAccent),
                                  onPressed: () => Navigator.of(c).pop(true),
                                  child: const Text('حذف'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await provider.deleteProject(selected.id);
                            if (mounted) {
                              setState(() {
                                _selectedProjectId = null;
                                _showMobileDetail = false;
                              });
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // نوار خلاصه Roll-up (تجمیع با تمام زیرپروژه‌ها)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    _MiniMetric(
                      label: 'کارکرد تجمیعی',
                      value: '$totalHoursStr ساعت (${rollupRecords.length} رکورد)',
                      color: palette.accent,
                    ),
                    _MiniMetric(
                      label: 'کارهای باز / کل',
                      value: '${openOutcomes.length} / ${rollupOutcomes.length}',
                      color: AppColors.textPrimary,
                    ),
                    if (effectiveRate > 0)
                      _MiniMetric(
                        label: isRateInherited
                            ? 'نرخ مؤثر (ارث‌بری)'
                            : 'نرخ / ارزش کل',
                        value:
                            '${NumberFormat('#,###').format(effectiveRate.round())} ت  •  ${NumberFormat('#,###').format(totalValue)} ت',
                        color: AppColors.golden,
                      ),
                    if (effectiveGcal != null)
                      _MiniMetric(
                        label: 'تقویم گوگل متصل',
                        value: effectiveGcal,
                        color: AppColors.stopwatch,
                      ),
                  ],
                ),
              ),

              if (selected.weeklyQuotaMinutes > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'سهمیه هفتگی (از بامداد شنبه با تجمیع زیرپروژه‌ها):',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                          Text(
                            '${weekMin.toStringAsFixed(0)} از ${selected.weeklyQuotaMinutes} دقیقه (${(quotaPct * 100).toStringAsFixed(0)}%)',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: quotaPct >= 1.0
                                  ? Colors.redAccent
                                  : palette.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: quotaPct,
                          minHeight: 6,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            quotaPct >= 1.0
                                ? Colors.redAccent
                                : palette.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),

              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: palette.accent,
                labelColor: palette.accent,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: [
                  Tab(text: 'کارها / اهداف (${rollupOutcomes.length})'),
                  Tab(text: 'رکوردهای زمانی (${rollupRecords.length})'),
                  Tab(text: 'یادداشت‌ها (${allRollupNotes.length})'),
                  Tab(text: 'زیرپروژه‌ها (${directChildren.length})'),
                ],
              ),
              const SizedBox(height: 8),

              Expanded(
                child: TabBarView(
                  children: [
                    // تب ۱: کارها / اهداف باز و تکمیل‌شده (تجمیعی)
                    _buildOutcomesSubTab(
                      context,
                      provider,
                      selected,
                      openOutcomes,
                      completedOutcomes,
                      palette,
                    ),

                    // تب ۲: رکوردهای زمانی (تجمیعی)
                    _buildRecordsSubTab(
                      context,
                      provider,
                      rollupRecords,
                      palette,
                    ),

                    // تب ۳: یادداشت‌ها (تجمیعی با فیلتر SessionNoteType)
                    _buildNotesSubTab(
                      context,
                      provider,
                      filteredNotes,
                      palette,
                    ),

                    // تب ۴: زیرپروژه‌های مستقیم و سهم هرکدام
                    _buildChildrenSubTab(
                      context,
                      provider,
                      directChildren,
                      totalSec,
                      palette,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutcomesSubTab(
    BuildContext context,
    AppStateProvider provider,
    ProjectNode selected,
    List<OutcomeItem> openOutcomes,
    List<OutcomeItem> completedOutcomes,
    RealmPalette palette,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inlineOutcomeCtrl,
                decoration: InputDecoration(
                  hintText: 'افزودن کار/هدف جدید در «${selected.name}»...',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _saveInlineOutcome(provider, selected),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: palette.accent),
              icon: const Icon(Icons.add_task_rounded, size: 16),
              label: const Text('افزودن'),
              onPressed: () => _saveInlineOutcome(provider, selected),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: (openOutcomes.isEmpty && completedOutcomes.isEmpty)
              ? const Center(
                  child: Text('هنوز کاری برای این شاخه تعریف نشده است.',
                      style: TextStyle(color: AppColors.textMuted)),
                )
              : ListView(
                  children: [
                    ...openOutcomes.map((o) => _buildOutcomeTile(
                          provider,
                          o,
                          palette,
                        )),
                    if (completedOutcomes.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'تکمیل‌شده / بایگانی (${completedOutcomes.length})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      ...completedOutcomes.map((o) => _buildOutcomeTile(
                            provider,
                            o,
                            palette,
                          )),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _saveInlineOutcome(
      AppStateProvider provider, ProjectNode selected) async {
    final text = _inlineOutcomeCtrl.text.trim();
    if (text.isEmpty) return;
    await provider.saveOutcome(OutcomeItem(
      id: const Uuid().v4(),
      realm: selected.realm,
      projectId: selected.id,
      title: text,
      isCompleted: false,
    ));
    _inlineOutcomeCtrl.clear();
  }

  Widget _buildOutcomeTile(
      AppStateProvider provider, OutcomeItem o, RealmPalette palette) {
    final totalSec = provider.getTotalSecondsForOutcome(o.id);
    final proj = provider.getProjectById(o.projectId);
    final isActive = provider.activeOutcome?.id == o.id;

    return Card(
      color: palette.surfaceElevated,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Checkbox(
          value: o.isCompleted,
          activeColor: palette.accent,
          onChanged: (v) {
            if (v == true) {
              provider.markOutcomeCompleted(o.id);
            } else {
              provider.reopenOutcome(o.id);
            }
          },
        ),
        title: Text(
          o.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: o.isCompleted ? TextDecoration.lineThrough : null,
            color:
                o.isCompleted ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          '${proj?.name ?? ""} • زمان کل: ${DateTimeUtils.formatDurationHms(totalSec)}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: o.isCompleted
            ? TextButton(
                onPressed: () => provider.reopenOutcome(o.id),
                child: const Text('بازگشایی', style: TextStyle(fontSize: 11)),
              )
            : (isActive
                ? Text('فعال',
                    style: TextStyle(
                        fontSize: 11,
                        color: palette.accent,
                        fontWeight: FontWeight.bold))
                : FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: palette.accent.withAlpha(35),
                      foregroundColor: palette.accent,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 15),
                    label: const Text('شروع', style: TextStyle(fontSize: 11)),
                    onPressed: () => provider.startOrSwitchToOutcome(o),
                  )),
      ),
    );
  }

  Widget _buildRecordsSubTab(
    BuildContext context,
    AppStateProvider provider,
    List<TimeRecord> records,
    RealmPalette palette,
  ) {
    if (records.isEmpty) {
      return const Center(
        child: Text('هیچ رکورد زمانی برای این پروژه ثبت نشده است.',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.separated(
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final r = records[i];
        final childProj = provider.getProjectById(r.projectId);
        final outcome =
            r.outcomeId != null ? provider.getOutcomeById(r.outcomeId!) : null;

        return Card(
          color: palette.surfaceElevated,
          child: ListTile(
            dense: true,
            leading: Icon(
              r.isStopwatch ? Icons.timer_outlined : Icons.bolt_rounded,
              size: 18,
              color: r.isLife ? AppColors.lifeGreen : AppColors.workBlue,
            ),
            title: Text(
              outcome?.title ?? r.titleSnapshot,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${JalaliDate.formatWithWeekDay(r.startTime)} ${DateFormat('HH:mm').format(r.startTime)}'
              '${childProj != null ? " • ${childProj.name}" : ""}'
              '${r.isEdited ? " • [Edited]" : ""}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateTimeUtils.formatDurationHms(r.durationSeconds),
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip:
                      'تبدیل به ${r.isWork ? "زندگی" : "کار"} (چالش ۲)',
                  icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                  onPressed: () => provider.swapSavedRecordRealm(r.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotesSubTab(
    BuildContext context,
    AppStateProvider provider,
    List<SessionNote> notes,
    RealmPalette palette,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('همه', style: TextStyle(fontSize: 11)),
                selected: _noteTypeFilter == null,
                onSelected: (_) => setState(() => _noteTypeFilter = null),
              ),
              const SizedBox(width: 6),
              ...SessionNoteType.values.map((t) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: FilterChip(
                      avatar: Icon(t.icon, size: 14, color: t.color),
                      label: Text(t.labelFa,
                          style: const TextStyle(fontSize: 11)),
                      selected: _noteTypeFilter == t,
                      onSelected: (_) => setState(() =>
                          _noteTypeFilter = _noteTypeFilter == t ? null : t),
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: notes.isEmpty
              ? const Center(
                  child: Text('هیچ یادداشتی برای این شاخه یافت نشد.',
                      style: TextStyle(color: AppColors.textMuted)),
                )
              : ListView.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final note = notes[i];
                    final outcome = note.outcomeId != null
                        ? provider.getOutcomeById(note.outcomeId!)
                        : null;
                    final record = note.timeRecordId != null
                        ? provider.getTimeRecordById(note.timeRecordId!)
                        : null;
                    final childProj = provider.getProjectById(note.projectId);
                    final targetTitle =
                        outcome?.title ?? record?.titleSnapshot ?? 'یادداشت';
                    final dateStr =
                        '${JalaliDate.formatWithWeekDay(note.createdAt)} ${DateFormat('HH:mm').format(note.createdAt)}';

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: palette.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: palette.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: note.noteType.color.withAlpha(35),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  note.noteType.labelFa,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: note.noteType.color,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$targetTitle${childProj != null ? " (${childProj.name})" : ""}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                              ),
                              Text(
                                dateStr,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          if (note.content.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            SelectableText(note.content,
                                style: const TextStyle(fontSize: 12)),
                          ],
                          if (note.imagePaths.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 54,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: note.imagePaths.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 6),
                                itemBuilder: (_, imgIdx) {
                                  final path = note.imagePaths[imgIdx];
                                  final f = File(path);
                                  return InkWell(
                                    onTap: () =>
                                        _showImagePreview(context, path),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: f.existsSync()
                                          ? Image.file(f,
                                              width: 54,
                                              height: 54,
                                              fit: BoxFit.cover)
                                          : const SizedBox(
                                              width: 54,
                                              height: 54,
                                              child: Icon(Icons.broken_image)),
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
        ),
      ],
    );
  }

  Widget _buildChildrenSubTab(
    BuildContext context,
    AppStateProvider provider,
    List<ProjectNode> children,
    int parentTotalSeconds,
    RealmPalette palette,
  ) {
    if (children.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('این پروژه هیچ زیرپروژه‌ای ندارد.',
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('ایجاد زیرپروژه'),
              onPressed: () => _showProjectFormDialog(
                context,
                provider,
                initialParentId: _selectedProjectId,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final child = children[i];
        final cColor = _parseHex(child.colorHex, palette.accent);
        final cRecords = provider.getTimeRecordsForProjectRollup(child.id);
        final cSec = cRecords.fold<int>(0, (s, r) => s + r.durationSeconds);
        final cHours = (cSec / 3600.0).toStringAsFixed(1);
        final share = parentTotalSeconds > 0
            ? (cSec / parentTotalSeconds).clamp(0.0, 1.0)
            : 0.0;
        final cRate = provider.getEffectiveHourlyRate(child.id);

        return Card(
          color: palette.surfaceElevated,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _selectedProjectId = child.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: cColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          child.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      Text(
                        '$cHours ساعت (${(share * 100).toStringAsFixed(0)}%)',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5, color: cColor),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_left_rounded,
                          size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 5,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(cColor),
                    ),
                  ),
                  if (cRate > 0) ...[
                    const SizedBox(height: 5),
                    Text(
                      'نرخ ساعتی مؤثر: ${NumberFormat('#,###').format(cRate.round())} تومان',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
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
  final Color surface;
  final Color border;

  const _StudioStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.surface,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.bold),
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

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
