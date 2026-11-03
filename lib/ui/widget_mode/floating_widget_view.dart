// ویجت شناور، حلقه وضعیت، شمارنده و نوار لبه‌ای
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/constants.dart';
import '../../core/platform_helper.dart';
import '../../models/pomodoro_state.dart';
import '../../providers/app_state_provider.dart';
import 'quick_task_sheet.dart';

class FloatingWidgetView extends StatefulWidget {
  const FloatingWidgetView({super.key});

  @override
  State<FloatingWidgetView> createState() => _FloatingWidgetViewState();
}

class _FloatingWidgetViewState extends State<FloatingWidgetView>
    with WindowListener {
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

  /// بررسی خودکار فاصله از لبه‌های چپ و راست مانیتور پس از رها کردن ماوس
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
    if (provider.isQuickMenuExpanded) return;

    _isCheckingSnap = true;
    final snapPosture = await PlatformHelper.checkEdgeSnapCondition();
    if (snapPosture != null && mounted) {
      await provider.setWindowPosture(snapPosture);
    }
    _isCheckingSnap = false;
  }

  Color _resolveRingColor(PomodoroState state) {
    if (state.isOvertime) return AppColors.overtime;
    if (state.mode == PomodoroMode.focus) return AppColors.focus;
    return AppColors.breakTime;
  }

  String _resolveStatusLabel(PomodoroState state) {
    if (state.isOvertime) return 'اضافه‌کاری';
    switch (state.mode) {
      case PomodoroMode.focus:
        return 'تمرکز (ست ${(state.completedSetsInCycle % AppDurations.setsPerCycle) + 1}/4)';
      case PomodoroMode.shortBreak:
        return 'استراحت کوتاه';
      case PomodoroMode.longBreak:
        return 'استراحت طولانی';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final state = provider.pomodoroState;
        final ringColor = _resolveRingColor(state);

        // حالت ۱: نوار عمودی چسبیده به لبه چپ یا راست مانیتور (Edge-Docked Vertical Pill)
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
                      Border.all(color: ringColor.withAlpha(160), width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: state.isOvertime
                              ? 1.0
                              : state.progress.clamp(0.08, 1.0),
                          widthFactor: 1.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: ringColor.withAlpha(200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // حالت ۲: ویجت دایره‌ای شفاف به همراه منوی بازشونده شروع فوری
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // حلقه دایره‌ای اصلی (۲۰۴ در ۲۰۴ پیکسل)
                  Container(
                    width: 204,
                    height: 204,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.background,
                      border: Border.all(color: AppColors.border, width: 1.2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black87,
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // رسم حلقه پیشرفت پومودورو
                        SizedBox(
                          width: 188,
                          height: 188,
                          child: CustomPaint(
                            painter: _RingProgressPainter(
                              progress: state.isOvertime ? 1.0 : state.progress,
                              ringColor: ringColor,
                            ),
                          ),
                        ),

                        // محتوای درونی دایره: ناحیه جابه‌جایی در بالا و دکمه‌های مجزا در پایین
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // ناحیه مخصوص کشیدن پنجره با ماوس (ایزوله از دکمه‌ها)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (_) {
                                if (PlatformHelper.isDesktop) {
                                  windowManager.startDragging();
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    top: 10, bottom: 4, left: 16, right: 16),
                                child: Column(
                                  children: [
                                    // دستگیره ظریف جابه‌جایی و وضعیت فعلی
                                    Container(
                                      width: 28,
                                      height: 3,
                                      margin: const EdgeInsets.only(bottom: 6),
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.textMuted.withAlpha(120),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    Text(
                                      _resolveStatusLabel(state),
                                      style: TextStyle(
                                        color: ringColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    // نمایشگر زمان با اعداد هم‌عرض (Tabular Figures)
                                    Text(
                                      state.formattedDisplayTime,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w700,
                                        color: state.isOvertime
                                            ? AppColors.overtime
                                            : AppColors.textPrimary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                    // عنوان تسک جاری
                                    SizedBox(
                                      width: 145,
                                      child: Text(
                                        provider.activeTaskLog?.title ??
                                            'آماده شروع کار...',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: provider.activeTaskLog
                                                      ?.isUntitledDraft ==
                                                  true
                                              ? AppColors.draftWarning
                                              : AppColors.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),

                            // نوار دکمه‌های کنترلی (کاملاً مستقل از GestureDetector کشیدن پنجره)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // ۱. دکمه Play / Pause
                                _WidgetIconButton(
                                  tooltip: state.status ==
                                              TimerStatus.running ||
                                          state.status == TimerStatus.overtime
                                      ? 'توقف موقت'
                                      : 'شروع فوری',
                                  icon: state.status == TimerStatus.running ||
                                          state.status == TimerStatus.overtime
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  backgroundColor: ringColor,
                                  iconColor: Colors.white,
                                  onPressed: () async {
                                    if (state.status == TimerStatus.running ||
                                        state.status == TimerStatus.overtime) {
                                      await provider.pauseTimer();
                                    } else if (state.status ==
                                        TimerStatus.paused) {
                                      await provider.resumeTimer();
                                    } else {
                                      await provider.startInstantWork();
                                      await provider
                                          .toggleQuickMenuExpanded(true);
                                    }
                                  },
                                ),
                                const SizedBox(width: 6),

                                // ۲. دکمه شروع استراحت / پایان جلسه
                                _WidgetIconButton(
                                  tooltip: state.mode == PomodoroMode.focus
                                      ? 'شروع استراحت'
                                      : 'پایان استراحت و بازنشانی',
                                  icon: state.mode == PomodoroMode.focus
                                      ? Icons.coffee_rounded
                                      : Icons.stop_rounded,
                                  backgroundColor: AppColors.surfaceElevated,
                                  iconColor: AppColors.breakTime,
                                  onPressed: () async {
                                    if (state.mode == PomodoroMode.focus) {
                                      await provider.startBreak();
                                    } else {
                                      await provider.stopAndResetSession();
                                    }
                                  },
                                ),
                                const SizedBox(width: 6),

                                // ۳. دکمه باز و بسته کردن منوی سریع تسک (+ / ···)
                                _WidgetIconButton(
                                  tooltip: 'مشخصات تسک / تسک بعدی',
                                  icon: provider.isQuickMenuExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.more_horiz_rounded,
                                  backgroundColor: provider.isQuickMenuExpanded
                                      ? AppColors.focus.withAlpha(60)
                                      : AppColors.surfaceElevated,
                                  iconColor: AppColors.textPrimary,
                                  onPressed: () {
                                    provider.toggleQuickMenuExpanded(
                                        !provider.isQuickMenuExpanded);
                                  },
                                ),
                                const SizedBox(width: 6),

                                // ۴. دکمه بازگشت به پنجره داشبورد کامل
                                _WidgetIconButton(
                                  tooltip: 'باز کردن داشبورد کامل',
                                  icon: Icons.open_in_full_rounded,
                                  backgroundColor: AppColors.surfaceElevated,
                                  iconColor: AppColors.textSecondary,
                                  onPressed: () {
                                    provider.setWindowPosture(
                                        WindowPosture.dashboard);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // کشوی شروع فوری و تعویض تسک در میانه پومودورو
                  if (provider.isQuickMenuExpanded)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: QuickTaskSheet(),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WidgetIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onPressed;

  const _WidgetIconButton({
    required this.tooltip,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 17, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _RingProgressPainter extends CustomPainter {
  final double progress;
  final Color ringColor;

  _RingProgressPainter({
    required this.progress,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 5;

    final trackPaint = Paint()
      ..color = Colors.white.withAlpha(18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5;

    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor;
  }
}
