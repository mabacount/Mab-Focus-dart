import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/platform_helper.dart';
import '../models/pomodoro_state.dart';
import '../providers/app_state_provider.dart';
import 'dashboard_mode/dashboard_screen.dart';
import 'widget_mode/floating_widget_view.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final posture = provider.pomodoroState.windowPosture;
        final isWidgetMode =
            PlatformHelper.isDesktop && posture != WindowPosture.dashboard;

        if (isWidgetMode) {
          return const FloatingWidgetView();
        }

        return Stack(
          children: [
            const DashboardScreen(),
            if (provider.lastErgonomicNudgeMessage != null)
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.overtime, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notification_important_rounded,
                              color: AppColors.overtime),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              provider.lastErgonomicNudgeMessage!,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              provider.clearErgonomicNudge();
                              provider.startBreak();
                            },
                            child: const Text(
                              'شروع استراحت',
                              style: TextStyle(
                                  color: AppColors.breakTime,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: AppColors.textSecondary),
                            onPressed: provider.clearErgonomicNudge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
