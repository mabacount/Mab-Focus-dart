import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/platform_helper.dart';
import '../../models/pomodoro_state.dart';
import '../../providers/app_state_provider.dart';
import '../../services/music_player_service.dart';
import 'activity_log_tab.dart';
import 'calendar_grid_tab.dart';
import 'capacity_thieves_tab.dart';
import 'open_outcomes_tab.dart';
import 'project_studio_tab.dart';
import 'settings_tab.dart';
import 'untitled_inbox_tab.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _tabs = const [
    CalendarGridTab(),
    OpenOutcomesTab(),
    ActivityLogTab(),
    ProjectStudioTab(),
    CapacityThievesTab(),
    UntitledInboxTab(),
    SettingsTab(),
  ];

  void _openMobileMoreSheet(
    BuildContext context,
    AppStateProvider provider,
    int untitledCount,
  ) {
    final palette = provider.activePalette;
    final realm = provider.dashboardRealm;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'بخش‌های تکمیلی (${realm.labelFa})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DashboardRealmToggle(
                    activeRealm: realm,
                    compact: true,
                    onChanged: (r) => provider.setDashboardRealm(r),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.account_tree_rounded, color: palette.accent),
                title: Text(realm == AppRealm.life
                    ? 'استودیوی پروژه‌های زندگی'
                    : 'استودیوی پروژه‌های کار'),
                selected: _selectedIndex == 3,
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _selectedIndex = 3);
                },
              ),
              ListTile(
                leading: Icon(Icons.pie_chart_rounded, color: palette.accent),
                title: const Text('سند ظرفیت و سارقان زمان'),
                selected: _selectedIndex == 4,
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _selectedIndex = 4);
                },
              ),
              ListTile(
                leading: Badge(
                  isLabelVisible: untitledCount > 0,
                  backgroundColor: AppColors.draftWarning,
                  label: Text('$untitledCount'),
                  child: const Icon(Icons.inbox_rounded,
                      color: AppColors.draftWarning),
                ),
                title: const Text('کارتابل نواقص (بدون عنوان)'),
                selected: _selectedIndex == 5,
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _selectedIndex = 5);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.settings_rounded, color: Colors.white70),
                title: const Text('تنظیمات Flowmodoro و تقویم گوگل'),
                selected: _selectedIndex == 6,
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _selectedIndex = 6);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final music = context.watch<MusicPlayerService>();
    final state = provider.pomodoroState;
    final palette = provider.activePalette;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;

    final untitledCount = provider.untitledDraftRecords.length;
    final realmNotesCount = provider.sessionNotes
        .where((n) => n.realm == provider.dashboardRealm)
        .length;
    final realmOpenOutcomesCount =
        provider.getOpenOutcomes(realm: provider.dashboardRealm).length;

    Color statusColor = AppColors.workBlue;
    if (state.isOvertime) {
      statusColor = AppColors.overtime;
    } else if (state.isLife) {
      statusColor = AppColors.lifeGreen;
    } else if (state.isStopwatch) {
      statusColor = AppColors.stopwatch;
    }

    final activeTitle = provider.activeOutcome?.title ??
        provider.activeRecord?.titleSnapshot ??
        '';

    final int wMin = state.cycleWorkSeconds ~/ 60;
    final int wTargetMin = (state.cycleWorkTargetSeconds / 60).round();
    final int bankMin = state.earnedShortBreakSeconds ~/ 60;
    final int debtMin = state.breakDebtSeconds ~/ 60;

    final isNarrow = screenWidth < 540;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.surface,
        elevation: 0,
        titleSpacing: isWide ? 16 : (isNarrow ? 6 : 10),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: palette.border),
        ),
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            SizedBox(width: isNarrow ? 6 : 8),
            if (screenWidth >= 540) ...[
              const Text(
                'Mab-Focus v4.0',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(width: 10),
            ],
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 6 : 8, vertical: 3),
              decoration: BoxDecoration(
                color: palette.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                state.formattedDisplayTime,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: isNarrow ? 12.0 : 13.5,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (activeTitle.isNotEmpty && screenWidth >= 680) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '${state.realm.labelFa}: $activeTitle',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
            ],
            if (isWide) ...[
              const SizedBox(width: 12),
              Tooltip(
                message:
                    'پیشرفت چرخه Flowmodoro: $wMin از $wTargetMin دقیقه کار | ذخیره استراحت کوتاه: $bankMin دقیقه | بدهی استراحت: $debtMin دقیقه',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded,
                          size: 14, color: palette.accent),
                      const SizedBox(width: 4),
                      Text(
                        '$wMin/${wTargetMin}m • بانک: +${bankMin}m${debtMin > 0 ? " (-${debtMin}m)" : ""}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // سوییچر اصلی داشبورد کار (آبی) / زندگی (سبز)
          _DashboardRealmToggle(
            activeRealm: provider.dashboardRealm,
            compact: isNarrow,
            onChanged: provider.setDashboardRealm,
          ),
          SizedBox(width: isNarrow ? 2 : 8),

          // مینی‌پلیر موسیقی ADHD در هدر دسکتاپ عریض
          if (music.tracks.isNotEmpty && screenWidth >= 1220) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: palette.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      music.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 18,
                      color: palette.accent,
                    ),
                    onPressed: music.togglePlayPause,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Text(
                      music.currentTrack?.title ?? 'موسیقی تمرکز',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: music.nextTrack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  SizedBox(
                    width: 60,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 5),
                        trackHeight: 2,
                      ),
                      child: Slider(
                        value: music.volume,
                        onChanged: music.setVolume,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],

          // سوییچ فوری کار / زندگی تایمر جاری
          IconButton(
            tooltip: state.isWork
                ? 'ورود به قلمرو زندگی (استراحت)'
                : 'بازگشت به قلمرو کار',
            visualDensity: isNarrow ? VisualDensity.compact : null,
            padding: isNarrow ? const EdgeInsets.all(4) : null,
            constraints: isNarrow
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
            icon: Icon(
              state.isWork ? Icons.spa_rounded : Icons.work_rounded,
              color: state.isWork ? AppColors.lifeGreen : AppColors.workBlue,
              size: isNarrow ? 19 : 22,
            ),
            onPressed: provider.toggleWorkLife,
          ),

          // سوییچ ساعت پومودورو / کرنومتر آزاد
          IconButton(
            tooltip: state.isStopwatch
                ? 'تغییر ساعت به پومودورو'
                : 'تغییر ساعت به کرنومتر آزاد',
            visualDensity: isNarrow ? VisualDensity.compact : null,
            padding: isNarrow ? const EdgeInsets.all(4) : null,
            constraints: isNarrow
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
            icon: Icon(
              state.isStopwatch
                  ? Icons.timelapse_rounded
                  : Icons.timer_outlined,
              color: state.isStopwatch
                  ? AppColors.stopwatch
                  : AppColors.textSecondary,
              size: isNarrow ? 19 : 21,
            ),
            onPressed: provider.toggleClockType,
          ),

          if (PlatformHelper.isDesktop && isNarrow)
            IconButton(
              tooltip: 'ویجت شناور',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.picture_in_picture_alt_rounded,
                  size: 19, color: palette.accent),
              onPressed: () =>
                  provider.setWindowPosture(WindowPosture.floatingCircle),
            )
          else if (PlatformHelper.isDesktop)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: palette.accent),
                onPressed: () =>
                    provider.setWindowPosture(WindowPosture.floatingCircle),
                icon:
                    const Icon(Icons.picture_in_picture_alt_rounded, size: 16),
                label: const Text('ویجت شناور', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              backgroundColor: palette.surface,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) =>
                  setState(() => _selectedIndex = idx),
              extended: screenWidth >= 1180,
              selectedIconTheme: IconThemeData(color: palette.accent),
              selectedLabelTextStyle:
                  TextStyle(color: palette.accent, fontWeight: FontWeight.bold),
              unselectedIconTheme:
                  const IconThemeData(color: AppColors.textSecondary),
              unselectedLabelTextStyle:
                  const TextStyle(color: AppColors.textSecondary),
              indicatorColor: palette.accent.withAlpha(36),
              destinations: [
                const NavigationRailDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: Text('تقویم و تایم‌شیت'),
                ),
                NavigationRailDestination(
                  icon: Badge(
                    isLabelVisible: realmOpenOutcomesCount > 0,
                    backgroundColor: palette.accent,
                    label: Text('$realmOpenOutcomesCount'),
                    child: const Icon(Icons.checklist_rounded),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: realmOpenOutcomesCount > 0,
                    backgroundColor: palette.accent,
                    label: Text('$realmOpenOutcomesCount'),
                    child: const Icon(Icons.fact_check_rounded),
                  ),
                  label: Text('کارهای باز (${provider.dashboardRealm.labelFa})'),
                ),
                NavigationRailDestination(
                  icon: Badge(
                    isLabelVisible: realmNotesCount > 0,
                    backgroundColor: palette.accent,
                    label: Text('$realmNotesCount'),
                    child: const Icon(Icons.assignment_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: realmNotesCount > 0,
                    backgroundColor: palette.accent,
                    label: Text('$realmNotesCount'),
                    child: const Icon(Icons.assignment_rounded),
                  ),
                  label: const Text('گزارش‌ها و یادداشت‌ها'),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.account_tree_outlined),
                  selectedIcon: const Icon(Icons.account_tree_rounded),
                  label: Text(provider.dashboardRealm == AppRealm.life
                      ? 'استودیوی پروژه‌های زندگی'
                      : 'استودیوی پروژه‌های کار'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.pie_chart_outline_rounded),
                  selectedIcon: Icon(Icons.pie_chart_rounded),
                  label: Text('سند ظرفیت و سارقان زمان'),
                ),
                NavigationRailDestination(
                  icon: Badge(
                    isLabelVisible: untitledCount > 0,
                    backgroundColor: AppColors.draftWarning,
                    label: Text('$untitledCount'),
                    child: const Icon(Icons.inbox_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: untitledCount > 0,
                    backgroundColor: AppColors.draftWarning,
                    label: Text('$untitledCount'),
                    child: const Icon(Icons.inbox_rounded),
                  ),
                  label: const Text('کارتابل بدون عنوان'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: Text('تنظیمات ریتم و چرخه'),
                ),
              ],
            ),
          if (isWide) VerticalDivider(width: 1, color: palette.border),
          Expanded(child: _tabs[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              backgroundColor: palette.surface,
              indicatorColor: palette.accent.withAlpha(42),
              selectedIndex: _selectedIndex <= 2 ? _selectedIndex : 3,
              onDestinationSelected: (idx) {
                if (idx <= 2) {
                  setState(() => _selectedIndex = idx);
                } else {
                  _openMobileMoreSheet(context, provider, untitledCount);
                }
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'تقویم',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: realmOpenOutcomesCount > 0,
                    backgroundColor: palette.accent,
                    label: Text('$realmOpenOutcomesCount'),
                    child: const Icon(Icons.checklist_rounded),
                  ),
                  label: 'کارها',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: realmNotesCount > 0,
                    backgroundColor: palette.accent,
                    label: Text('$realmNotesCount'),
                    child: const Icon(Icons.assignment_outlined),
                  ),
                  label: 'یادداشت',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: untitledCount > 0,
                    backgroundColor: AppColors.draftWarning,
                    label: Text('$untitledCount'),
                    child: const Icon(Icons.apps_rounded),
                  ),
                  label: 'بیشتر',
                ),
              ],
            ),
    );
  }
}

class _DashboardRealmToggle extends StatelessWidget {
  final AppRealm activeRealm;
  final bool compact;
  final ValueChanged<AppRealm> onChanged;

  const _DashboardRealmToggle({
    required this.activeRealm,
    this.compact = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 2 : 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RealmTogglePill(
            label: 'کار',
            icon: Icons.work_rounded,
            color: AppColors.workBlue,
            isSelected: activeRealm == AppRealm.work,
            compact: compact,
            onTap: () => onChanged(AppRealm.work),
          ),
          const SizedBox(width: 2),
          _RealmTogglePill(
            label: 'زندگی',
            icon: Icons.spa_rounded,
            color: AppColors.lifeGreen,
            isSelected: activeRealm == AppRealm.life,
            compact: compact,
            onTap: () => onChanged(AppRealm.life),
          ),
        ],
      ),
    );
  }
}

class _RealmTogglePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  const _RealmTogglePill({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 10, vertical: compact ? 3 : 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(42) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: compact ? 12 : 14,
                color: isSelected ? color : AppColors.textSecondary),
            SizedBox(width: compact ? 3 : 4),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 10.5 : 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
