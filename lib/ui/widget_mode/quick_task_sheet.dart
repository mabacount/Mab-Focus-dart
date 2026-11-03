// منوی بازشونده شروع فوری تسک و تعویض تسک در میانه پومودورو
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/pomodoro_state.dart';
import '../../providers/app_state_provider.dart';

class QuickTaskSheet extends StatefulWidget {
  const QuickTaskSheet({super.key});

  @override
  State<QuickTaskSheet> createState() => _QuickTaskSheetState();
}

class _QuickTaskSheetState extends State<QuickTaskSheet> {
  final TextEditingController _titleController = TextEditingController();
  String? _selectedMacroId;
  String? _selectedSubId;
  final Set<String> _selectedTagIds = {};
  String? _syncedTaskId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AppStateProvider>();
    final activeTask = provider.activeTaskLog;
    if (activeTask != null && activeTask.id != _syncedTaskId) {
      _syncedTaskId = activeTask.id;
      _titleController.text =
          activeTask.isUntitledDraft ? '' : activeTask.title;
      _selectedMacroId = activeTask.macroProjectId;
      _selectedSubId = activeTask.subProjectId;
      _selectedTagIds
        ..clear()
        ..addAll(activeTask.tagIds);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final macroProjects = provider.macroProjects;
        final subProjects = provider.getSubProjects(_selectedMacroId);
        final tags = provider.phaseTags;
        final isTimerActive =
            provider.pomodoroState.status == TimerStatus.running ||
                provider.pomodoroState.status == TimerStatus.overtime;

        return Container(
          width: 304,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // فیلد عنوان تسک
              TextField(
                controller: _titleController,
                autofocus: true,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'در حال انجام چه کاری هستید؟ (اختیاری)',
                  hintStyle: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // انتخابگر دو مرحله‌ای پروژه کلان و زیرپروژه
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value:
                              macroProjects.any((p) => p.id == _selectedMacroId)
                                  ? _selectedMacroId
                                  : null,
                          isExpanded: true,
                          isDense: true,
                          hint: const Text(
                            'پروژه کلان',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.textPrimary),
                          dropdownColor: AppColors.surfaceElevated,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('بدون پروژه کلان'),
                            ),
                            ...macroProjects.map(
                              (proj) => DropdownMenuItem<String?>(
                                value: proj.id,
                                child: Text(proj.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedMacroId = val;
                              _selectedSubId = null;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: subProjects.any((p) => p.id == _selectedSubId)
                              ? _selectedSubId
                              : null,
                          isExpanded: true,
                          isDense: true,
                          hint: const Text(
                            'زیرپروژه',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.textPrimary),
                          dropdownColor: AppColors.surfaceElevated,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('بدون زیرپروژه'),
                            ),
                            ...subProjects.map(
                              (sub) => DropdownMenuItem<String?>(
                                value: sub.id,
                                child: Text(sub.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedSubId = val;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // تگ‌های فاز کاری
              SizedBox(
                height: 28,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tags.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    final tag = tags[index];
                    final isSelected = _selectedTagIds.contains(tag.id);
                    return FilterChip(
                      label: Text(
                        tag.name,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppColors.focus,
                      backgroundColor: AppColors.background,
                      checkmarkColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedTagIds.add(tag.id);
                          } else {
                            _selectedTagIds.remove(tag.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),

              // دکمه‌های ثبت یا تعویض تسک در میانه پومودورو
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.focus,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        textStyle: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        provider.activeTaskLog != null
                            ? 'ثبت مشخصات تسک جاری'
                            : 'شروع فوری تسک',
                      ),
                      onPressed: () async {
                        if (provider.activeTaskLog != null) {
                          await provider.updateActiveTaskMetadata(
                            title: _titleController.text,
                            macroProjectId: _selectedMacroId,
                            subProjectId: _selectedSubId,
                            tagIds: _selectedTagIds.toList(),
                          );
                        } else {
                          await provider.startInstantWork(
                            title: _titleController.text,
                            macroProjectId: _selectedMacroId,
                            subProjectId: _selectedSubId,
                            tagIds: _selectedTagIds.toList(),
                          );
                        }
                        await provider.toggleQuickMenuExpanded(false);
                      },
                    ),
                  ),
                  if (isTimerActive && provider.activeTaskLog != null) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message:
                          'بستن تسک فعلی و شروع تسک جدید بدون ریست شدن پومودورو',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.breakTime,
                          side: const BorderSide(color: AppColors.breakTime),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          textStyle: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        icon: const Icon(Icons.skip_next_rounded, size: 15),
                        label: const Text('تسک بعدی'),
                        onPressed: () async {
                          await provider.switchTaskMidPomodoro(
                            newTitle: _titleController.text,
                            macroProjectId: _selectedMacroId,
                            subProjectId: _selectedSubId,
                            tagIds: _selectedTagIds.toList(),
                          );
                          _titleController.clear();
                          await provider.toggleQuickMenuExpanded(false);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
