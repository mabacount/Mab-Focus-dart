import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/project_node.dart';

class UnifiedProjectSelector extends StatefulWidget {
  final List<ProjectNode> projects;
  final String? selectedMacroId;
  final String? selectedSubId;
  final void Function(String? macroId, String? subId) onSelected;
  final bool isDense;

  const UnifiedProjectSelector({
    super.key,
    required this.projects,
    this.selectedMacroId,
    this.selectedSubId,
    required this.onSelected,
    this.isDense = true,
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
      return AppColors.focus;
    }
  }

  String _getDisplayText() {
    if (widget.selectedSubId != null) {
      final sub = widget.projects.firstWhere(
        (p) => p.id == widget.selectedSubId,
        orElse: () => const ProjectNode(id: '', name: '-'),
      );
      final macro = widget.projects.firstWhere(
        (p) => p.id == widget.selectedMacroId,
        orElse: () => const ProjectNode(id: '', name: '-'),
      );
      return '${macro.name} > ${sub.name}';
    } else if (widget.selectedMacroId != null) {
      final macro = widget.projects.firstWhere(
        (p) => p.id == widget.selectedMacroId,
        orElse: () => const ProjectNode(id: '', name: '-'),
      );
      return macro.name;
    }
    return 'بدون پروژه (عمومی)';
  }

  Color _getSelectedColor() {
    if (widget.selectedMacroId != null) {
      final macro = widget.projects.firstWhere(
        (p) => p.id == widget.selectedMacroId,
        orElse: () => const ProjectNode(id: '', name: ''),
      );
      return _parseHex(macro.colorHex);
    }
    return AppColors.textMuted;
  }

  void _openSelectionDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final macros = widget.projects
                .where((p) => p.isMacro && !p.isArchived)
                .toList();

            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text('انتخاب پروژه هدف',
                  style: TextStyle(fontSize: 15)),
              content: SizedBox(
                width: 380,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'جست‌وجوی پروژه یا زیرمجموعه...',
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
                            title: const Text('بدون پروژه (عمومی)',
                                style: TextStyle(fontSize: 13)),
                            selected: widget.selectedMacroId == null &&
                                widget.selectedSubId == null,
                            onTap: () {
                              widget.onSelected(null, null);
                              Navigator.of(ctx).pop();
                            },
                          ),
                          const Divider(height: 1, color: AppColors.border),
                          ...macros.expand((macro) {
                            final subs = widget.projects
                                .where((p) =>
                                    p.parentId == macro.id && !p.isArchived)
                                .toList();

                            final bool macroMatches =
                                macro.name.toLowerCase().contains(searchQuery);
                            final matchingSubs = subs
                                .where((s) =>
                                    s.name.toLowerCase().contains(searchQuery))
                                .toList();

                            if (searchQuery.isNotEmpty &&
                                !macroMatches &&
                                matchingSubs.isEmpty) {
                              return <Widget>[];
                            }

                            final macroColor = _parseHex(macro.colorHex);

                            return [
                              ListTile(
                                dense: true,
                                leading: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                      color: macroColor,
                                      shape: BoxShape.circle),
                                ),
                                title: Text(
                                  macro.name,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                ),
                                selected: widget.selectedMacroId == macro.id &&
                                    widget.selectedSubId == null,
                                onTap: () {
                                  widget.onSelected(macro.id, null);
                                  Navigator.of(ctx).pop();
                                },
                              ),
                              ...(searchQuery.isNotEmpty ? matchingSubs : subs)
                                  .map(
                                (sub) => Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                      start: 24),
                                  child: ListTile(
                                    dense: true,
                                    leading: const Text('↳',
                                        style: TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 14)),
                                    title: Text(sub.name,
                                        style: const TextStyle(fontSize: 12.5)),
                                    selected: widget.selectedSubId == sub.id,
                                    onTap: () {
                                      widget.onSelected(macro.id, sub.id);
                                      Navigator.of(ctx).pop();
                                    },
                                  ),
                                ),
                              ),
                            ];
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
