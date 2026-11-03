import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/pomodoro_state.dart';
import '../../providers/app_state_provider.dart';
import '../../services/music_player_service.dart';
import '../shared/searchable_task_input.dart';
import '../shared/unified_project_selector.dart';

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
    final active = provider.activeTaskLog;
    if (active != null && active.id != _syncedTaskId) {
      _syncedTaskId = active.id;
      _titleController.text = active.isUntitledDraft ? '' : active.title;
      _selectedMacroId = active.macroProjectId;
      _selectedSubId = active.subProjectId;
      _selectedTagIds
        ..clear()
        ..addAll(active.tagIds);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppStateProvider, MusicPlayerService>(
      builder: (context, provider, music, _) {
        final tags = provider.phaseTags;
        final isTimerActive =
            provider.pomodoroState.status == TimerStatus.running ||
                provider.pomodoroState.status == TimerStatus.overtime;

        return Container(
          width: 300,
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
              // فیلد عنوان اقدام با قابلیت ادامه کارهای باز (Resume)
              SearchableTaskInput(
                controller: _titleController,
                openTasks: provider.openWorkTasks,
                onResumeTask: (task) async {
                  await provider.resumeOpenTask(task);
                  await provider.toggleQuickMenuExpanded(false);
                },
              ),
              const SizedBox(height: 8),

              // انتخابگر تک‌فیلدی درختی پروژه
              UnifiedProjectSelector(
                projects: provider.projects,
                selectedMacroId: _selectedMacroId,
                selectedSubId: _selectedSubId,
                onSelected: (macroId, subId) {
                  setState(() {
                    _selectedMacroId = macroId;
                    _selectedSubId = subId;
                  });
                },
              ),
              const SizedBox(height: 8),

              // تگ‌های فاز کاری
              SizedBox(
                height: 26,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tags.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    final tag = tags[index];
                    final isSelected = _selectedTagIds.contains(tag.id);
                    return FilterChip(
                      label: Text(tag.name,
                          style: const TextStyle(fontSize: 10.5)),
                      selected: isSelected,
                      selectedColor: AppColors.focus,
                      backgroundColor: AppColors.background,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
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
                  },
                ),
              ),
              const SizedBox(height: 10),

              // مینی‌پلیر موسیقی تمرکز
              if (music.tracks.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          music.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 16,
                          color: AppColors.focus,
                        ),
                        onPressed: music.togglePlayPause,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          music.currentTrack?.title ?? 'موسیقی تمرکز',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded,
                            size: 16, color: AppColors.textSecondary),
                        onPressed: music.nextTrack,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // دکمه‌های ثبت و تعویض تسک
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.focus,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        provider.activeTaskLog != null
                            ? 'ثبت تسک جاری'
                            : 'شروع فوری',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold),
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
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.breakTime,
                        side: const BorderSide(color: AppColors.breakTime),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                      ),
                      icon: const Icon(Icons.skip_next_rounded, size: 15),
                      label: const Text('تسک بعدی',
                          style: TextStyle(fontSize: 11)),
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
