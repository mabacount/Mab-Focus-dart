import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/outcome_item.dart';
import '../../models/project_node.dart';
import '../../models/time_record.dart';

/// فیلد جستجو و ایجاد زنده برای کارها/اهداف (باز، تکمیل‌شده قبلی و سوابق تاریخی)
class SearchableTaskInput extends StatefulWidget {
  final TextEditingController controller;
  final List<OutcomeItem> openOutcomes;
  final List<OutcomeItem> completedOutcomes;
  final List<TimeRecord> historicalRecords;
  final List<ProjectNode> projects;
  final void Function(OutcomeItem outcome)? onSelectOutcome;
  final void Function(TimeRecord record)? onSelectHistoricalRecord;
  final void Function(String title)? onCreateNew;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Color accentColor;
  final String hintText;
  final bool isDense;

  const SearchableTaskInput({
    super.key,
    required this.controller,
    required this.openOutcomes,
    this.completedOutcomes = const [],
    this.historicalRecords = const [],
    this.projects = const [],
    this.onSelectOutcome,
    this.onSelectHistoricalRecord,
    this.onCreateNew,
    this.onSubmitted,
    this.onChanged,
    this.accentColor = AppColors.workBlue,
    this.hintText = 'جست‌وجوی کار باز یا تایپ فعالیت جدید...',
    this.isDense = true,
  });

  @override
  State<SearchableTaskInput> createState() => _SearchableTaskInputState();
}

class _SearchableTaskInputState extends State<SearchableTaskInput> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.controller.text.trim().toLowerCase();
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final next = widget.controller.text.trim().toLowerCase();
    if (next != _query && mounted) {
      setState(() => _query = next);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  Color _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return widget.accentColor;
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return widget.accentColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    // کارهای باز (isCompleted == false)
    final openList = widget.openOutcomes.where((o) {
      if (o.isCompleted) return false;
      if (_query.isEmpty) return true;
      return o.title.toLowerCase().contains(_query);
    }).toList();

    // کارهای تکمیل‌شده قبلی (برای انتخاب مجدد و بازگشایی)
    final completedList = widget.completedOutcomes.where((o) {
      if (!o.isCompleted) return false;
      if (_query.isEmpty) return true;
      return o.title.toLowerCase().contains(_query);
    }).toList();

    // سوابق تاریخی بدون Outcome (فقط رکوردهای دارای عنوان واقعی و بدون تکرار)
    final Set<String> knownTitles = {
      for (final o in widget.openOutcomes) o.title.trim().toLowerCase(),
      for (final o in widget.completedOutcomes) o.title.trim().toLowerCase(),
    };
    final List<TimeRecord> historicalList = [];
    final Set<String> seenHistorical = {};
    for (final r in widget.historicalRecords) {
      if (r.isUntitledDraft) continue;
      final t = r.titleSnapshot.trim();
      final lower = t.toLowerCase();
      if (t.isEmpty || t == AppDefaults.untitledTaskTitle) continue;
      if (knownTitles.contains(lower) || seenHistorical.contains(lower)) {
        continue;
      }
      if (_query.isNotEmpty && !lower.contains(_query)) continue;
      seenHistorical.add(lower);
      historicalList.add(r);
    }

    final rawText = widget.controller.text.trim();
    final bool hasExactMatch = widget.openOutcomes
        .any((o) => !o.isCompleted && o.title.trim().toLowerCase() == _query);
    final bool showCreateRow = widget.onCreateNew != null &&
        rawText.isNotEmpty &&
        rawText != AppDefaults.untitledTaskTitle &&
        !hasExactMatch;

    final Map<String, ProjectNode> projMap = {
      for (final p in widget.projects) p.id: p
    };

    final bool showDropdown = _isFocused &&
        (openList.isNotEmpty ||
            completedList.isNotEmpty ||
            historicalList.isNotEmpty ||
            showCreateRow);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onFocusChange: (focus) => setState(() => _isFocused = focus),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            style:
                const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle:
                  const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              isDense: widget.isDense,
              filled: true,
              fillColor: AppColors.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              prefixIcon: Icon(Icons.search_rounded,
                  size: 18, color: widget.accentColor),
              suffixIcon: rawText.isNotEmpty && widget.onCreateNew != null
                  ? IconButton(
                      tooltip: 'ایجاد و شروع «$rawText»',
                      icon: Icon(Icons.add_circle_outline_rounded,
                          size: 18, color: widget.accentColor),
                      onPressed: () {
                        _focusNode.unfocus();
                        widget.onCreateNew!(rawText);
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.accentColor, width: 1.2),
              ),
            ),
            onChanged: widget.onChanged,
            onSubmitted: (_) {
              _focusNode.unfocus();
              if (widget.onSubmitted != null) {
                widget.onSubmitted!();
              } else if (showCreateRow) {
                widget.onCreateNew!(rawText);
              }
            },
          ),
        ),
        if (showDropdown) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 170),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.accentColor.withAlpha(110)),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (showCreateRow)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      _focusNode.unfocus();
                      widget.onCreateNew!(rawText);
                    },
                    child: Container(
                      margin: EdgeInsets.only(bottom: openList.isNotEmpty ? 4 : 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.add_task_rounded,
                              size: 15, color: widget.accentColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'ایجاد و شروع «$rawText»',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: widget.accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ...openList.map((outcome) {
                  final proj = outcome.projectId != null
                      ? projMap[outcome.projectId]
                      : null;
                  final projColor = _parseHex(proj?.colorHex);
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      widget.controller.text = outcome.title;
                      _focusNode.unfocus();
                      widget.onSelectOutcome?.call(outcome);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 5),
                      child: Row(
                        children: [
                          Icon(Icons.radio_button_unchecked_rounded,
                              size: 14, color: widget.accentColor),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              outcome.title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (proj != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: projColor.withAlpha(32),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                proj.name,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: projColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          Icon(Icons.play_arrow_rounded,
                              size: 16, color: widget.accentColor),
                        ],
                      ),
                    ),
                  );
                }),
                ...completedList.map((outcome) {
                  final proj = outcome.projectId != null
                      ? projMap[outcome.projectId]
                      : null;
                  final projColor = _parseHex(proj?.colorHex);
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      widget.controller.text = outcome.title;
                      _focusNode.unfocus();
                      widget.onSelectOutcome?.call(outcome);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 5),
                      child: Row(
                        children: [
                          const Icon(Icons.replay_rounded,
                              size: 14, color: AppColors.lifeGreen),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              outcome.title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (proj != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: projColor.withAlpha(32),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                proj.name,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: projColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          Icon(Icons.play_arrow_rounded,
                              size: 16, color: widget.accentColor),
                        ],
                      ),
                    ),
                  );
                }),
                ...historicalList.map((rec) {
                  final proj =
                      rec.projectId != null ? projMap[rec.projectId] : null;
                  final projColor = _parseHex(proj?.colorHex);
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      widget.controller.text = rec.titleSnapshot;
                      _focusNode.unfocus();
                      widget.onSelectHistoricalRecord?.call(rec);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 5),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              rec.titleSnapshot,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (proj != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: projColor.withAlpha(32),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                proj.name,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: projColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          Icon(Icons.play_arrow_rounded,
                              size: 16, color: widget.accentColor),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
