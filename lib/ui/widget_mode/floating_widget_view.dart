import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/constants.dart';
import '../../core/platform_helper.dart';
import '../../models/pomodoro_state.dart';
import '../../providers/app_state_provider.dart';
import '../../services/music_player_service.dart';
import 'quick_task_sheet.dart';

class FloatingWidgetView extends StatefulWidget {
  const FloatingWidgetView({super.key});

  @override
  State<FloatingWidgetView> createState() => _FloatingWidgetViewState();
}

class _FloatingWidgetViewState extends State<FloatingWidgetView>
    with WindowListener {
  bool _isHovered = false;
  bool _isCheckingSnap = false;

  @override
  void initState() {
    super.initState();
    if (PlatformHelper.isDesktop) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (PlatformHelper.isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMoved() async {
    if (_isCheckingSnap || !mounted) {
      return;
    }
    final provider = context.read<AppStateProvider>();
    if (provider.pomodoroState.windowPosture != WindowPosture.floatingCircle) {
      return;
    }
    if (provider.isQuickMenuExpanded) {
      return;
    }

    _isCheckingSnap = true;
    final snapPosture = await PlatformHelper.checkEdgeSnapCondition();
    if (snapPosture != null && mounted) {
      await provider.setWindowPosture(snapPosture);
    }
    _isCheckingSnap = false;
  }

  void _onHoverChanged(bool hovered) async {
    if (_isHovered == hovered) return;
    setState(() => _isHovered = hovered);
    final provider = context.read<AppStateProvider>();
    if (!provider.isQuickMenuExpanded) {
      await PlatformHelper.switchToFloatingWidgetMode(isHovered: hovered);
    }
  }

  Color _resolveRingColor(PomodoroState state) {
    if (state.isStopwatch) return AppColors.stopwatch;
    if (state.isOvertime) return AppColors.overtime;
    if (state.mode == PomodoroMode.focus) return AppColors.focus;
    return AppColors.breakTime;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppStateProvider, MusicPlayerService>(
      builder: (context, provider, music, _) {
        final state = provider.pomodoroState;
        final ringColor = _resolveRingColor(state);

        // ۱. حالت نوار عمودی چسبیده به لبه مانیتور
        if (state.windowPosture == WindowPosture.edgeDockedLeft ||
            state.windowPosture == WindowPosture.edgeDockedRight) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: MouseRegion(
              onEnter: (_) {
                provider.setWindowPosture(
                  WindowPosture.floatingCircle,
                  expanded: provider.isQuickMenuExpanded,
                );
              },
              child: Container(
                width: 18,
                height: 160,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.horizontal(
                    right: state.windowPosture == WindowPosture.edgeDockedLeft
                        ? const Radius.circular(10)
                        : Radius.zero,
                    left: state.windowPosture == WindowPosture.edgeDockedRight
                        ? const Radius.circular(10)
                        : Radius.zero,
                  ),
                  border:
                      Border.all(color: ringColor.withAlpha(180), width: 1.5),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: state.isOvertime || state.isStopwatch
                        ? 1.0
                        : state.progress.clamp(0.08, 1.0),
                    widthFactor: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: ringColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // ۲. حالت دایره بدون کادر با انیمیشن هاور درونی و باکس تسک زیر دایره
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: MouseRegion(
            onEnter: (_) => _onHoverChanged(true),
            onExit: (_) => _onHoverChanged(false),
            child: Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // دایره ۱۰۴ پیکسلی
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.background,
                        border: Border.all(color: AppColors.border, width: 1.2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black87,
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // رسم حلقه پیشرفت
                          SizedBox(
                            width: 96,
                            height: 96,
                            child: CustomPaint(
                              painter: _CompactRingPainter(
                                progress: state.isOvertime || state.isStopwatch
                                    ? 1.0
                                    : state.progress,
                                ringColor: ringColor,
                              ),
                            ),
                          ),

                          // شمارنده زمان (با جابه‌جایی انیمیشنی به بالا در حالت هاور)
                          AnimatedAlign(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            alignment: _isHovered
                                ? const Alignment(0, -0.48)
                                : Alignment.center,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (_) {
                                if (PlatformHelper.isDesktop) {
                                  windowManager.startDragging();
                                }
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    state.formattedDisplayTime,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: state.isStopwatch ? 16 : 19,
                                      fontWeight: FontWeight.bold,
                                      color: state.isOvertime
                                          ? AppColors.overtime
                                          : AppColors.textPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                  if (!_isHovered)
                                    Container(
                                      width: 5,
                                      height: 5,
                                      margin: const EdgeInsets.only(top: 2),
                                      decoration: BoxDecoration(
                                        color: ringColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // ردیف دکمه‌های مینیاتوری در نیمه پایینی داخل دایره (فقط در حالت هاور)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            bottom: _isHovered ? 12 : -30,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _isHovered ? 1.0 : 0.0,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Play / Pause
                                  _MiniCircleButton(
                                    tooltip: state.status == TimerStatus.running
                                        ? 'توقف'
                                        : 'شروع',
                                    icon: state.status == TimerStatus.running
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: ringColor,
                                    onPressed: () {
                                      if (state.status == TimerStatus.running) {
                                        provider.pauseTimer();
                                      } else if (state.status ==
                                          TimerStatus.paused) {
                                        provider.resumeTimer();
                                      } else {
                                        provider.startInstantWork();
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  // استراحت / توقف
                                  _MiniCircleButton(
                                    tooltip: state.isStopwatch
                                        ? 'توقف کرنومتر'
                                        : (state.mode == PomodoroMode.focus
                                            ? 'استراحت'
                                            : 'پایان'),
                                    icon: state.isStopwatch
                                        ? Icons.stop_rounded
                                        : (state.mode == PomodoroMode.focus
                                            ? Icons.coffee_rounded
                                            : Icons.stop_rounded),
                                    color: AppColors.surfaceElevated,
                                    iconColor: AppColors.breakTime,
                                    onPressed: () {
                                      if (state.isStopwatch) {
                                        provider.stopAndResetSession();
                                      } else if (state.mode ==
                                          PomodoroMode.focus) {
                                        provider.startBreak();
                                      } else {
                                        provider.stopAndResetSession();
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  // سوییچ به کرنومتر آزاد
                                  _MiniCircleButton(
                                    tooltip: state.isStopwatch
                                        ? 'پومودورو'
                                        : 'کرنومتر آزاد',
                                    icon: Icons.timer_outlined,
                                    color: AppColors.surfaceElevated,
                                    iconColor: state.isStopwatch
                                        ? AppColors.stopwatch
                                        : AppColors.textSecondary,
                                    onPressed: () {
                                      if (state.isStopwatch) {
                                        provider.stopAndResetSession();
                                      } else {
                                        provider.startStopwatchMode();
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  // بزرگ‌نمایی به داشبورد کامل
                                  _MiniCircleButton(
                                    tooltip: 'داشبورد کامل',
                                    icon: Icons.open_in_full_rounded,
                                    color: AppColors.surfaceElevated,
                                    iconColor: AppColors.textSecondary,
                                    onPressed: () {
                                      provider.setWindowPosture(
                                          WindowPosture.dashboard);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // باکس کپسولی تسک جاری زیر دایره (ظهور هنگام هاور یا باز بودن منو)
                    if (_isHovered || provider.isQuickMenuExpanded)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            provider.toggleQuickMenuExpanded(
                                !provider.isQuickMenuExpanded);
                          },
                          child: Container(
                            width: 172,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    provider.activeTaskLog?.title ??
                                        'تسک جدید...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: provider.activeTaskLog
                                                  ?.isUntitledDraft ==
                                              true
                                          ? AppColors.draftWarning
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (music.tracks.isNotEmpty)
                                  InkWell(
                                    onTap: music.togglePlayPause,
                                    child: Icon(
                                      music.isPlaying
                                          ? Icons.music_note_rounded
                                          : Icons.music_off_rounded,
                                      size: 14,
                                      color: music.isPlaying
                                          ? AppColors.focus
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                const SizedBox(width: 2),
                                Icon(
                                  provider.isQuickMenuExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.edit_note_rounded,
                                  size: 15,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // کشوی فرم ویرایش تسک
                    if (provider.isQuickMenuExpanded)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: QuickTaskSheet(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniCircleButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback onPressed;

  const _MiniCircleButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    this.iconColor = Colors.white,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, size: 12, color: iconColor),
        ),
      ),
    );
  }
}

class _CompactRingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;

  _CompactRingPainter({required this.progress, required this.ringColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 4;

    final trackPaint = Paint()
      ..color = Colors.white.withAlpha(15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(center, radius, trackPaint);

    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    final progressPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CompactRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor;
  }
}
