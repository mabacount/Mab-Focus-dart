import 'dart:async';
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
  bool _buttonsOnRight = false;
  Timer? _hoverDebounceTimer;

  @override
  void initState() {
    super.initState();
    if (PlatformHelper.isDesktop) {
      windowManager.addListener(this);
      _checkInitialEdgePosition();
    }
  }

  void _checkInitialEdgePosition() async {
    final nearLeft = await PlatformHelper.isNearLeftEdge();
    if (mounted && nearLeft != _buttonsOnRight) {
      setState(() => _buttonsOnRight = nearLeft);
    }
  }

  @override
  void dispose() {
    _hoverDebounceTimer?.cancel();
    if (PlatformHelper.isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMoved() async {
    if (_isCheckingSnap || !mounted) return;

    final provider = context.read<AppStateProvider>();
    if (provider.pomodoroState.windowPosture != WindowPosture.floatingCircle) {
      return;
    }
    if (provider.isQuickMenuExpanded) return;

    // بررسی نزدیکی به لبه چپ نمایشگر
    final nearLeft = await PlatformHelper.isNearLeftEdge();
    if (mounted && nearLeft != _buttonsOnRight) {
      setState(() => _buttonsOnRight = nearLeft);
    }

    _isCheckingSnap = true;
    final snapPosture = await PlatformHelper.checkEdgeSnapCondition();
    if (snapPosture != null && mounted) {
      await provider.setWindowPosture(snapPosture);
    }
    _isCheckingSnap = false;
  }

  void _onMouseEnter() {
    _hoverDebounceTimer?.cancel();
    if (!_isHovered && mounted) {
      setState(() => _isHovered = true);
    }
  }

  void _onMouseExit() {
    _hoverDebounceTimer?.cancel();
    _hoverDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && _isHovered) {
        setState(() => _isHovered = false);
      }
    });
  }

  Color _resolveRingColor(PomodoroState state) {
    if (state.isStopwatch) {
      return state.isWork ? AppColors.stopwatch : AppColors.breakTime;
    }
    if (state.isOvertime) return AppColors.overtime;
    if (state.isWork) return AppColors.focus;
    return AppColors.breakTime;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppStateProvider, MusicPlayerService>(
      builder: (context, provider, music, _) {
        final state = provider.pomodoroState;
        final ringColor = _resolveRingColor(state);
        final bool showFullMenu = _isHovered || provider.isQuickMenuExpanded;

        // ۱. حالت نوار کناری چسبیده به لبه مانیتور (Edge-Docked)
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
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.horizontal(
                    right: state.windowPosture == WindowPosture.edgeDockedLeft
                        ? const Radius.circular(9)
                        : Radius.zero,
                    left: state.windowPosture == WindowPosture.edgeDockedRight
                        ? const Radius.circular(9)
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
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // هندسه دقیق چیدمان در پنجره ۳۴۰ پیکسلی:
        // دایره با ابعاد ۶۸×۶۸ در فاصله ۴۴ پیکسلی از لبه پنجره قرار دارد.
        // مرکز دایره دقیقاً در فاصله ۷۸ پیکسلی (۴۴ + ۳۴) از لبه مهار شده است.
        const double circleTop = 10.0;
        const double circleEdge = 44.0;
        const double circleSize = 68.0;

        // دایره تایمر اصلی (تنها بخش درگ و جابه‌جایی پنجره)
        final timerCircle = MouseRegion(
          onEnter: (_) => _onMouseEnter(),
          onExit: (_) => _onMouseExit(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              if (PlatformHelper.isDesktop) {
                windowManager.startDragging();
              }
            },
            child: Container(
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF18181B),
                border: Border.all(
                  color: Colors.white.withAlpha(30),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(150),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // حلقه پیشرفت زمان
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: CustomPaint(
                      painter: _CompactRingPainter(
                        progress: state.isOvertime || state.isStopwatch
                            ? 1.0
                            : state.progress,
                        ringColor: ringColor,
                      ),
                    ),
                  ),

                  // متن زمان و نقطه وضعیت
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.formattedDisplayTime,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: state.isStopwatch &&
                                  state.elapsedSeconds >= 3600
                              ? 12.5
                              : 16.5,
                          fontWeight: FontWeight.w700,
                          color: state.isOvertime
                              ? AppColors.overtime
                              : Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Container(
                        width: 4.5,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: ringColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        // دکمه‌های کنترل نوار ابزار
        final buttonFullscreen = _MiniCircleButton(
          tooltip: 'داشبورد کامل',
          icon: Icons.open_in_full_rounded,
          onPressed: () {
            provider.setWindowPosture(WindowPosture.dashboard);
          },
        );

        final buttonTune = _MiniCircleButton(
          tooltip: 'تنظیمات و تسک جاری',
          icon: provider.isQuickMenuExpanded
              ? Icons.expand_less_rounded
              : Icons.tune_rounded,
          isActive: provider.isQuickMenuExpanded,
          activeColor: AppColors.focus,
          onPressed: () {
            provider.toggleQuickMenuExpanded(!provider.isQuickMenuExpanded);
          },
        );

        final buttonPin = _MiniCircleButton(
          tooltip: provider.isPinned
              ? 'ویجت پین است (همیشه رو)'
              : 'پین کردن ویجت (همیشه رو)',
          icon: provider.isPinned
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          isActive: provider.isPinned,
          activeColor: AppColors.focus,
          onPressed: provider.togglePin,
        );

        final buttonStopwatch = _MiniCircleButton(
          tooltip: state.isStopwatch
              ? 'سوییچ به پومودورو'
              : 'سوییچ به کرنومتر آزاد',
          icon: state.isStopwatch
              ? Icons.timelapse_rounded
              : Icons.timer_outlined,
          isActive: state.isStopwatch,
          activeColor: AppColors.stopwatch,
          onPressed: provider.toggleClockType,
        );

        // دکمه اصلی انتقال پیوسته قلمرو: کار ⇄ زندگی (استراحت)
        // در این اپ چیزی به نام توقف وجود ندارد؛ پیوسته یا کار است یا زندگی
        final buttonRealmAction = _RealmActionButton(
          isWork: state.isWork,
          ringColor: ringColor,
          onPressed: provider.toggleWorkLife,
        );

        // چیدمان دکمه‌ها در LTR:
        // حالت پیش‌فرض (سمت چپ دایره): [تمام‌صفحه, تنظیمات, پین, کرنومتر, دکمه کار/زندگی] -> مجاور دایره در سمت راست
        // حالت لبه چپ (سمت راست دایره): [دکمه کار/زندگی, کرنومتر, پین, تنظیمات, تمام‌صفحه] -> مجاور دایره در سمت چپ
        final List<Widget> buttonWidgets = _buttonsOnRight
            ? [
                buttonRealmAction,
                const SizedBox(width: 5),
                buttonStopwatch,
                const SizedBox(width: 5),
                buttonPin,
                const SizedBox(width: 5),
                buttonTune,
                const SizedBox(width: 5),
                buttonFullscreen,
              ]
            : [
                buttonFullscreen,
                const SizedBox(width: 5),
                buttonTune,
                const SizedBox(width: 5),
                buttonPin,
                const SizedBox(width: 5),
                buttonStopwatch,
                const SizedBox(width: 5),
                buttonRealmAction,
              ];

        // کپسول دکمه‌های کنترل
        final buttonsCapsule = MouseRegion(
          onEnter: (_) => _onMouseEnter(),
          onExit: (_) => _onMouseExit(),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B).withAlpha(245),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withAlpha(25),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(120),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: buttonWidgets,
            ),
          ),
        );

        // کپسول نام تسک زیر دایره
        final taskCapsule = MouseRegion(
          onEnter: (_) => _onMouseEnter(),
          onExit: (_) => _onMouseExit(),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              provider.toggleQuickMenuExpanded(!provider.isQuickMenuExpanded);
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 156),
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 4.0),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B).withAlpha(245),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withAlpha(25),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(90),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      state.isWork
                          ? (provider.activeTaskLog?.title ?? 'تسک جدید...')
                          : 'در حال استراحت / زندگی',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        color: state.isWork
                            ? (provider.activeTaskLog?.isUntitledDraft == true
                                ? AppColors.draftWarning
                                : AppColors.textPrimary)
                            : AppColors.breakTime,
                      ),
                    ),
                  ),
                  if (music.tracks.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: music.togglePlayPause,
                      child: Icon(
                        music.isPlaying
                            ? Icons.music_note_rounded
                            : Icons.music_off_rounded,
                        size: 13,
                        color: music.isPlaying
                            ? AppColors.focus
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              clipBehavior: Clip.none,
              children: [
                // ۱. کپسول دکمه‌های کنترل (اسلاید نرم از پشت دایره به چپ یا راست)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  top: 22,
                  right: _buttonsOnRight
                      ? null
                      : (showFullMenu ? 110 : circleEdge),
                  left: _buttonsOnRight
                      ? (showFullMenu ? 110 : circleEdge)
                      : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    opacity: showFullMenu ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !showFullMenu,
                      child: buttonsCapsule,
                    ),
                  ),
                ),

                // ۲. دایره تایمر اصلی (کاملاً ثابت و مهارشده در مختصات مطلق)
                Positioned(
                  top: circleTop,
                  right: _buttonsOnRight ? null : circleEdge,
                  left: _buttonsOnRight ? circleEdge : null,
                  child: timerCircle,
                ),

                // ۳. کپسول نام تسک زیر دایره (دقیقاً زیر مرکز هندسی دایره هم‌تراز شده)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  top: showFullMenu && !provider.isQuickMenuExpanded ? 84 : 55,
                  right: _buttonsOnRight ? null : 0,
                  left: _buttonsOnRight ? 0 : null,
                  width: 156,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    opacity: showFullMenu && !provider.isQuickMenuExpanded
                        ? 1.0
                        : 0.0,
                    child: IgnorePointer(
                      ignoring: !showFullMenu || provider.isQuickMenuExpanded,
                      child: Center(child: taskCapsule),
                    ),
                  ),
                ),

                // ۴. پنل مشخصات تسک جاری (Quick Task Sheet) در صورت باز بودن
                if (provider.isQuickMenuExpanded)
                  Positioned(
                    top: 86,
                    left: 20,
                    right: 20,
                    child: const Center(child: QuickTaskSheet()),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// دکمه اصلی سوییچ دوگانه «کار» و «زندگی»
/// هیچ وقفه یا توقفی در کل سیستم وجود ندارد؛ فقط گذار از کار به زندگی یا بالعکس
class _RealmActionButton extends StatelessWidget {
  final bool isWork;
  final Color ringColor;
  final VoidCallback onPressed;

  const _RealmActionButton({
    required this.isWork,
    required this.ringColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isWork
          ? 'وقفه / ورود به وضعیت زندگی (استراحت)'
          : 'پایان استراحت و ورود به وضعیت کار',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ringColor,
              boxShadow: [
                BoxShadow(
                  color: ringColor.withAlpha(110),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Icon(
              isWork ? Icons.coffee_rounded : Icons.work_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniCircleButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback onPressed;

  const _MiniCircleButton({
    required this.tooltip,
    required this.icon,
    this.isActive = false,
    this.activeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final Color tint = activeColor ?? AppColors.focus;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? tint.withAlpha(50) : Colors.white.withAlpha(20),
              border: isActive
                  ? Border.all(color: tint.withAlpha(120), width: 1.0)
                  : null,
            ),
            child: Icon(
              icon,
              size: 14.5,
              color: isActive ? tint : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactRingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;

  _CompactRingPainter({
    required this.progress,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 5) / 2;

    // مسیر پس‌زمینه حلقه
    final trackPaint = Paint()
      ..color = ringColor.withAlpha(36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    // کمان پیشرفت زمان
    final progressPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;

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
  bool shouldRepaint(covariant _CompactRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor;
  }
}
