import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
        final completedOutcomes =
            provider.getCompletedOutcomes(realm: activeRealm);
        final historicalRecords = provider.timeRecords
            .where((r) => r.realm == activeRealm && !r.isUntitledDraft)
            .toList();
        final activeOutcome = provider.activeOutcome;

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
                // ۱. نوار وضعیت قلمرو فعال و دکمه تبدیل آنی
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: realmColor.withAlpha(35),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: realmColor.withAlpha(70)),
                      ),
                      child: Text(
                        'قلمرو ${activeRealm.labelFa}',
                        style: TextStyle(
                          fontSize: 11,
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
                              horizontal: 8, vertical: 3),
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
                              SizedBox(width: 4),
                              Text(
                                'تبدیل آنی',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.edited,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ۲. جستجوی زنده روی کارهای باز، تکمیل‌شده قبلی و سوابق تاریخی + ایجاد آنی
                SearchableTaskInput(
                  controller: _titleController,
                  openOutcomes: openOutcomes,
                  completedOutcomes: completedOutcomes,
                  historicalRecords: historicalRecords,
                  projects: provider.projects,
                  accentColor: realmColor,
                  hintText: activeRealm == AppRealm.life
                      ? 'جست‌وجوی کار زندگی (مثلاً خواب، ورزش) یا تایپ جدید...'
                      : 'جست‌وجوی کار باز، قبلی یا تایپ عنوان جدید...',
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
                  onSelectHistoricalRecord: (record) async {
                    setState(() {
                      _selectedOutcomeId = null;
                      _selectedProjectId = record.projectId;
                    });
                    await provider.startOrSwitchToHistoricalRecord(
                      record,
                      tagIds: _selectedTagIds.isEmpty
                          ? record.tagIds
                          : _selectedTagIds.toList(),
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

                // ۵. تنظیمات و مدیریت پوشه‌های موسیقی و پخش تصادفی (جایگزین پنل کارهای باز و بانک استراحت)
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // نوار عنوان تنظیمات موسیقی و دکمه افزودن پوشه
                      Row(
                        children: [
                          Icon(Icons.music_note_rounded,
                              size: 15, color: realmColor),
                          const SizedBox(width: 6),
                          const Text(
                            'تنظیمات موسیقی',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          // نشان وضعیت پخش رندم / تصادفی
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: music.isShuffle
                                  ? AppColors.lifeGreen.withAlpha(35)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: music.isShuffle
                                    ? AppColors.lifeGreen.withAlpha(120)
                                    : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shuffle_rounded,
                                  size: 11,
                                  color: music.isShuffle
                                      ? AppColors.lifeGreen
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  music.isShuffle ? 'پخش تصادفی' : 'پخش عادی',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: music.isShuffle
                                        ? AppColors.lifeGreen
                                        : AppColors.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          // دکمه افزودن پوشه جدید
                          Tooltip(
                            message: 'افزودن پوشه موسیقی از سیستم',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () async {
                                final folder = await FilePicker.platform
                                    .getDirectoryPath();
                                if (folder != null) {
                                  await music.addFolder(folder);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: realmColor.withAlpha(30),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: realmColor.withAlpha(100)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_rounded,
                                        size: 12, color: realmColor),
                                    const SizedBox(width: 2),
                                    Text(
                                      'افزودن پوشه',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: realmColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // انتخاب پوشه فعال
                      if (music.playlists.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.folder_off_outlined,
                                  size: 13, color: AppColors.textMuted),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'هیچ پوشه موسیقی ذخیره نشده است. با دکمه بالا یک پوشه انتخاب کنید.',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            const Text(
                              'پوشه فعال:',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.textSecondary),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Container(
                                height: 28,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: music.activePlaylist?.id,
                                    isExpanded: true,
                                    dropdownColor: AppColors.surfaceElevated,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppColors.textPrimary,
                                    ),
                                    icon: const Icon(Icons.arrow_drop_down,
                                        size: 16,
                                        color: AppColors.textSecondary),
                                    items: music.playlists.map((pl) {
                                      return DropdownMenuItem<String>(
                                        value: pl.id,
                                        child: Text(
                                          pl.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10.5),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (id) {
                                      if (id != null) {
                                        final target = music.playlists
                                            .firstWhere((p) => p.id == id);
                                        music.selectPlaylist(target);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                            if (music.activePlaylist != null) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: 'حذف این پوشه از لیست',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () async {
                                    await music.deletePlaylist(
                                        music.activePlaylist!.id);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 15,
                                      color: AppColors.overtime.withAlpha(180),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),

                      // کنترل‌های پلیر و نمایش نام آهنگ جاری
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded,
                                  size: 15, color: AppColors.textSecondary),
                              onPressed: music.tracks.isNotEmpty
                                  ? music.previousTrack
                                  : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'آهنگ قبلی (تصادفی)',
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                music.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 17,
                                color: realmColor,
                              ),
                              onPressed: music.tracks.isNotEmpty
                                  ? music.togglePlayPause
                                  : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: music.isPlaying ? 'توقف' : 'پخش',
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded,
                                  size: 15, color: AppColors.textSecondary),
                              onPressed: music.tracks.isNotEmpty
                                  ? music.nextTrack
                                  : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'آهنگ بعدی (تصادفی)',
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                music.currentTrack?.title ??
                                    (music.tracks.isEmpty
                                        ? 'بدون آهنگ در این پوشه'
                                        : 'آماده پخش'),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (music.tracks.isNotEmpty)
                              Text(
                                '${music.tracks.length} آهنگ',
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ۷. دکمه‌های ۳‌گانه: انصراف | از قبل تا به حال | از حالا به بعد
                Row(
                  children: [
                    // ۱. انصراف: تغییرات ذخیره نشوند و پنجره بسته شود
                    Tooltip(
                      message: 'بستن منو بدون ذخیره هیچ‌گونه تغییری',
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          _syncedRecordId = null;
                          _syncFromProvider(provider);
                          await provider.toggleQuickMenuExpanded(false);
                        },
                        child: const Text(
                          'انصراف',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),

                    // ۲. از قبل تا به حال: از زمان شروع این رکورد تا به حال به این نام ذخیره شود و ادامه یابد
                    Expanded(
                      child: Tooltip(
                        message:
                            'اعمال این عنوان و مشخصات برای کل رکورد جاری از لحظه شروع تا به حال و ادامه کار',
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: realmColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            visualDensity: VisualDensity.compact,
                            elevation: 0,
                          ),
                          onPressed: () async {
                            final cleanTitle = _titleController.text.trim();
                            if (active != null) {
                              String? effectiveOutcomeId = _selectedOutcomeId;
                              if (effectiveOutcomeId != null) {
                                final out =
                                    provider.getOutcomeById(effectiveOutcomeId);
                                if (out != null &&
                                    cleanTitle.isNotEmpty &&
                                    out.title != cleanTitle) {
                                  effectiveOutcomeId = null;
                                }
                              }
                              await provider.updateActiveRecordMetadata(
                                title: cleanTitle,
                                outcomeId: effectiveOutcomeId,
                                clearOutcomeId: effectiveOutcomeId == null,
                                projectId: _selectedProjectId,
                                clearProjectId: _selectedProjectId == null,
                                tagIds: _selectedTagIds.toList(),
                              );
                            } else {
                              if (cleanTitle.isNotEmpty) {
                                await provider.createAndStartOutcome(
                                  realm: activeRealm,
                                  title: cleanTitle,
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
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'از قبل تا به حال',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),

                    // ۳. از حالا به بعد: رکورد قبلی در این لحظه ذخیره شود و رکورد جدید با این عنوان شروع شود
                    Expanded(
                      child: Tooltip(
                        message:
                            'پایان و ذخیره رکورد قبلی در همین لحظه، و آغاز رکورد تازه از این لحظه به بعد',
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: realmColor.withAlpha(45),
                            foregroundColor: realmColor,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: realmColor.withAlpha(120),
                                width: 1.0,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            final cleanTitle = _titleController.text.trim();
                            if (active != null) {
                              OutcomeItem? targetOutcome;
                              if (_selectedOutcomeId != null) {
                                final out =
                                    provider.getOutcomeById(_selectedOutcomeId!);
                                if (out != null &&
                                    (cleanTitle.isEmpty ||
                                        out.title == cleanTitle)) {
                                  targetOutcome = out;
                                }
                              }
                              await provider.switchRecordMidSession(
                                newTitle: cleanTitle,
                                projectId: _selectedProjectId,
                                outcome: targetOutcome,
                                tagIds: _selectedTagIds.toList(),
                              );
                              _titleController.clear();
                            } else {
                              if (cleanTitle.isNotEmpty) {
                                await provider.createAndStartOutcome(
                                  realm: activeRealm,
                                  title: cleanTitle,
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
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'از حالا به بعد',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (state.status == TimerStatus.running ||
                        state.status == TimerStatus.overtime) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'توقف کامل تایمر (نه کار و نه زندگی)',
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            await provider.stopTimer();
                            await provider.toggleQuickMenuExpanded(false);
                          },
                          child: const Icon(Icons.stop_rounded, size: 16),
                        ),
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
