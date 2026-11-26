import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/date_time_utils.dart';
import '../../core/platform_helper.dart';
import '../../models/outcome_item.dart';
import '../../models/pomodoro_state.dart';
import '../../providers/app_state_provider.dart';
import '../../services/nature_ambience_service.dart';
import 'searchable_task_input.dart';

/// ویجت اسلایدشوی تمام‌صفحه طبیعت، صدای آبشار و تایمر استراحت برای حالت زندگی
class NatureSlideshowOverlay extends StatefulWidget {
  const NatureSlideshowOverlay({super.key});

  @override
  State<NatureSlideshowOverlay> createState() => _NatureSlideshowOverlayState();
}

class _NatureSlideshowOverlayState extends State<NatureSlideshowOverlay> {
  static const List<String> _natureImages = [
    'https://images.unsplash.com/photo-1511497584788-87676104235f?q=80&w=1920&auto=format&fit=crop', // جنگل مه‌آلود
    'https://images.unsplash.com/photo-1432405972618-c60b0225b8f9?q=80&w=1920&auto=format&fit=crop', // آبشار آرامش‌بخش
    'https://images.unsplash.com/photo-1448375240586-882707db888b?q=80&w=1920&auto=format&fit=crop', // سایبان سبز درختان
    'https://images.unsplash.com/photo-1506744038136-46273834b3fb?q=80&w=1920&auto=format&fit=crop', // طبیعت و آبشار
    'https://images.unsplash.com/photo-1518457607834-6e8d80c183c5?q=80&w=1920&auto=format&fit=crop', // دریاچه زمردین و کاج
    'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?q=80&w=1920&auto=format&fit=crop', // تپه‌های مه‌آلود سبز
  ];

  static const List<List<Color>> _fallbackGradients = [
    [Color(0xFF041C15), Color(0xFF0F382A), Color(0xFF061812)],
    [Color(0xFF062326), Color(0xFF0E4549), Color(0xFF04171A)],
    [Color(0xFF142416), Color(0xFF26472A), Color(0xFF0E1A0F)],
    [Color(0xFF0B2129), Color(0xFF13454B), Color(0xFF07191E)],
    [Color(0xFF0A2B1D), Color(0xFF185339), Color(0xFF071C13)],
    [Color(0xFF152A20), Color(0xFF244A39), Color(0xFF0D1E16)],
  ];

  int _currentIndex = 0;
  Timer? _slideshowTimer;
  bool _isPaused = false;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _restTaskController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _focusNode.requestFocus();
      final isTestMode = context.read<AppStateProvider>().isTestMode;
      if (PlatformHelper.isDesktop && !isTestMode) {
        await PlatformHelper.enterLifeSlideshowMode();
      }
    });
  }

  void _startTimer() {
    _slideshowTimer?.cancel();
    _slideshowTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!_isPaused && mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _natureImages.length;
        });
      }
    });
  }

  void _nextSlide() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % _natureImages.length;
    });
    _startTimer();
  }

  void _prevSlide() {
    setState(() {
      _currentIndex =
          (_currentIndex - 1 + _natureImages.length) % _natureImages.length;
    });
    _startTimer();
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _focusNode.dispose();
    _restTaskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final ambience = NatureAmbienceService.instance;
    final state = provider.pomodoroState;
    final currentImageUrl = _natureImages[_currentIndex];
    final currentGradient =
        _fallbackGradients[_currentIndex % _fallbackGradients.length];

    // زمان‌بندی تایمر
    final targetSec = provider.activeOrPreviewBreakTargetSeconds;
    final elapsedSec = state.elapsedSeconds;
    final remainingSec = (targetSec - elapsedSec).clamp(0, 86400);
    final displaySec = state.isPomodoro ? remainingSec : elapsedSec;
    final formattedTime = DateTimeUtils.formatDurationHms(displaySec);

    final double progress = targetSec > 0
        ? (elapsedSec / targetSec).clamp(0.0, 1.0)
        : (state.earnedShortBreakSeconds > 0
            ? (state.earnedShortBreakSeconds / 1800).clamp(0.0, 1.0)
            : 0.5);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          provider.dismissNatureSlideshow();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ۱. تصویر پس‌زمینه اسلایدشو با ترنزیشن نرم Fade
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 1400),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: Container(
                key: ValueKey<int>(_currentIndex),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: currentGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Image.network(
                  currentImageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (ctx, err, stack) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 1.2,
                          colors: currentGradient,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.eco_rounded,
                          size: 110,
                          color: AppColors.lifeGreen.withAlpha(40),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ۲. لایه محافظ تیره جهت خوانایی کامل تایمر و نوشته‌ها
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(160),
                    Colors.black.withAlpha(90),
                    Colors.black.withAlpha(190),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),

            // ۳. نوار بالای صفحه: عنوان، کنترل‌های صدا و دکمه بستن
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 620;
                      return Row(
                        children: [
                          // نشان قلمرو زندگی
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.lifeGreen.withAlpha(45),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppColors.lifeGreen.withAlpha(120)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.spa_rounded,
                                    size: 15, color: AppColors.lifeGreen),
                                SizedBox(width: 5),
                                Text(
                                  'قلمرو زندگی و استراحت',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.lifeGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),

                          if (!isNarrow) ...[
                            // کنترل‌های اسلایدشو
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(130),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.skip_previous_rounded,
                                        size: 18, color: Colors.white70),
                                    tooltip: 'تصویر قبلی',
                                    onPressed: _prevSlide,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isPaused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                      size: 18,
                                      color: Colors.white70,
                                    ),
                                    tooltip: _isPaused
                                        ? 'ادامه اسلایدشو'
                                        : 'توقف اسلایدشو',
                                    onPressed: _togglePause,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.skip_next_rounded,
                                        size: 18, color: Colors.white70),
                                    tooltip: 'تصویر بعدی',
                                    onPressed: _nextSlide,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],

                          // کنترل صدای آبشار و طبیعت
                          ListenableBuilder(
                            listenable: ambience,
                            builder: (ctx, _) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(130),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: ambience.isPlaying && !ambience.isMuted
                                        ? AppColors.lifeGreen.withAlpha(160)
                                        : Colors.white24,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: ambience.isMuted
                                          ? 'فعال‌سازی صدای آبشار'
                                          : 'قطع صدای آبشار',
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: ambience.toggleMute,
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(
                                            ambience.isMuted
                                                ? Icons.volume_off_rounded
                                                : Icons.water_drop_rounded,
                                            size: 18,
                                            color: ambience.isMuted
                                                ? Colors.white54
                                                : AppColors.lifeGreen,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (!isNarrow) ...[
                                      const SizedBox(width: 4),
                                      SizedBox(
                                        width: 70,
                                        child: SliderTheme(
                                          data: SliderTheme.of(ctx).copyWith(
                                            thumbShape: const RoundSliderThumbShape(
                                                enabledThumbRadius: 5),
                                            trackHeight: 2.5,
                                            activeTrackColor: AppColors.lifeGreen,
                                            inactiveTrackColor: Colors.white24,
                                            thumbColor: AppColors.lifeGreen,
                                          ),
                                          child: Slider(
                                            value: ambience.isMuted
                                                ? 0
                                                : ambience.volume,
                                            onChanged: (val) =>
                                                ambience.setVolume(val),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 10),

                          // دکمه بستن اسلایدشو در بالا ("دکمه بستن هم اون بالا باشه")
                          Tooltip(
                            message: 'بستن اسلایدشو (Esc)',
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: provider.dismissNatureSlideshow,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(25),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white38),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // ۴. کارت تایمر مرکزی شیشه‌ای (Glassmorphic)
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    constraints:
                        const BoxConstraints(maxWidth: 400, maxHeight: 640),
                    margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(140),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: AppColors.lifeGreen.withAlpha(80),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.lifeGreen.withAlpha(30),
                          blurRadius: 36,
                          spreadRadius: 4,
                        ),
                        const BoxShadow(
                          color: Colors.black87,
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    // عنوان و شرح وضعیت
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.air_rounded,
                            size: 18, color: AppColors.lifeGreen),
                        const SizedBox(width: 8),
                        Text(
                          state.isInLongBreak
                              ? 'استراحت طولانی و ریکاوری'
                              : 'استراحت و تجدید انرژی',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // دایره پیشرفت تایمر
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 170,
                            height: 170,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 7,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.lifeGreen),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formattedTime,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 38,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                state.isPomodoro
                                    ? 'زمان باقی‌مانده'
                                    : 'سپری‌شده',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // توضیحات بانک استراحت
                    Text(
                      provider.breakTargetExplanationFa,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // انتخاب سریع کار برای بازگشت به قلمرو کار و شروع ضبط
                    SearchableTaskInput(
                      controller: _restTaskController,
                      openOutcomes:
                          provider.getOpenOutcomes(realm: AppRealm.work),
                      completedOutcomes:
                          provider.getCompletedOutcomes(realm: AppRealm.work),
                      historicalRecords: provider.timeRecords
                          .where((r) =>
                              r.realm == AppRealm.work && !r.isUntitledDraft)
                          .toList(),
                      projects: provider.projects,
                      accentColor: AppColors.workBlue,
                      hintText:
                          'انتخاب کار قبلی یا باز برای بازگشت سریع به کار...',
                      onSelectOutcome: (OutcomeItem outcome) async {
                        await provider.dismissNatureSlideshow();
                        await provider.startOrSwitchToOutcome(outcome);
                      },
                      onSelectHistoricalRecord: (record) async {
                        await provider.dismissNatureSlideshow();
                        await provider.startOrSwitchToHistoricalRecord(record);
                      },
                      onCreateNew: (newTitle) async {
                        await provider.dismissNatureSlideshow();
                        await provider.createAndStartOutcome(
                          realm: AppRealm.work,
                          title: newTitle,
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // دکمه بازگشت به کار و ثبت برش
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.workBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                        ),
                        icon: const Icon(Icons.work_rounded, size: 17),
                        label: const Text(
                          'پایان استراحت و شروع قلمرو کار',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          await provider.dismissNatureSlideshow();
                          await provider.switchRealm(AppRealm.work);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }
}
