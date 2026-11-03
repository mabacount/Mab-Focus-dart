// وضعیت لحظه‌ای تایمر پومودورو، اضافه‌کاری منفی و حالت پنجره
enum PomodoroMode { focus, shortBreak, longBreak }

enum TimerStatus { idle, running, paused, overtime }

enum WindowPosture {
  dashboard,
  floatingCircle,
  edgeDockedLeft,
  edgeDockedRight
}

class PomodoroState {
  final PomodoroMode mode;
  final TimerStatus status;
  final int elapsedSeconds;
  final int targetSeconds;
  final int completedSetsInCycle;
  final int overtimeSeconds;
  final int lastNudgeAtOvertimeSeconds;
  final WindowPosture windowPosture;
  final String? activeTaskId;

  const PomodoroState({
    this.mode = PomodoroMode.focus,
    this.status = TimerStatus.idle,
    this.elapsedSeconds = 0,
    this.targetSeconds = 1500, // 25 دقیقه
    this.completedSetsInCycle = 0,
    this.overtimeSeconds = 0,
    this.lastNudgeAtOvertimeSeconds = 0,
    this.windowPosture = WindowPosture.dashboard,
    this.activeTaskId,
  });

  int get remainingSeconds => targetSeconds - elapsedSeconds;
  bool get isOvertime =>
      status == TimerStatus.overtime || elapsedSeconds > targetSeconds;

  double get progress {
    if (targetSeconds <= 0) return 0.0;
    final double p = elapsedSeconds / targetSeconds;
    return p.clamp(0.0, 1.0);
  }

  String get formattedDisplayTime {
    if (isOvertime) {
      final int extra = (elapsedSeconds - targetSeconds).abs();
      final int m = extra ~/ 60;
      final int s = extra % 60;
      return '-${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else {
      final int rem = remainingSeconds < 0 ? 0 : remainingSeconds;
      final int m = rem ~/ 60;
      final int s = rem % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
  }

  PomodoroState copyWith({
    PomodoroMode? mode,
    TimerStatus? status,
    int? elapsedSeconds,
    int? targetSeconds,
    int? completedSetsInCycle,
    int? overtimeSeconds,
    int? lastNudgeAtOvertimeSeconds,
    WindowPosture? windowPosture,
    String? activeTaskId,
  }) {
    return PomodoroState(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      targetSeconds: targetSeconds ?? this.targetSeconds,
      completedSetsInCycle: completedSetsInCycle ?? this.completedSetsInCycle,
      overtimeSeconds: overtimeSeconds ?? this.overtimeSeconds,
      lastNudgeAtOvertimeSeconds:
          lastNudgeAtOvertimeSeconds ?? this.lastNudgeAtOvertimeSeconds,
      windowPosture: windowPosture ?? this.windowPosture,
      activeTaskId: activeTaskId ?? this.activeTaskId,
    );
  }
}
