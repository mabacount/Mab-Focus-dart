import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/pomodoro_state.dart';
import '../../models/project_node.dart';
import '../../services/database_service.dart';

class UnifiedProjectSelector extends StatefulWidget {
  final List<ProjectNode> projects;
  final AppRealm? realmFilter;
  final String? selectedProjectId;
  final ValueChanged<String?> onSelected;
  final bool isDense;
  final String emptyLabel;
  final Color? accentColor;

  const UnifiedProjectSelector({
    super.key,
    required this.projects,
    this.realmFilter,
    this.selectedProjectId,
    required this.onSelected,
    this.isDense = true,
    this.emptyLabel = 'بدون پروژه (عمومی)',
    this.accentColor,
  });

  @override
  State<UnifiedProjectSelector> createState() => _UnifiedProjectSelectorState();
}

class _UnifiedProjectSelectorState extends State<UnifiedProjectSelector> {
  Color _parseHex(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return widget.accentColor ?? AppColors.workBlue;
    }
  }

  List<ProjectNode> get _scopedProjects {
    return widget.projects
        .where((p) =>
            !p.isArchived &&
            (widget.realmFilter == null || p.realm == widget.realmFilter))
        .toList();
  }

  String _getDisplayText() {
    if (widget.selectedProjectId == null) return widget.emptyLabel;
    final chain = DatabaseService.getProjectBreadcrumb(
        widget.selectedProjectId, widget.projects);
    if (chain.isEmpty) return widget.emptyLabel;
    return chain.map((e) => e.name).join(' > ');
  }

  Color _getSelectedColor() {
    if (widget.selectedProjectId != null) {
      for (final p in widget.projects) {
        if (p.id == widget.selectedProjectId) {
          return _parseHex(p.colorHex);
        }
      }
    }
    return AppColors.textMuted;
  }

  /// ساخت فهرست مسطح از درخت پروژه‌ها با حفظ عمق (Depth) برای نمایش تودرتوی بی‌نهایت سطحی
  List<({ProjectNode node, int depth, String pathLabel})> _buildTreeRows(
      List<ProjectNode> source, String searchQuery) {
    final Map<String, List<ProjectNode>> childrenByParent = {};
    final Set<String> allIds = source.map((p) => p.id).toSet();

    for (final p in source) {
      final key =
          (p.parentId != null && allIds.contains(p.parentId)) ? p.parentId! : '';
      childrenByParent.putIfAbsent(key, () => []).add(p);
    }

    final List<({ProjectNode node, int depth, String pathLabel})> rows = [];

    if (searchQuery.isNotEmpty) {
      for (final p in source) {
        final path = DatabaseService.getProjectBreadcrumb(p.id, source)
            .map((e) => e.name)
            .join(' > ');
        if (p.name.toLowerCase().contains(searchQuery) ||
            path.toLowerCase().contains(searchQuery)) {
          rows.add((node: p, depth: 0, pathLabel: path));
        }
      }
      return rows;
    }

    void visit(String parentKey, int depth, String prefix) {
      final kids = childrenByParent[parentKey] ?? [];
      for (final child in kids) {
        final fullPath = prefix.isEmpty ? child.name : '$prefix > ${child.name}';
        rows.add((node: child, depth: depth, pathLabel: fullPath));
        visit(child.id, depth + 1, fullPath);
      }
    }

    visit('', 0, '');
    return rows;
  }

  void _openSelectionDialog() {
    final realmColor = widget.accentColor ??
        (widget.realmFilter == AppRealm.life
            ? AppColors.lifeGreen
            : AppColors.workBlue);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final scoped = _scopedProjects;
            final treeRows = _buildTreeRows(scoped, searchQuery);

            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: Row(
                children: [
                  Icon(Icons.account_tree_rounded,
                      size: 18, color: realmColor),
                  const SizedBox(width: 8),
                  Text(
                    widget.realmFilter != null
                        ? 'انتخاب پروژه (${widget.realmFilter!.labelFa})'
                        : 'انتخاب پروژه درختی',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                height: 440,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'جست‌وجوی پروژه در هر عمق درخت...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => setDialogState(
                          () => searchQuery = val.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.circle_outlined,
                                size: 14, color: AppColors.textMuted),
                            title: Text(widget.emptyLabel,
                                style: const TextStyle(fontSize: 13)),
                            selected: widget.selectedProjectId == null,
                            selectedColor: realmColor,
                            onTap: () {
                              widget.onSelected(null);
                              Navigator.of(ctx).pop();
                            },
                          ),
                          const Divider(height: 1, color: AppColors.border),
                          if (treeRows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  'پروژه‌ای با این مشخصات یافت نشد.',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.textMuted),
                                ),
                              ),
                            )
                          else
                            ...treeRows.map((row) {
                              final p = row.node;
                              final pColor = _parseHex(p.colorHex);
                              final isSelected =
                                  widget.selectedProjectId == p.id;
                              return Padding(
                                padding: EdgeInsetsDirectional.only(
                                    start: (row.depth * 18.0).clamp(0.0, 120.0)),
                                child: ListTile(
                                  dense: true,
                                  leading: row.depth == 0
                                      ? Container(
                                          width: 11,
                                          height: 11,
                                          decoration: BoxDecoration(
                                            color: pColor,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      : Icon(Icons.subdirectory_arrow_left_rounded,
                                          size: 14, color: pColor),
                                  title: Text(
                                    searchQuery.isNotEmpty
                                        ? row.pathLabel
                                        : p.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: row.depth == 0 ? 13 : 12.2,
                                      fontWeight: row.depth == 0
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  trailing: p.realm == AppRealm.life &&
                                          widget.realmFilter == null
                                      ? const Text('زندگی',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: AppColors.lifeGreen))
                                      : null,
                                  selected: isSelected,
                                  selectedColor: pColor,
                                  onTap: () {
                                    widget.onSelected(p.id);
                                    Navigator.of(ctx).pop();
                                  },
                                ),
                              );
                            }),
                        ],
                      ),
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _openSelectionDialog,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: 10, vertical: widget.isDense ? 8 : 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _getSelectedColor(),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getDisplayText(),
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              ),
            ),
            const Icon(Icons.arrow_drop_down,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
