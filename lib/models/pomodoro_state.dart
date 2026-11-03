enum PomodoroMode { focus, shortBreak, longBreak, stopwatch }

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
    this.targetSeconds = 1500,
    this.completedSetsInCycle = 0,
    this.overtimeSeconds = 0,
    this.lastNudgeAtOvertimeSeconds = 0,
    this.windowPosture = WindowPosture.dashboard,
    this.activeTaskId,
  });

  bool get isStopwatch => mode == PomodoroMode.stopwatch;
  bool get isLifeSanctuaryLock => mode == PomodoroMode.longBreak;
  bool get isOvertime =>
      status == TimerStatus.overtime ||
      (mode != PomodoroMode.stopwatch && elapsedSeconds > targetSeconds);
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
