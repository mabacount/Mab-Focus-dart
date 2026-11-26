import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/session_note.dart';
import '../../providers/app_state_provider.dart';
import 'unified_project_selector.dart';

class EditSessionNoteDialog extends StatefulWidget {
  final SessionNote note;

  const EditSessionNoteDialog({super.key, required this.note});

  static Future<void> show(BuildContext context, SessionNote note) {
    return showDialog<void>(
      context: context,
      builder: (_) => EditSessionNoteDialog(note: note),
    );
  }

  @override
  State<EditSessionNoteDialog> createState() => _EditSessionNoteDialogState();
}

class _EditSessionNoteDialogState extends State<EditSessionNoteDialog> {
  late TextEditingController _contentController;
  late SessionNoteType _noteType;
  String? _selectedProjectId;
  String? _selectedOutcomeId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.note.content);
    _noteType = widget.note.noteType;
    _selectedProjectId = widget.note.projectId;
    _selectedOutcomeId = widget.note.outcomeId;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Color _parseHex(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _handleSave(AppStateProvider provider) async {
    final text = _contentController.text.trim();
    if (text.isEmpty && widget.note.imagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً متن یادداشت را وارد کنید.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final selectedProj = provider.getProjectById(_selectedProjectId);
      final noteRealm = selectedProj?.realm ?? widget.note.realm;

      final updated = widget.note.copyWith(
        realm: noteRealm,
        noteType: _noteType,
        projectId: _selectedProjectId,
        clearProjectId: _selectedProjectId == null,
        outcomeId: _selectedOutcomeId,
        clearOutcomeId: _selectedOutcomeId == null,
        content: text,
      );

      await provider.updateSessionNote(updated);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('یادداشت با موفقیت ویرایش و منتقل شد.'),
            backgroundColor: AppColors.lifeGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final palette = provider.activePalette;

    final availableOutcomes = _selectedProjectId != null
        ? provider.outcomes.where((o) => o.projectId == _selectedProjectId).toList()
        : provider.outcomes;

    final selectedProject = provider.getProjectById(_selectedProjectId);
    final projectColor = _parseHex(selectedProject?.colorHex, palette.accent);

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      title: Row(
        children: [
          Icon(Icons.drive_file_move_rounded, color: palette.accent, size: 22),
          const SizedBox(width: 8),
          const Text(
            'ویرایش و انتقال یادداشت',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
              // ۱. انتخاب پروژه مقصد
              const Text(
                'پروژه مقصد:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              UnifiedProjectSelector(
                projects: provider.projects,
                selectedProjectId: _selectedProjectId,
                emptyLabel: 'بدون پروژه (عمومی)',
                accentColor: projectColor,
                onSelected: (pid) {
                  setState(() {
                    _selectedProjectId = pid;
                    if (_selectedOutcomeId != null) {
                      final currOut = provider.getOutcomeById(_selectedOutcomeId!);
                      if (currOut != null && currOut.projectId != pid) {
                        _selectedOutcomeId = null;
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 12),

              // ۲. انتخاب کار / هدف متصل
              const Text(
                'کار / هدف متصل:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: availableOutcomes.any((o) => o.id == _selectedOutcomeId)
                        ? _selectedOutcomeId
                        : null,
                    isExpanded: true,
                    dropdownColor: palette.surface,
                    hint: const Text('بدون کار مشخص (یادداشت عمومی)', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('بدون کار مشخص (یادداشت عمومی)', style: TextStyle(fontSize: 12)),
                      ),
                      ...availableOutcomes.map((o) => DropdownMenuItem<String?>(
                        value: o.id,
                        child: Text(
                          o.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      )),
                    ],
                    onChanged: (newOid) {
                      setState(() {
                        _selectedOutcomeId = newOid;
                        if (newOid != null) {
                          final out = provider.getOutcomeById(newOid);
                          if (out != null && out.projectId != null) {
                            _selectedProjectId = out.projectId;
                          }
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ۳. دسته‌بندی نوع یادداشت
              const Text(
                'نوع یادداشت:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: SessionNoteType.values.map((t) {
                  final isSelected = _noteType == t;
                  return ChoiceChip(
                    avatar: Icon(t.icon, size: 14, color: isSelected ? Colors.white : t.color),
                    label: Text(t.labelFa,
                        style: TextStyle(
                            fontSize: 11,
                            color: isSelected ? Colors.white : AppColors.textPrimary)),
                    selected: isSelected,
                    selectedColor: t.color,
                    backgroundColor: AppColors.surfaceElevated,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _noteType = t),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // ۴. متن یادداشت
              const Text(
                'متن یادداشت:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _contentController,
                maxLines: 5,
                minLines: 3,
                style: const TextStyle(fontSize: 13, height: 1.5),
                decoration: const InputDecoration(
                  hintText: 'متن یادداشت را اینجا بنویسید...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: palette.accent),
          icon: const Icon(Icons.save_rounded, size: 16),
          label: const Text('ذخیره و انتقال'),
          onPressed: _isSaving ? null : () => _handleSave(provider),
        ),
      ],
    );
  }
}
