import '../core/constants.dart';

enum PomodoroMode { focus, shortBreak, longBreak, stopwatch }

enum TimerStatus { idle, running, paused, overtime }

enum AppRealm { work, life }

extension AppRealmX on AppRealm {
  String get dbValue => this == AppRealm.life ? 'life' : 'work';
  String get labelFa => this == AppRealm.life ? 'زندگی' : 'کار';

  static AppRealm fromDb(String? raw) {
    if (raw == 'life') return AppRealm.life;
    return AppRealm.work;
  }
}

enum ClockType { pomodoro, stopwatch }

extension ClockTypeX on ClockType {
  String get dbValue => this == ClockType.stopwatch ? 'stopwatch' : 'pomodoro';
  String get labelFa => this == ClockType.stopwatch ? 'کرنومتر' : 'پومودورو';

  static ClockType fromDb(String? raw) {
    if (raw == 'stopwatch') return ClockType.stopwatch;
    return ClockType.pomodoro;
  }
}

enum WindowPosture {
  dashboard,
  floatingCircle,
  edgeDockedLeft,
  edgeDockedRight,
}

class PomodoroState {
  final AppRealm realm;
  final ClockType clockType;
  final TimerStatus status;
  final int elapsedSeconds;
  final int targetSeconds;
  final int overtimeSeconds;
  final int lastNudgeAtOvertimeSeconds;

  // متغیرهای موتور Flowmodoro و بانک استراحت
  final int cycleWorkSeconds; // W_cycle
  final int earnedShortBreakSeconds; // B_earned
  final int breakDebtSeconds; // D_break
  final int cycleWorkTargetSeconds; // W_target (پیش‌فرض ۶۰۰۰ ثانیه = ۱۰۰ دقیقه)
  final bool isInLongBreak;

  final WindowPosture windowPosture;
  final String? activeRecordId;
  final String? activeOutcomeId;

  const PomodoroState({
    this.realm = AppRealm.work,
    this.clockType = ClockType.pomodoro,
    this.status = TimerStatus.idle,
    this.elapsedSeconds = 0,
    this.targetSeconds = AppDurations.defaultFocusSeconds,
    this.overtimeSeconds = 0,
    this.lastNudgeAtOvertimeSeconds = 0,
    this.cycleWorkSeconds = 0,
    this.earnedShortBreakSeconds = 0,
    this.breakDebtSeconds = 0,
    this.cycleWorkTargetSeconds = AppDurations.defaultCycleWorkTargetSeconds,
    this.isInLongBreak = false,
    this.windowPosture = WindowPosture.dashboard,
    this.activeRecordId,
    this.activeOutcomeId,
  });

  bool get isWork => realm == AppRealm.work;
  bool get isLife => realm == AppRealm.life;
  bool get isStopwatch => clockType == ClockType.stopwatch;
  bool get isPomodoro => clockType == ClockType.pomodoro;
  bool get isLifeSanctuaryLock => isLife && isInLongBreak;

  /// سازگاری با تعداد ست‌های معادل (بر مبنای ۲۵ دقیقه = ۱۵۰۰ ثانیه)
  int get completedSetsInCycle =>
      (cycleWorkSeconds ~/ AppDurations.defaultFocusSeconds);

  double get cycleProgress {
    if (cycleWorkTargetSeconds <= 0) return 0.0;
    return (cycleWorkSeconds / cycleWorkTargetSeconds).clamp(0.0, 1.0);
  }

  PomodoroMode get mode {
    if (isStopwatch) return PomodoroMode.stopwatch;
    if (isWork) return PomodoroMode.focus;
    return isInLongBreak ? PomodoroMode.longBreak : PomodoroMode.shortBreak;
  }

  bool get isOvertime =>
      status == TimerStatus.overtime ||
      (!isStopwatch && targetSeconds > 0 && elapsedSeconds > targetSeconds);

  int get remainingSeconds => targetSeconds - elapsedSeconds;

  double get progress {
    if (isStopwatch) return 1.0;
    if (targetSeconds <= 0) return 0.0;
    return (elapsedSeconds / targetSeconds).clamp(0.0, 1.0);
  }

  String get formattedDisplayTime {
    if (isStopwatch) {
      final int h = elapsedSeconds ~/ 3600;
      final int m = (elapsedSeconds % 3600) ~/ 60;
      final int s = elapsedSeconds % 60;
      if (h > 0) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      }
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    if (isOvertime) {
      final int extra = (elapsedSeconds - targetSeconds).abs();
      final int h = extra ~/ 3600;
      final int m = (extra % 3600) ~/ 60;
      final int s = extra % 60;
      if (h > 0) {
        return '-${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      }
      return '-${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else {
      final int rem = remainingSeconds < 0 ? 0 : remainingSeconds;
      final int h = rem ~/ 3600;
      final int m = (rem % 3600) ~/ 60;
      final int s = rem % 60;
      if (h > 0) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      }
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
  }

  PomodoroState copyWith({
    AppRealm? realm,
    ClockType? clockType,
    TimerStatus? status,
    int? elapsedSeconds,
    int? targetSeconds,
    int? overtimeSeconds,
    int? lastNudgeAtOvertimeSeconds,
    int? cycleWorkSeconds,
    int? earnedShortBreakSeconds,
    int? breakDebtSeconds,
    int? cycleWorkTargetSeconds,
    bool? isInLongBreak,
    WindowPosture? windowPosture,
    String? activeRecordId,
    bool clearActiveRecord = false,
    String? activeOutcomeId,
    bool clearActiveOutcome = false,
  }) {
    return PomodoroState(
      realm: realm ?? this.realm,
      clockType: clockType ?? this.clockType,
      status: status ?? this.status,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      targetSeconds: targetSeconds ?? this.targetSeconds,
      overtimeSeconds: overtimeSeconds ?? this.overtimeSeconds,
      lastNudgeAtOvertimeSeconds:
          lastNudgeAtOvertimeSeconds ?? this.lastNudgeAtOvertimeSeconds,
      cycleWorkSeconds: cycleWorkSeconds ?? this.cycleWorkSeconds,
      earnedShortBreakSeconds:
          earnedShortBreakSeconds ?? this.earnedShortBreakSeconds,
      breakDebtSeconds: breakDebtSeconds ?? this.breakDebtSeconds,
      cycleWorkTargetSeconds:
          cycleWorkTargetSeconds ?? this.cycleWorkTargetSeconds,
      isInLongBreak: isInLongBreak ?? this.isInLongBreak,
      windowPosture: windowPosture ?? this.windowPosture,
      activeRecordId:
          clearActiveRecord ? null : (activeRecordId ?? this.activeRecordId),
      activeOutcomeId: clearActiveOutcome
          ? null
          : (activeOutcomeId ?? this.activeOutcomeId),
    );
  }
}
