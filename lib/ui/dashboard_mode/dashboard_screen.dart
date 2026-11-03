import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/platform_helper.dart';
import '../../models/pomodoro_state.dart';
import '../../providers/app_state_provider.dart';
import 'activity_log_tab.dart';
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
    ActivityLogTab(),
    UntitledInboxTab(),
    ProjectStudioTab(),
    SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final state = provider.pomodoroState;
    final untitledCount = provider.untitledDraftLogs.length;
    final isWide = MediaQuery.of(context).size.width >= 800;

    Color statusColor = AppColors.focus;
    if (state.isOvertime) {
      statusColor = AppColors.overtime;
    } else if (state.mode != PomodoroMode.focus) {
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
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Mab-Focus',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(width: 8),
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
            const SizedBox(width: 10),
            if (provider.activeTaskLog != null)
              Flexible(
                child: Text(
                  'در حال اجرا: ${provider.activeTaskLog!.title}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
        actions: [
          // کنترل سریع تایمر از داخل هدر داشبورد
          IconButton(
            tooltip: state.status == TimerStatus.running ||
                    state.status == TimerStatus.overtime
                ? 'توقف موقت تایمر'
                : 'شروع فوری تایمر',
            icon: Icon(
              state.status == TimerStatus.running ||
                      state.status == TimerStatus.overtime
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: statusColor,
              size: 28,
            ),
            onPressed: () {
              if (state.status == TimerStatus.running ||
                  state.status == TimerStatus.overtime) {
                provider.pauseTimer();
              } else if (state.status == TimerStatus.paused) {
                provider.resumeTimer();
              } else {
                provider.startInstantWork();
              }
            },
          ),
          if (state.status != TimerStatus.idle)
            IconButton(
              tooltip: state.mode == PomodoroMode.focus
                  ? 'شروع استراحت'
                  : 'پایان و بازنشانی',
              icon: Icon(
                state.mode == PomodoroMode.focus
                    ? Icons.coffee_rounded
                    : Icons.stop_circle_rounded,
                color: AppColors.breakTime,
              ),
              onPressed: () {
                if (state.mode == PomodoroMode.focus) {
                  provider.startBreak();
                } else {
                  provider.stopAndResetSession();
                }
              },
            ),
          const SizedBox(width: 8),
          if (PlatformHelper.isDesktop)
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.focus,
                  foregroundColor: Colors.white,
                ),
                onPressed: () =>
                    provider.setWindowPosture(WindowPosture.floatingCircle),
                icon:
                    const Icon(Icons.picture_in_picture_alt_rounded, size: 18),
                label: const Text('تبدیل به ویجت شناور'),
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
              extended: MediaQuery.of(context).size.width >= 1050,
              selectedIconTheme: const IconThemeData(color: AppColors.focus),
              selectedLabelTextStyle: const TextStyle(
                color: AppColors.focus,
                fontWeight: FontWeight.bold,
              ),
              unselectedIconTheme:
                  const IconThemeData(color: AppColors.textSecondary),
              unselectedLabelTextStyle:
                  const TextStyle(color: AppColors.textSecondary),
              destinations: [
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
                  label: Text('تنظیمات و همگام‌سازی'),
                ),
              ],
            ),
          if (isWide) const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: _tabs[_selectedIndex],
          ),
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
                  icon: Icon(Icons.table_chart_outlined),
                  selectedIcon: Icon(Icons.table_chart_rounded),
                  label: 'تایم‌شیت',
                ),
                NavigationDestination(
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
                  label: 'کارتابل نواقص',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.account_tree_outlined),
                  selectedIcon: Icon(Icons.account_tree_rounded),
                  label: 'پروژه‌ها',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'تنظیمات',
                ),
              ],
            ),
    );
  }
}
