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
import '../shared/work_note_dialog.dart';
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
  Timer? _hoverDebounceTimer;

  @override
  void initState() {
    super.initState();
    if (PlatformHelper.isDesktop) {
      windowManager.addListener(this);
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
    _hoverDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      final provider = context.read<AppStateProvider>();
      if (mounted &&
          _isHovered &&
          !provider.isQuickMenuExpanded &&
          !provider.isWorkNoteOpen) {
        setState(() => _isHovered = false);
      }
    });
  }

  Color _resolveRingColor(PomodoroState state, {bool isGolden = false}) {
    // اضافه‌زمان (چه در کار و چه در استراحت/زندگی) با رنگ هشدار نارنجی-قرمز متمایز می‌شود
    if (state.isOvertime) {
      return AppColors.overtime;
    }
    if (state.isLife) {
      return AppColors.lifeGreen;
    }
    if (state.isStopwatch) {
      return AppColors.stopwatch;
    }
    if (isGolden) {
      return AppColors.golden;
    }
    return AppColors.workBlue;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppStateProvider, MusicPlayerService>(
      builder: (context, provider, music, _) {
        final state = provider.pomodoroState;
        final active = provider.activeRecord;
        final activeOutcome = provider.activeOutcome;
        final isGolden = provider.isGoldenScheduledTaskActive;
        final ringColor = _resolveRingColor(state, isGolden: isGolden);
        final bool showFullMenu = _isHovered || provider.isQuickMenuExpanded;

        if (provider.isWorkNoteOpen) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: SizedBox.expand(),
          );
        }

        // ۱. حالت نوار کناری چسبیده به لبه مانیتور
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

        const double circleSize = PlatformHelper.baseCircleSize;
        final double windowW = provider.isQuickMenuExpanded
            ? PlatformHelper.expandedSheetWidth
            : PlatformHelper.hoveredWidth;

        final double centerX = windowW / 2.0;
        const double centerY = 75.0;

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
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: CustomPaint(
                      painter: _CompactRingPainter(
                        progress: state.isOvertime || state.isStopwatch
                            ? 1.0
                            : state.progress,
                        ringColor: ringColor,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.formattedDisplayTime,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: state.isOvertime ||
                                  (state.isStopwatch &&
                                      state.elapsedSeconds >= 3600)
                              ? 13.5
                              : 16.0,
                          fontWeight: FontWeight.w700,
                          color: state.isOvertime
                              ? AppColors.overtime
                              : (state.isLife
                                  ? AppColors.lifeGreen
                                  : (isGolden
                                      ? AppColors.golden
                                      : Colors.white)),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      isGolden
                          ? const Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: AppColors.golden,
                            )
                          : Container(
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

        final realmAccent =
            state.isLife ? AppColors.lifeGreen : AppColors.workBlue;

        final buttonWorkNote = _HaloButton(
          tooltip: 'ثبت یادداشت حین فعالیت (اتصال سه‌گانه)',
          icon: Icons.edit_note_rounded,
          activeColor: realmAccent,
          onPressed: () => WorkNoteDialog.openStandalone(context),
          onMouseEnter: _onMouseEnter,
          onMouseExit: _onMouseExit,
        );

        final buttonTune = _HaloButton(
          tooltip: 'پنل سریع کارهای باز و بانک استراحت',
          icon: provider.isQuickMenuExpanded
              ? Icons.expand_less_rounded
              : Icons.tune_rounded,
          isActive: provider.isQuickMenuExpanded,
          activeColor: realmAccent,
          onPressed: () =>
              provider.toggleQuickMenuExpanded(!provider.isQuickMenuExpanded),
          onMouseEnter: _onMouseEnter,
          onMouseExit: _onMouseExit,
        );

        final buttonFullscreen = _HaloButton(
          tooltip: 'داشبورد کامل',
          icon: Icons.open_in_full_rounded,
          onPressed: () => provider.setWindowPosture(WindowPosture.dashboard),
          onMouseEnter: _onMouseEnter,
          onMouseExit: _onMouseExit,
        );

        final buttonGoldenStar = _HaloButton(
          tooltip: isGolden
              ? 'تسک طلایی فعال (مطابق برنامه)'
              : 'فعال‌سازی تسک طلایی',
          icon: Icons.star_rounded,
          isActive: isGolden,
          activeColor: AppColors.golden,
          onPressed: () => provider.toggleGoldenScheduledTask(),
          onMouseEnter: _onMouseEnter,
          onMouseExit: _onMouseExit,
        );

        final buttonStopwatch = _HaloButton(
          tooltip: state.isStopwatch
              ? 'سوییچ به پومودورو Flowmodoro'
              : 'سوییچ به کرنومتر آزاد',
          icon: state.isStopwatch
              ? Icons.timelapse_rounded
              : Icons.timer_outlined,
          isActive: state.isStopwatch,
          activeColor: AppColors.stopwatch,
          onPressed: provider.toggleClockType,
          onMouseEnter: _onMouseEnter,
          onMouseExit: _onMouseExit,
        );

        final buttonPin = _HaloButton(
          tooltip: provider.isPinned
              ? 'ویجت پین است (همیشه رو)'
              : 'پین کردن ویجت (همیشه رو)',
          icon: provider.isPinned
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          isActive: provider.isPinned,
          activeColor: realmAccent,
          onPressed: provider.togglePin,
          onMouseEnter: _onMouseEnter,
          onMouseExit: _onMouseExit,
        );

        final buttonRealmAction = _HaloButton(
          tooltip: state.isWork
              ? 'ورود به قلمرو زندگی (استراحت متناسب)'
              : 'بازگشت به قلمرو کار',
          icon: state.isWork ? Icons.coffee_rounded : Icons.work_rounded,
          iconColor: Colors.white,
          backgroundColor: state.isWork
              ? AppColors.lifeGreen
              : (isGolden ? AppColors.golden : AppColors.workBlue),
          onPressed: provider.toggleWorkLife,
          onMouseEnter: _onMouseEnter,
          onMouseExit: _onMouseExit,
        );

        final List<({Widget widget, double angleDeg})> haloButtons = [
          (widget: buttonWorkNote, angleDeg: -102.0),
          (widget: buttonTune, angleDeg: -68.0),
          (widget: buttonFullscreen, angleDeg: -34.0),
          (widget: buttonGoldenStar, angleDeg: 0.0),
          (widget: buttonStopwatch, angleDeg: 34.0),
          (widget: buttonPin, angleDeg: 68.0),
          (widget: buttonRealmAction, angleDeg: 102.0),
        ];

        const double haloOrbitRadius = 55.0;

        final String capsuleText = activeOutcome?.title ??
            active?.titleSnapshot ??
            (state.isLife ? 'زندگی / استراحت' : 'تسک جدید...');

        final taskCapsule = MouseRegion(
          onEnter: (_) => _onMouseEnter(),
          onExit: (_) => _onMouseExit(),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              provider.toggleQuickMenuExpanded(!provider.isQuickMenuExpanded);
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 175),
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 4.5),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B).withAlpha(245),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isGolden
                      ? AppColors.golden.withAlpha(120)
                      : (state.isLife
                          ? AppColors.lifeGreen.withAlpha(100)
                          : Colors.white.withAlpha(28)),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(120),
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
                      capsuleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        color: state.isLife
                            ? AppColors.lifeGreen
                            : (isGolden
                                ? AppColors.golden
                                : (active?.isUntitledDraft == true
                                    ? AppColors.draftWarning
                                    : AppColors.textPrimary)),
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
                            ? realmAccent
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
                Positioned(
                  top: centerY - (haloOrbitRadius + 18.0),
                  left: centerX - (haloOrbitRadius + 22.0),
                  width: (haloOrbitRadius + 22.0) * 2,
                  height: (haloOrbitRadius + 18.0) * 2 + 30.0,
                  child: MouseRegion(
                    opaque: false,
                    onEnter: (_) => _onMouseEnter(),
                    onExit: (_) => _onMouseExit(),
                  ),
                ),

                ...haloButtons.map((item) {
                  final rad = item.angleDeg * (math.pi / 180.0);
                  final targetX =
                      centerX + (haloOrbitRadius * math.sin(rad)) - 13.0;
                  final targetY =
                      centerY - (haloOrbitRadius * math.cos(rad)) - 13.0;

                  final collapsedX = centerX - 13.0;
                  final collapsedY = centerY - 13.0;

                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: showFullMenu ? targetX : collapsedX,
                    top: showFullMenu ? targetY : collapsedY,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: showFullMenu ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !showFullMenu,
                        child: item.widget,
                      ),
                    ),
                  );
                }),

                Positioned(
                  top: centerY - (circleSize / 2.0),
                  left: centerX - (circleSize / 2.0),
                  child: timerCircle,
                ),

                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  top: showFullMenu && !provider.isQuickMenuExpanded
                      ? (centerY + (circleSize / 2.0) + 7.0)
                      : centerY,
                  left: centerX - (175.0 / 2.0),
                  width: 175,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    opacity: showFullMenu && !provider.isQuickMenuExpanded
                        ? 1.0
                        : 0.0,
                    child: IgnorePointer(
                      ignoring:
                          !showFullMenu || provider.isQuickMenuExpanded,
                      child: Center(child: taskCapsule),
                    ),
                  ),
                ),

                if (provider.isQuickMenuExpanded)
                  const Positioned(
                    top: 86,
                    left: 14,
                    right: 14,
                    bottom: 8,
                    child: QuickTaskSheet(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HaloButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool isActive;
  final Color? activeColor;
  final Color? iconColor;
  final Color? backgroundColor;
  final VoidCallback onPressed;
  final VoidCallback? onMouseEnter;
  final VoidCallback? onMouseExit;

  const _HaloButton({
    required this.tooltip,
    required this.icon,
    this.isActive = false,
    this.activeColor,
    this.iconColor,
    this.backgroundColor,
    required this.onPressed,
    this.onMouseEnter,
    this.onMouseExit,
  });

  @override
  Widget build(BuildContext context) {
    final Color tint = activeColor ?? AppColors.workBlue;
    final Color bg = backgroundColor ??
        (isActive
            ? tint.withAlpha(60)
            : const Color(0xFF1E1E22).withAlpha(240));

    final Color fg = iconColor ?? (isActive ? tint : AppColors.textPrimary);

    return MouseRegion(
      onEnter: (_) => onMouseEnter?.call(),
      onExit: (_) => onMouseExit?.call(),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                border: Border.all(
                  color: isActive
                      ? tint.withAlpha(150)
                      : Colors.white.withAlpha(25),
                  width: 0.9,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(120),
                    blurRadius: 5,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 13.0,
                color: fg,
              ),
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
    final radius = (size.width - 4.5) / 2;

    final trackPaint = Paint()
      ..color = ringColor.withAlpha(36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final progressPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

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
