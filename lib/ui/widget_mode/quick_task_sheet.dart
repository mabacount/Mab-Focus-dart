import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/outcome_item.dart';
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
  String? _selectedProjectId;
  String? _selectedOutcomeId;
  final Set<String> _selectedTagIds = {};
  String? _syncedRecordId;
  AppRealm? _syncedRealm;

  void _syncFromProvider(AppStateProvider provider) {
    final active = provider.activeRecord;
    final activeRealm = active?.realm ?? provider.pomodoroState.realm;
    if (active != null &&
        (active.id != _syncedRecordId || activeRealm != _syncedRealm)) {
      _syncedRecordId = active.id;
      _syncedRealm = activeRealm;
      _titleController.text =
          active.isUntitledDraft ? '' : active.titleSnapshot;
      _selectedOutcomeId = active.outcomeId;
      _selectedProjectId = active.projectId;
      _selectedTagIds
        ..clear()
        ..addAll(active.tagIds);
    } else if (active == null && _syncedRecordId != null) {
      _syncedRecordId = null;
      _syncedRealm = activeRealm;
      _titleController.clear();
      _selectedOutcomeId = null;
      _selectedProjectId = null;
      _selectedTagIds.clear();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFromProvider(context.read<AppStateProvider>());
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Color _parseHex(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.workBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppStateProvider, MusicPlayerService>(
      builder: (context, provider, music, _) {
        _syncFromProvider(provider);

        final state = provider.pomodoroState;
        final active = provider.activeRecord;
        final activeRealm = active?.realm ?? state.realm;
        final realmColor = activeRealm == AppRealm.life
            ? AppColors.lifeGreen
            : AppColors.workBlue;

        final tags = provider.phaseTags;
        final openOutcomes = provider.getOpenOutcomes(realm: activeRealm);
        final activeOutcome = provider.activeOutcome;
        final bool isTimerActive = state.status == TimerStatus.running ||
            state.status == TimerStatus.overtime;

        final int cycleMin = state.cycleWorkSeconds ~/ 60;
        final int targetMin = state.cycleWorkTargetSeconds ~/ 60;
        final int earnedMin = state.earnedShortBreakSeconds ~/ 60;
        final int debtMin = state.breakDebtSeconds ~/ 60;

        return Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: realmColor.withAlpha(110), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ۱. نوار وضعیت قلمرو، بانک استراحت Flowmodoro و دکمه‌های Swap / Reset Cycle
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: realmColor.withAlpha(70)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: realmColor.withAlpha(35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'قلمرو ${activeRealm.labelFa}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: realmColor,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Tooltip(
                            message:
                                'تغییر ماهیت رکورد جاری (کار ↔ زندگی) از لحظه شروع',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () async {
                                await provider.swapCurrentSliceRealm();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.edited.withAlpha(30),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: AppColors.edited.withAlpha(100)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.swap_horiz_rounded,
                                        size: 13, color: AppColors.edited),
                                    SizedBox(width: 3),
                                    Text(
                                      'تبدیل آنی',
                                      style: TextStyle(
                                          fontSize: 9.5,
                                          color: AppColors.edited,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'ریست دستی چرخه ۱۰۰ دقیقه‌ای Flowmodoro',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => provider.resetFlowmodoroCycle(),
                              child: Container(
                                padding: const EdgeInsets.all(3.5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.restart_alt_rounded,
                                    size: 14, color: AppColors.textSecondary),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            'چرخه: $cycleMin/$targetMinد',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5, color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'استراحت ذخیره: +$earnedMinد',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5, color: AppColors.lifeGreen),
                          ),
                          if (debtMin > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              'بدهی: -$debtMinد',
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5, color: AppColors.overtime),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: state.cycleProgress,
                          minHeight: 3.5,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(realmColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ۲. جستجوی زنده فقط روی کارهای بازِ قلمرو فعال + ایجاد آنی
                SearchableTaskInput(
                  controller: _titleController,
                  openOutcomes: openOutcomes,
                  projects: provider.projects,
                  accentColor: realmColor,
                  hintText: activeRealm == AppRealm.life
                      ? 'جست‌وجوی کار زندگی (مثلاً خواب، ورزش) یا تایپ جدید...'
                      : 'جست‌وجوی کار باز یا تایپ عنوان جدید...',
                  onChanged: (text) {
                    if (_selectedOutcomeId != null) {
                      final matched = provider.getOutcomeById(_selectedOutcomeId!);
                      if (matched != null && matched.title != text.trim()) {
                        setState(() => _selectedOutcomeId = null);
                      }
                    }
                  },
                  onSelectOutcome: (OutcomeItem outcome) async {
                    setState(() {
                      _selectedOutcomeId = outcome.id;
                      _selectedProjectId = outcome.projectId;
                    });
                    await provider.startOrSwitchToOutcome(
                      outcome,
                      tagIds: _selectedTagIds.toList(),
                    );
                    await provider.toggleQuickMenuExpanded(false);
                  },
                  onCreateNew: (newTitle) async {
                    await provider.createAndStartOutcome(
                      realm: activeRealm,
                      title: newTitle,
                      projectId: _selectedProjectId,
                      tagIds: _selectedTagIds.toList(),
                      attachToCurrentRecordIfUntitled:
                          active != null && active.isUntitledDraft,
                    );
                    await provider.toggleQuickMenuExpanded(false);
                  },
                ),

                // چک‌باکس تکمیل سریع کار در حال اجرا (Complete Active Outcome)
                if (activeOutcome != null) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      if (activeOutcome.isCompleted) {
                        await provider.reopenOutcome(activeOutcome.id);
                      } else {
                        await provider.markOutcomeCompleted(activeOutcome.id);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: activeOutcome.isCompleted
                            ? AppColors.lifeGreen.withAlpha(28)
                            : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: activeOutcome.isCompleted
                              ? AppColors.lifeGreen.withAlpha(110)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            activeOutcome.isCompleted
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 16,
                            color: activeOutcome.isCompleted
                                ? AppColors.lifeGreen
                                : realmColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              activeOutcome.isCompleted
                                  ? 'تکمیل و بایگانی شد: ${activeOutcome.title}'
                                  : 'تیک تکمیل کار فعلی (بایگانی پس از انجام)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: activeOutcome.isCompleted
                                    ? AppColors.lifeGreen
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // ۳. انتخابگر درختی پروژه (محدود به پروژه‌های قلمرو فعال)
                UnifiedProjectSelector(
                  projects: provider.projects,
                  realmFilter: activeRealm,
                  selectedProjectId: _selectedProjectId,
                  accentColor: realmColor,
                  onSelected: (projectId) {
                    setState(() => _selectedProjectId = projectId);
                  },
                ),
                const SizedBox(height: 8),

                // ۴. تگ‌های فاز کاری
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
                        label: Text(tag.name,
                            style: const TextStyle(fontSize: 10)),
                        selected: isSelected,
                        selectedColor: realmColor,
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

                // ۵. لیست سریع کارهای بازِ قلمرو فعال با چک‌باکس تکمیل فوری
                if (openOutcomes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'کارهای بازِ ${activeRealm.labelFa} (${openOutcomes.length})',
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary),
                      ),
                      const Text(
                        'کلیک برای شروع / تیک برای انجام',
                        style:
                            TextStyle(fontSize: 9.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 112),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: openOutcomes.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (ctx, i) {
                        final item = openOutcomes[i];
                        final isCurrent = item.id == active?.outcomeId;
                        final proj = provider.getProjectById(item.projectId);
                        return InkWell(
                          onTap: () async {
                            await provider.startOrSwitchToOutcome(
                              item,
                              tagIds: _selectedTagIds.toList(),
                            );
                            await provider.toggleQuickMenuExpanded(false);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Row(
                              children: [
                                InkWell(
                                  onTap: () => provider
                                      .markOutcomeCompleted(item.id),
                                  child: Icon(
                                    Icons.check_box_outline_blank_rounded,
                                    size: 16,
                                    color: realmColor,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    item.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isCurrent
                                          ? realmColor
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (proj != null) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _parseHex(proj.colorHex),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 4),
                                Icon(
                                  isCurrent
                                      ? Icons.graphic_eq_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 14,
                                  color: realmColor,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // ۶. مینی‌پلیر موسیقی
                if (music.tracks.isNotEmpty) ...[
                  const SizedBox(height: 8),
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
                            color: realmColor,
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
                ],
                const SizedBox(height: 10),

                // ۷. دکمه‌های ثبت روی رکورد جاری یا شروع فعالیت بعدی
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: realmColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: Text(
                          active != null
                              ? 'ثبت روی رکورد جاری'
                              : 'شروع فوری',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          if (active != null) {
                            await provider.updateActiveRecordMetadata(
                              title: _titleController.text,
                              outcomeId: _selectedOutcomeId,
                              clearOutcomeId: _selectedOutcomeId == null,
                              projectId: _selectedProjectId,
                              clearProjectId: _selectedProjectId == null,
                              tagIds: _selectedTagIds.toList(),
                            );
                          } else {
                            final rawTitle = _titleController.text.trim();
                            if (rawTitle.isNotEmpty) {
                              await provider.createAndStartOutcome(
                                realm: activeRealm,
                                title: rawTitle,
                                projectId: _selectedProjectId,
                                tagIds: _selectedTagIds.toList(),
                              );
                            } else {
                              await provider.switchRealm(
                                activeRealm,
                                projectId: _selectedProjectId,
                                tagIds: _selectedTagIds.toList(),
                              );
                            }
                          }
                          await provider.toggleQuickMenuExpanded(false);
                        },
                      ),
                    ),
                    if (isTimerActive && active != null) ...[
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.lifeGreen,
                          side: const BorderSide(color: AppColors.lifeGreen),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                        ),
                        icon: const Icon(Icons.skip_next_rounded, size: 15),
                        label: const Text('برش بعدی',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () async {
                          final selectedOutcome = _selectedOutcomeId != null
                              ? provider.getOutcomeById(_selectedOutcomeId!)
                              : null;
                          await provider.switchRecordMidSession(
                            newTitle: _titleController.text,
                            projectId: _selectedProjectId,
                            outcome: selectedOutcome,
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
          ),
        );
      },
    );
  }
}
