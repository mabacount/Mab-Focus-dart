import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/task_log_entry.dart';

class SearchableTaskInput extends StatefulWidget {
  final TextEditingController controller;
  final List<TaskLogEntry> openTasks;
  final void Function(TaskLogEntry task)? onResumeTask;
  final VoidCallback? onSubmitted;
  final bool isDense;

  const SearchableTaskInput({
    super.key,
    required this.controller,
    required this.openTasks,
    this.onResumeTask,
    this.onSubmitted,
    this.isDense = true,
  });

  @override
  State<SearchableTaskInput> createState() => _SearchableTaskInputState();
}

class _SearchableTaskInputState extends State<SearchableTaskInput> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    // گروه‌بندی کارهای باز بر اساس groupId برای جلوگیری از تکرار عنوان
    final Map<String, TaskLogEntry> uniqueOpenTasks = {};
    for (final task in widget.openTasks) {
      uniqueOpenTasks.putIfAbsent(task.groupId, () => task);
    }
    final openList = uniqueOpenTasks.values.toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onFocusChange: (focus) => setState(() => _isFocused = focus),
          child: TextField(
            controller: widget.controller,
            style:
                const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'در حال انجام چه کاری هستید؟',
              hintStyle:
                  const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              isDense: widget.isDense,
              filled: true,
              fillColor: AppColors.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              prefixIcon: const Icon(Icons.edit_note_rounded,
                  size: 18, color: AppColors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
            onSubmitted: (_) => widget.onSubmitted?.call(),
          ),
        ),
        if (_isFocused && openList.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.breakTime.withAlpha(80)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: openList.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 6, color: AppColors.border),
              itemBuilder: (context, index) {
                final task = openList[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    widget.controller.text = task.title;
                    widget.onResumeTask?.call(task);
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.breakTime.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ادامه کار باز',
                            style: TextStyle(
                                fontSize: 9.5,
                                color: AppColors.breakTime,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.textPrimary),
                          ),
                        ),
                        const Icon(Icons.play_circle_outline_rounded,
                            size: 16, color: AppColors.breakTime),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
