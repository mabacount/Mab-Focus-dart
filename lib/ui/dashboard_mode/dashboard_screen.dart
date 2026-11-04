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
    CapacityThievesTab(),
    ActivityLogTab(),
    UntitledInboxTab(),
    ProjectStudioTab(),
    SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final music = context.watch<MusicPlayerService>();
    final state = provider.pomodoroState;
    final untitledCount = provider.untitledDraftLogs.length;
    final isWide = MediaQuery.of(context).size.width >= 900;

    Color statusColor = AppColors.focus;
    if (state.isStopwatch) {
      statusColor = state.isWork ? AppColors.stopwatch : AppColors.breakTime;
    } else if (state.isOvertime) {
      statusColor = AppColors.overtime;
    } else if (state.isLife) {
      statusColor = AppColors.breakTime;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration:
                  BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text('Mab-Focus v3.0',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                state.formattedDisplayTime,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (provider.activeTaskLog != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  state.isWork
                      ? 'فعال: ${provider.activeTaskLog!.title}'
                      : 'وضعیت: زندگی / استراحت',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // مینی‌پلیر موسیقی ADHD در هدر
          if (music.tracks.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
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
                      color: AppColors.focus,
                    ),
                    onPressed: music.togglePlayPause,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      music.currentTrack?.title ?? 'موسیقی تمرکز',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
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
                    width: 70,
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
            const SizedBox(width: 10),
          ],

          // سوییچ کار و زندگی (استراحت) - در این سیستم توقف نداریم؛ یا کار است یا زندگی
          IconButton(
            tooltip: state.isWork
                ? 'ورود به وضعیت زندگی (استراحت)'
                : 'پایان استراحت و شروع کار',
            icon: Icon(
              state.isWork ? Icons.coffee_rounded : Icons.work_rounded,
              color: state.isWork ? AppColors.breakTime : AppColors.focus,
              size: 24,
            ),
            onPressed: provider.toggleWorkLife,
          ),

          // ۳. سوییچ پومودورو و کرنومتر
          IconButton(
            tooltip: state.isStopwatch
                ? 'سوییچ به پومودورو (سقف‌دار)'
                : 'سوییچ به کرنومتر آزاد (بی‌پایان)',
            icon: Icon(
              state.isStopwatch
                  ? Icons.timelapse_rounded
                  : Icons.timer_outlined,
              color: state.isStopwatch
                  ? AppColors.stopwatch
                  : AppColors.textSecondary,
              size: 22,
            ),
            onPressed: provider.toggleClockType,
          ),
          const SizedBox(width: 8),

          // دکمه بازگشت به ویجت شناور
          if (PlatformHelper.isDesktop)
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.focus),
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
              backgroundColor: AppColors.surface,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) =>
                  setState(() => _selectedIndex = idx),
              extended: MediaQuery.of(context).size.width >= 1150,
              selectedIconTheme: const IconThemeData(color: AppColors.focus),
              selectedLabelTextStyle: const TextStyle(
                  color: AppColors.focus, fontWeight: FontWeight.bold),
              unselectedIconTheme:
                  const IconThemeData(color: AppColors.textSecondary),
              unselectedLabelTextStyle:
                  const TextStyle(color: AppColors.textSecondary),
              destinations: [
                const NavigationRailDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: Text('تقویم هوشمند (Google)'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.pie_chart_outline_rounded),
                  selectedIcon: Icon(Icons.pie_chart_rounded),
                  label: Text('سند ظرفیت و سارقان زمان'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.table_chart_outlined),
                  selectedIcon: Icon(Icons.table_chart_rounded),
                  label: Text('جدول تایم‌شیت و کارکرد'),
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
                  icon: Icon(Icons.account_tree_outlined),
                  selectedIcon: Icon(Icons.account_tree_rounded),
                  label: Text('استودیوی پروژه‌ها'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: Text('تنظیمات و موسیقی'),
                ),
              ],
            ),
          if (isWide) const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(child: _tabs[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              backgroundColor: AppColors.surface,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) =>
                  setState(() => _selectedIndex = idx),
              destinations: [
                const NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined), label: 'تقویم'),
                const NavigationDestination(
                    icon: Icon(Icons.pie_chart_outline_rounded),
                    label: 'ظرفیت'),
                const NavigationDestination(
                    icon: Icon(Icons.table_chart_outlined), label: 'تایم‌شیت'),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: untitledCount > 0,
                    label: Text('$untitledCount'),
                    child: const Icon(Icons.inbox_outlined),
                  ),
                  label: 'نواقص',
                ),
                const NavigationDestination(
                    icon: Icon(Icons.account_tree_outlined), label: 'پروژه‌ها'),
                const NavigationDestination(
                    icon: Icon(Icons.settings_outlined), label: 'تنظیمات'),
              ],
            ),
    );
  }
}
