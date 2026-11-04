import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../core/platform_helper.dart';
import '../models/phase_tag.dart';
import '../models/pomodoro_state.dart';
import '../models/project_node.dart';
import '../models/task_log_entry.dart';
import '../models/scheduled_block.dart';
import '../models/music_track.dart';
import '../services/database_service.dart';
import '../services/excel_export_service.dart';
import '../services/gcal_sync_service.dart';
import '../services/sound_service.dart';
import '../services/txt_logger_service.dart';
import '../services/music_player_service.dart';

class AppStateProvider extends ChangeNotifier {
  final Uuid _uuid = const Uuid();

  PomodoroState _pomodoroState = const PomodoroState();
  TaskLogEntry? _activeTaskLog;
  int _activeTaskElapsedSeconds = 0;

  DateTime? _phaseStartedAt;
  int _accumulatedPhaseSeconds = 0;
  DateTime? _taskSliceStartedAt;
  int _accumulatedTaskSeconds = 0;
  Timer? _ticker;

  List<ProjectNode> _projects = [];
  List<PhaseTag> _phaseTags = [];
  List<TaskLogEntry> _taskLogs = [];
  List<ScheduledBlock> _scheduledBlocks = [];
  List<MusicPlaylist> _playlists = [];

  int _focusDurationMinutes = 25;
  int _shortBreakDurationMinutes = 5;
  int _longBreakDurationMinutes = 60;
  String _txtLogPath = '';
  String _gcalToken = '';
  bool _isQuickMenuExpanded = false;
  String? _lastErgonomicNudgeMessage;
  bool _isPinned = true;

  // ==================== Getters ====================

  PomodoroState get pomodoroState => _pomodoroState;
  TaskLogEntry? get activeTaskLog => _activeTaskLog;
  int get activeTaskElapsedSeconds => _activeTaskElapsedSeconds;
  List<ProjectNode> get projects => _projects;
  List<ProjectNode> get macroProjects =>
      _projects.where((p) => p.isMacro && !p.isArchived).toList();
  List<PhaseTag> get phaseTags => _phaseTags.where((t) => !t.archived).toList();
  List<TaskLogEntry> get taskLogs => _taskLogs;
  List<ScheduledBlock> get scheduledBlocks => _scheduledBlocks;
  List<MusicPlaylist> get playlists => _playlists;

  List<TaskLogEntry> get openWorkTasks => _taskLogs
      .where((l) => !l.isCompleted && l.isWork && !l.isUntitledDraft)
      .toList();

  List<TaskLogEntry> get untitledDraftLogs => _taskLogs
      .where((log) => log.isUntitledDraft && log.id != _activeTaskLog?.id)
      .toList();
  final String _gcalSyncLevel = 'task';
  String get gcalSyncLevel => _gcalSyncLevel;

  int get focusDurationMinutes => _focusDurationMinutes;
  int get shortBreakDurationMinutes => _shortBreakDurationMinutes;
  int get longBreakDurationMinutes => _longBreakDurationMinutes;
  String get txtLogPath => _txtLogPath;
  String get gcalToken => _gcalToken;
  bool get isQuickMenuExpanded => _isQuickMenuExpanded;
  String? get lastErgonomicNudgeMessage => _lastErgonomicNudgeMessage;
  bool get isPinned => _isPinned;

  List<ProjectNode> getSubProjects(String? macroProjectId) {
    if (macroProjectId == null) return [];
    return _projects
        .where((p) => p.parentId == macroProjectId && !p.isArchived)
        .toList();
  }

  ProjectNode? getProjectById(String? id) {
    if (id == null) return null;
    for (final p in _projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  PhaseTag? getPhaseTagById(String id) {
    for (final t in _phaseTags) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ==================== مقداردهی اولیه ====================

  Future<void> initialize() async {
    await _loadSettings();
    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
  }

  Future<void> _loadSettings() async {
    final db = DatabaseService.instance;
    final focusStr = await db.getSetting(AppDefaults.settingKeyFocusDuration,
        defaultValue: '25');
    final shortStr = await db.getSetting(
        AppDefaults.settingKeyShortBreakDuration,
        defaultValue: '5');
    final longStr = await db.getSetting(AppDefaults.settingKeyLongBreakDuration,
        defaultValue: '60');
    final musicBreakStr = await db.getSetting(
        AppDefaults.settingKeyPlayMusicDuringBreaks,
        defaultValue: '0');
    final pinnedStr = await db.getSetting(
        AppDefaults.settingKeyWidgetPinned,
        defaultValue: '1');

    _focusDurationMinutes = int.tryParse(focusStr ?? '25') ?? 25;
    _shortBreakDurationMinutes = int.tryParse(shortStr ?? '5') ?? 5;
    _longBreakDurationMinutes = int.tryParse(longStr ?? '60') ?? 60;
    _isPinned = (pinnedStr ?? '1') == '1';
    MusicPlayerService.instance.setPlayDuringBreaks(musicBreakStr == '1');

    _txtLogPath = await TxtLoggerService.instance.getEffectiveLogFilePath();
    _gcalToken = await db.getSetting(AppDefaults.settingKeyGCalToken,
            defaultValue: '') ??
        '';

    if (_pomodoroState.status == TimerStatus.idle) {
      _pomodoroState = _pomodoroState.copyWith(
        targetSeconds: _focusDurationMinutes * 60,
      );
    }
  }

  Future<void> refreshAllData() async {
    final db = DatabaseService.instance;
    _projects = await db.getProjects(includeArchived: true);
    _phaseTags = await db.getPhaseTags(includeArchived: true);
    _taskLogs = await db.getAllTaskLogs();
    _playlists = await db.getAllMusicPlaylists();

    final now = DateTime.now();
    final startRange = now.subtract(const Duration(days: 14));
    final endRange = now.add(const Duration(days: 14));
    _scheduledBlocks = await db.getScheduledBlocksInRange(startRange, endRange);

    notifyListeners();
  }

  // ==================== موتور زمان‌سنج بر پایه Timestamp-Delta ====================

  void _ensureTickerRunning() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (_pomodoroState.status != TimerStatus.running &&
        _pomodoroState.status != TimerStatus.overtime) {
      return;
    }

    final now = DateTime.now();
    final int currentPhaseDelta = _phaseStartedAt != null
        ? now.difference(_phaseStartedAt!).inSeconds
        : 0;
    final int totalPhaseElapsed = _accumulatedPhaseSeconds + currentPhaseDelta;

    if (_activeTaskLog != null && _taskSliceStartedAt != null) {
      final int currentTaskDelta =
          now.difference(_taskSliceStartedAt!).inSeconds;
      _activeTaskElapsedSeconds = _accumulatedTaskSeconds + currentTaskDelta;
    }

    // حالت ۱: کرنومتر آزاد (Stopwatch)
    if (_pomodoroState.isStopwatch) {
      _pomodoroState = _pomodoroState.copyWith(
        elapsedSeconds: totalPhaseElapsed,
      );
      notifyListeners();
      return;
    }

    // حالت ۲: پومودورو یا استراحت
    TimerStatus newStatus = _pomodoroState.status;
    int overtimeSec = 0;
    int lastNudge = _pomodoroState.lastNudgeAtOvertimeSeconds;

    if (totalPhaseElapsed >= _pomodoroState.targetSeconds) {
      overtimeSec = totalPhaseElapsed - _pomodoroState.targetSeconds;
      if (_pomodoroState.status != TimerStatus.overtime) {
        newStatus = TimerStatus.overtime;
        SoundService.instance.playCompletionChime();
      }

      if (overtimeSec - lastNudge >=
          AppDurations.overtimeNudgeIntervalSeconds) {
        lastNudge = overtimeSec;
        SoundService.instance.playOvertimeNudge();
        _lastErgonomicNudgeMessage =
            '۵ دقیقه از زمان پومودورو گذشته است؛ آیا مایل به استراحت هستید؟';
      }
    }

    _pomodoroState = _pomodoroState.copyWith(
      status: newStatus,
      elapsedSeconds: totalPhaseElapsed,
      overtimeSeconds: overtimeSec,
      lastNudgeAtOvertimeSeconds: lastNudge,
    );

    notifyListeners();
  }

  void clearErgonomicNudge() {
    _lastErgonomicNudgeMessage = null;
    notifyListeners();
  }

  // ==================== کنترل دوگانه کار و زندگی (Work vs Life) ====================

  Future<void> togglePin() async {
    _isPinned = !_isPinned;
    await DatabaseService.instance.setSetting(
      AppDefaults.settingKeyWidgetPinned,
      _isPinned ? '1' : '0',
    );
    await PlatformHelper.setPinned(_isPinned);
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    // در این سیستم توقف/وقفه انجمادی نداریم: بین کار و زندگی سوییچ می‌شود
    await toggleWorkLife();
  }

  /// سوییچ مستقیم و پیوسته بین قلمرو «کار» و قلمرو «زندگی»
  Future<void> toggleWorkLife() async {
    final now = DateTime.now();

    if (_pomodoroState.isWork) {
      // از کار به زندگی
      await _closeAndPersistActiveTask();

      final int nextSets = _pomodoroState.completedSetsInCycle + 1;
      final bool isLongBreak =
          (nextSets % AppDurations.setsPerCycle) == 0 && nextSets > 0;
      final int breakSec = isLongBreak
          ? _longBreakDurationMinutes * 60
          : _shortBreakDurationMinutes * 60;

      final breakEntry = TaskLogEntry(
        id: _uuid.v4(),
        groupId: _uuid.v4(),
        entryType: _pomodoroState.isStopwatch
            ? 'stopwatch'
            : (isLongBreak ? 'long_break' : 'short_break'),
        title: _pomodoroState.isStopwatch
            ? 'کرنومتر زندگی و استراحت آزاد'
            : (isLongBreak ? 'استراحت طولانی (زندگی)' : 'استراحت کوتاه‌مدت'),
        isUntitledDraft: false,
        startTime: now,
      );
      await DatabaseService.instance.insertTaskLog(breakEntry);
      _activeTaskLog = breakEntry;
      _accumulatedTaskSeconds = 0;
      _activeTaskElapsedSeconds = 0;
      _taskSliceStartedAt = now;

      _accumulatedPhaseSeconds = 0;
      _phaseStartedAt = now;
      _lastErgonomicNudgeMessage = null;

      _pomodoroState = _pomodoroState.copyWith(
        realm: AppRealm.life,
        status: TimerStatus.running,
        elapsedSeconds: 0,
        targetSeconds: _pomodoroState.isStopwatch ? 0 : breakSec,
        completedSetsInCycle: nextSets,
        overtimeSeconds: 0,
        lastNudgeAtOvertimeSeconds: 0,
        activeTaskId: breakEntry.id,
      );

      MusicPlayerService.instance.onPomodoroModeChanged(_pomodoroState.mode);
      _ensureTickerRunning();
      await refreshAllData();
    } else {
      // از زندگی به کار
      await _closeAndPersistActiveTask();

      _accumulatedPhaseSeconds = 0;
      _phaseStartedAt = now;
      _lastErgonomicNudgeMessage = null;

      final workEntry = TaskLogEntry(
        id: _uuid.v4(),
        groupId: _uuid.v4(),
        entryType: _pomodoroState.isStopwatch ? 'stopwatch' : 'work',
        title: AppDefaults.untitledTaskTitle,
        isUntitledDraft: true,
        startTime: now,
        pomodoroSetIndex:
            (_pomodoroState.completedSetsInCycle % AppDurations.setsPerCycle) + 1,
      );
      await DatabaseService.instance.insertTaskLog(workEntry);
      _activeTaskLog = workEntry;
      _accumulatedTaskSeconds = 0;
      _activeTaskElapsedSeconds = 0;
      _taskSliceStartedAt = now;

      _pomodoroState = _pomodoroState.copyWith(
        realm: AppRealm.work,
        status: TimerStatus.running,
        elapsedSeconds: 0,
        targetSeconds:
            _pomodoroState.isStopwatch ? 0 : (_focusDurationMinutes * 60),
        overtimeSeconds: 0,
        lastNudgeAtOvertimeSeconds: 0,
        activeTaskId: workEntry.id,
      );

      MusicPlayerService.instance.onPomodoroModeChanged(PomodoroMode.focus);
      _ensureTickerRunning();
      await refreshAllData();
    }
  }

  /// سوییچ بین پومودورو (شمارش معکوس با هدف) و کرنومتر (شمارش رو به بالا)
  Future<void> toggleClockType() async {
    final bool willBeStopwatch = !_pomodoroState.isStopwatch;

    if (willBeStopwatch) {
      _pomodoroState = _pomodoroState.copyWith(
        clockType: ClockType.stopwatch,
        targetSeconds: 0,
        overtimeSeconds: 0,
        status: _pomodoroState.status == TimerStatus.paused
            ? TimerStatus.paused
            : TimerStatus.running,
      );
    } else {
      final int target = _pomodoroState.isWork
          ? _focusDurationMinutes * 60
          : _shortBreakDurationMinutes * 60;

      final newStatus = _pomodoroState.elapsedSeconds >= target
          ? TimerStatus.overtime
          : (_pomodoroState.status == TimerStatus.paused
              ? TimerStatus.paused
              : TimerStatus.running);

      _pomodoroState = _pomodoroState.copyWith(
        clockType: ClockType.pomodoro,
        targetSeconds: target,
        status: newStatus,
      );
    }

    _ensureTickerRunning();
    notifyListeners();
  }

  // ==================== کنترل پومودورو، تسک‌ها و کرنومتر ====================

  Future<void> startInstantWork({
    String? title,
    String? macroProjectId,
    String? subProjectId,
    List<String>? tagIds,
    String? existingGroupId,
  }) async {
    final now = DateTime.now();

    if (_pomodoroState.status == TimerStatus.idle ||
        _pomodoroState.realm != AppRealm.work ||
        _pomodoroState.isStopwatch) {
      _accumulatedPhaseSeconds = 0;
      _phaseStartedAt = now;
      _pomodoroState = _pomodoroState.copyWith(
        realm: AppRealm.work,
        clockType: ClockType.pomodoro,
        status: TimerStatus.running,
        elapsedSeconds: 0,
        targetSeconds: _focusDurationMinutes * 60,
        overtimeSeconds: 0,
        lastNudgeAtOvertimeSeconds: 0,
      );
      MusicPlayerService.instance.onPomodoroModeChanged(PomodoroMode.focus);
    } else if (_pomodoroState.status == TimerStatus.paused) {
      _phaseStartedAt = now;
      _pomodoroState = _pomodoroState.copyWith(
        status: _pomodoroState.elapsedSeconds >= _pomodoroState.targetSeconds
            ? TimerStatus.overtime
            : TimerStatus.running,
      );
    }

    if (_activeTaskLog == null) {
      final cleanTitle = (title == null || title.trim().isEmpty)
          ? AppDefaults.untitledTaskTitle
          : title.trim();
      final isUntitled = cleanTitle == AppDefaults.untitledTaskTitle;

      final newEntry = TaskLogEntry(
        id: _uuid.v4(),
        groupId: existingGroupId ?? _uuid.v4(),
        entryType: 'work',
        title: cleanTitle,
        isUntitledDraft: isUntitled,
        macroProjectId: macroProjectId,
        subProjectId: subProjectId,
        tagIds: tagIds ?? const [],
        startTime: now,
        pomodoroSetIndex:
            (_pomodoroState.completedSetsInCycle % AppDurations.setsPerCycle) +
                1,
      );

      await DatabaseService.instance.insertTaskLog(newEntry);
      _activeTaskLog = newEntry;
      _accumulatedTaskSeconds = 0;
      _activeTaskElapsedSeconds = 0;
      _taskSliceStartedAt = now;
      _pomodoroState = _pomodoroState.copyWith(activeTaskId: newEntry.id);
    } else {
      _taskSliceStartedAt ??= now;
    }

    _ensureTickerRunning();
    await refreshAllData();
  }

  Future<void> startWorkStopwatch({
    String? title,
    String? macroProjectId,
    String? subProjectId,
  }) async {
    await _closeAndPersistActiveTask();
    final now = DateTime.now();

    _accumulatedPhaseSeconds = 0;
    _phaseStartedAt = now;
    _lastErgonomicNudgeMessage = null;

    final entry = TaskLogEntry(
      id: _uuid.v4(),
      groupId: _uuid.v4(),
      entryType: 'stopwatch',
      title: (title == null || title.trim().isEmpty)
          ? 'کار با کرنومتر آزاد'
          : title.trim(),
      isUntitledDraft: false,
      macroProjectId: macroProjectId,
      subProjectId: subProjectId,
      startTime: now,
    );

    await DatabaseService.instance.insertTaskLog(entry);
    _activeTaskLog = entry;
    _accumulatedTaskSeconds = 0;
    _activeTaskElapsedSeconds = 0;
    _taskSliceStartedAt = now;

    _pomodoroState = _pomodoroState.copyWith(
      realm: AppRealm.work,
      clockType: ClockType.stopwatch,
      status: TimerStatus.running,
      elapsedSeconds: 0,
      targetSeconds: 0,
      activeTaskId: entry.id,
    );

    _ensureTickerRunning();
    await refreshAllData();
  }

  Future<void> startLifeStopwatch({
    String title = 'زندگی و استراحت آزاد',
  }) async {
    await _closeAndPersistActiveTask();
    final now = DateTime.now();

    _accumulatedPhaseSeconds = 0;
    _phaseStartedAt = now;
    _lastErgonomicNudgeMessage = null;

    final entry = TaskLogEntry(
      id: _uuid.v4(),
      groupId: _uuid.v4(),
      entryType: 'stopwatch',
      title: title,
      isUntitledDraft: false,
      startTime: now,
    );

    await DatabaseService.instance.insertTaskLog(entry);
    _activeTaskLog = entry;
    _accumulatedTaskSeconds = 0;
    _activeTaskElapsedSeconds = 0;
    _taskSliceStartedAt = now;

    _pomodoroState = _pomodoroState.copyWith(
      realm: AppRealm.life,
      clockType: ClockType.stopwatch,
      status: TimerStatus.running,
      elapsedSeconds: 0,
      targetSeconds: 0,
      activeTaskId: entry.id,
    );

    _ensureTickerRunning();
    await refreshAllData();
  }

  /// سوییچ به کرنومتر آزاد عمومی (برای سازگاری با نسخه‌های قبلی)
  Future<void> startStopwatchMode({
    String title = 'کرنومتر آزاد',
    String? macroProjectId,
    String? subProjectId,
  }) async {
    await startWorkStopwatch(
      title: title,
      macroProjectId: macroProjectId,
      subProjectId: subProjectId,
    );
  }

  /// ادامه یک تسک باز قبلی (Multi-Slice Resume)
  Future<void> resumeOpenTask(TaskLogEntry target) async {
    await startInstantWork(
      title: target.title,
      macroProjectId: target.macroProjectId,
      subProjectId: target.subProjectId,
      tagIds: target.tagIds,
      existingGroupId: target.groupId,
    );
  }

  /// علامت‌گذاری یک کار به عنوان پایان‌یافته
  Future<void> markTaskAsCompleted(String id) async {
    final task = await DatabaseService.instance.getTaskLogById(id);
    if (task == null) return;
    final updated = task.copyWith(isCompleted: true);
    await DatabaseService.instance.updateTaskLog(updated);
    if (_activeTaskLog?.id == id) {
      _activeTaskLog = updated;
    }
    await refreshAllData();
  }

  Future<void> updateActiveTaskMetadata({
    required String title,
    String? macroProjectId,
    String? subProjectId,
    required List<String> tagIds,
  }) async {
    if (_activeTaskLog == null) return;

    final cleanTitle =
        title.trim().isEmpty ? AppDefaults.untitledTaskTitle : title.trim();
    final isUntitled = cleanTitle == AppDefaults.untitledTaskTitle;

    final updated = _activeTaskLog!.copyWith(
      title: cleanTitle,
      isUntitledDraft: isUntitled,
      macroProjectId: macroProjectId,
      subProjectId: subProjectId,
      tagIds: tagIds,
    );

    await DatabaseService.instance.updateTaskLog(updated);
    _activeTaskLog = updated;
    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
  }

  Future<void> switchTaskMidPomodoro({
    required String newTitle,
    String? macroProjectId,
    String? subProjectId,
    required List<String> tagIds,
    String? existingGroupId,
  }) async {
    await _closeAndPersistActiveTask();

    final now = DateTime.now();
    final cleanTitle = newTitle.trim().isEmpty
        ? AppDefaults.untitledTaskTitle
        : newTitle.trim();
    final isUntitled = cleanTitle == AppDefaults.untitledTaskTitle;

    final nextTask = TaskLogEntry(
      id: _uuid.v4(),
      groupId: existingGroupId ?? _uuid.v4(),
      entryType: 'work',
      title: cleanTitle,
      isUntitledDraft: isUntitled,
      macroProjectId: macroProjectId,
      subProjectId: subProjectId,
      tagIds: tagIds,
      startTime: now,
      pomodoroSetIndex:
          (_pomodoroState.completedSetsInCycle % AppDurations.setsPerCycle) + 1,
    );

    await DatabaseService.instance.insertTaskLog(nextTask);
    _activeTaskLog = nextTask;
    _accumulatedTaskSeconds = 0;
    _activeTaskElapsedSeconds = 0;
    _taskSliceStartedAt = now;
    _pomodoroState = _pomodoroState.copyWith(activeTaskId: nextTask.id);

    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
  }

  /// شروع استراحت با ثبت رکورد استراحت در دیتابیس
  Future<void> startBreak() async {
    final now = DateTime.now();
    final int nextSets = _pomodoroState.isWork
        ? _pomodoroState.completedSetsInCycle + 1
        : _pomodoroState.completedSetsInCycle;

    final bool isLongBreak =
        (nextSets % AppDurations.setsPerCycle) == 0 && nextSets > 0;
    final int breakSec = isLongBreak
        ? _longBreakDurationMinutes * 60
        : _shortBreakDurationMinutes * 60;

    bool keepTaskOpen = false;
    if (_activeTaskLog != null && _activeTaskLog!.macroProjectId != null) {
      final macro = getProjectById(_activeTaskLog!.macroProjectId);
      if (macro != null) {
        keepTaskOpen = isLongBreak
            ? macro.countLongBreaksAsWork
            : macro.countShortBreaksAsWork;
      }
    }

    if (!keepTaskOpen) {
      await _closeAndPersistActiveTask();
    }

    // ثبت رکورد واقعی استراحت در جدول task_logs
    final breakEntry = TaskLogEntry(
      id: _uuid.v4(),
      groupId: _uuid.v4(),
      entryType: isLongBreak ? 'long_break' : 'short_break',
      title: isLongBreak ? 'استراحت طولانی (زندگی)' : 'استراحت ۵ دقیقه‌ای',
      isUntitledDraft: false,
      macroProjectId: _activeTaskLog?.macroProjectId,
      startTime: now,
    );
    await DatabaseService.instance.insertTaskLog(breakEntry);

    _accumulatedPhaseSeconds = 0;
    _phaseStartedAt = now;
    _lastErgonomicNudgeMessage = null;

    _pomodoroState = _pomodoroState.copyWith(
      realm: AppRealm.life,
      clockType: ClockType.pomodoro,
      status: TimerStatus.running,
      elapsedSeconds: 0,
      targetSeconds: breakSec,
      completedSetsInCycle: nextSets,
      overtimeSeconds: 0,
      lastNudgeAtOvertimeSeconds: 0,
    );

    MusicPlayerService.instance.onPomodoroModeChanged(_pomodoroState.mode);
    _ensureTickerRunning();
    await refreshAllData();
  }

  Future<void> pauseTimer() async {
    if (_pomodoroState.status != TimerStatus.running &&
        _pomodoroState.status != TimerStatus.overtime) {
      return;
    }

    final now = DateTime.now();
    if (_phaseStartedAt != null) {
      _accumulatedPhaseSeconds += now.difference(_phaseStartedAt!).inSeconds;
      _phaseStartedAt = null;
    }
    if (_taskSliceStartedAt != null) {
      _accumulatedTaskSeconds += now.difference(_taskSliceStartedAt!).inSeconds;
      _taskSliceStartedAt = null;
    }

    _ticker?.cancel();
    _pomodoroState = _pomodoroState.copyWith(status: TimerStatus.paused);
    notifyListeners();
  }

  Future<void> resumeTimer() async {
    if (_pomodoroState.status != TimerStatus.paused) return;
    final now = DateTime.now();
    _phaseStartedAt = now;
    if (_activeTaskLog != null) {
      _taskSliceStartedAt = now;
    }

    final nextStatus =
        _pomodoroState.elapsedSeconds >= _pomodoroState.targetSeconds &&
                !_pomodoroState.isStopwatch
            ? TimerStatus.overtime
            : TimerStatus.running;

    _pomodoroState = _pomodoroState.copyWith(status: nextStatus);
    _ensureTickerRunning();
    notifyListeners();
  }

  Future<void> stopAndResetSession() async {
    _ticker?.cancel();
    await _closeAndPersistActiveTask();
    _phaseStartedAt = null;
    _accumulatedPhaseSeconds = 0;
    _lastErgonomicNudgeMessage = null;

    _pomodoroState = PomodoroState(
      realm: AppRealm.work,
      clockType: ClockType.pomodoro,
      status: TimerStatus.idle,
      elapsedSeconds: 0,
      targetSeconds: _focusDurationMinutes * 60,
      completedSetsInCycle: _pomodoroState.completedSetsInCycle,
      windowPosture: _pomodoroState.windowPosture,
    );

    MusicPlayerService.instance.onPomodoroModeChanged(PomodoroMode.focus);
    await refreshAllData();
  }

  Future<void> _closeAndPersistActiveTask() async {
    if (_activeTaskLog == null) return;

    final now = DateTime.now();
    int finalSeconds = _accumulatedTaskSeconds;
    if (_taskSliceStartedAt != null) {
      finalSeconds += now.difference(_taskSliceStartedAt!).inSeconds;
    }
    if (finalSeconds < 1) finalSeconds = 1;

    final closed = _activeTaskLog!.copyWith(
      endTime: now,
      durationSeconds: finalSeconds,
      overtimeSeconds: _pomodoroState.overtimeSeconds,
    );

    await DatabaseService.instance.updateTaskLog(closed);
    _activeTaskLog = null;
    _taskSliceStartedAt = null;
    _accumulatedTaskSeconds = 0;
    _activeTaskElapsedSeconds = 0;

    await TxtLoggerService.instance.syncTxtFile();
    final proj = getProjectById(closed.effectiveProjectId);
    unawaited(GCalSyncService.instance.syncTaskLogEntry(closed, project: proj));
  }

  // ==================== مدیریت پنجره ویندوز ====================

  Future<void> setWindowPosture(WindowPosture posture,
      {bool expanded = false}) async {
    _isQuickMenuExpanded = expanded;
    _pomodoroState = _pomodoroState.copyWith(windowPosture: posture);
    notifyListeners();

    if (posture == WindowPosture.dashboard) {
      await PlatformHelper.switchToDashboardMode();
    } else if (posture == WindowPosture.floatingCircle) {
      await PlatformHelper.switchToFloatingWidgetMode(
        isSheetExpanded: expanded,
        isPinned: _isPinned,
      );
    } else if (posture == WindowPosture.edgeDockedLeft) {
      await PlatformHelper.switchToEdgeDockedMode(true);
    } else if (posture == WindowPosture.edgeDockedRight) {
      await PlatformHelper.switchToEdgeDockedMode(false);
    }
  }

  Future<void> toggleQuickMenuExpanded(bool expanded) async {
    _isQuickMenuExpanded = expanded;
    notifyListeners();
    if (_pomodoroState.windowPosture == WindowPosture.floatingCircle) {
      await PlatformHelper.switchToFloatingWidgetMode(
        isSheetExpanded: expanded,
        isPinned: _isPinned,
      );
    }
  }

  // ==================== متدهای CRUD و تحلیل ====================

  Future<void> completeUntitledDraft({
    required String id,
    required String title,
    String? macroProjectId,
    String? subProjectId,
    required List<String> tagIds,
  }) async {
    final existing = await DatabaseService.instance.getTaskLogById(id);
    if (existing == null) return;

    final updated = await DatabaseService.instance.updateTaskLogWithAudit(
      id: id,
      newTitle: title,
      newMacroProjectId: macroProjectId,
      newSubProjectId: subProjectId,
      newTagIds: tagIds,
      newStartTime: existing.startTime,
      newEndTime: existing.endTime ??
          existing.startTime.add(Duration(seconds: existing.durationSeconds)),
      newDurationSeconds: existing.durationSeconds,
    );

    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
    final proj = getProjectById(updated.effectiveProjectId);
    unawaited(
        GCalSyncService.instance.syncTaskLogEntry(updated, project: proj));
  }

  /// به‌روزرسانی سریع زمان شروع و پایان تسک در تقویم
  Future<void> updateTaskLogTimes({
    required String id,
    required DateTime newStartTime,
    required DateTime newEndTime,
    String? editNote,
  }) async {
    final existing = await DatabaseService.instance.getTaskLogById(id);
    if (existing == null) return;
    final int newDurationSec = newEndTime.difference(newStartTime).inSeconds;
    final tags = existing.tagIds.toList();
    if (!tags.contains('دستی') && !tags.contains('manual')) {
      tags.add('دستی');
    }
    await editTaskLogWithAudit(
      id: id,
      newTitle: existing.title,
      newMacroProjectId: existing.macroProjectId,
      newSubProjectId: existing.subProjectId,
      newTagIds: tags,
      newStartTime: newStartTime,
      newEndTime: newEndTime,
      newDurationSeconds: newDurationSec,
      isCompleted: existing.isCompleted,
      editNote: editNote ?? 'جابه‌جایی در تقویم',
    );
  }



  Future<void> editTaskLogWithAudit({
    required String id,
    required String newTitle,
    String? newMacroProjectId,
    String? newSubProjectId,
    required List<String> newTagIds,
    required DateTime newStartTime,
    required DateTime newEndTime,
    required int newDurationSeconds,
    bool? isCompleted,
    String? editNote,
  }) async {
    final updated = await DatabaseService.instance.updateTaskLogWithAudit(
      id: id,
      newTitle: newTitle,
      newMacroProjectId: newMacroProjectId,
      newSubProjectId: newSubProjectId,
      newTagIds: newTagIds,
      newStartTime: newStartTime,
      newEndTime: newEndTime,
      newDurationSeconds: newDurationSeconds,
      isCompleted: isCompleted,
      editNote: editNote,
    );

    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
    final proj = getProjectById(updated.effectiveProjectId);
    unawaited(
        GCalSyncService.instance.syncTaskLogEntry(updated, project: proj));
  }

  Future<void> deleteTaskLog(String id) async {
    await DatabaseService.instance.deleteTaskLog(id);
    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
  }

  /// ایجاد لاگ کارکرد به صورت دستی (با ثبت تگ «دستی» و ممیزی)
  Future<void> createManualTaskLog({
    required String title,
    String? macroProjectId,
    String? subProjectId,
    required DateTime startTime,
    required DateTime endTime,
    List<String>? tagIds,
    String entryType = 'work',
  }) async {
    final now = DateTime.now();
    final durationSeconds = endTime.difference(startTime).inSeconds;
    final tags = (tagIds ?? []).toList();
    if (!tags.contains('دستی') && !tags.contains('manual')) {
      tags.add('دستی');
    }

    final entry = TaskLogEntry(
      id: const Uuid().v4(),
      groupId: const Uuid().v4(),
      entryType: entryType,
      title: title.trim().isEmpty ? 'گزارش دستی' : title.trim(),
      isUntitledDraft: false,
      isCompleted: true,
      macroProjectId: macroProjectId,
      subProjectId: subProjectId,
      tagIds: tags,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: durationSeconds,
      isEdited: true,
      editedAt: now,
      editNote: 'ثبت دستی از تقویم',
    );

    await DatabaseService.instance.insertTaskLog(entry);
    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
  }

  Future<void> saveProject(ProjectNode project) async {
    await DatabaseService.instance.insertProject(project);
    await refreshAllData();
  }

  Future<void> deleteProject(String id) async {
    await DatabaseService.instance.deleteProject(id);
    await refreshAllData();
  }

  Future<void> savePhaseTag(PhaseTag tag) async {
    await DatabaseService.instance.insertPhaseTag(tag);
    await refreshAllData();
  }

  Future<void> deletePhaseTag(String id) async {
    await DatabaseService.instance.deletePhaseTag(id);
    await refreshAllData();
  }

  Future<void> saveScheduledBlock(ScheduledBlock block) async {
    await DatabaseService.instance.insertScheduledBlock(block);
    unawaited(GCalSyncService.instance.pushScheduledBlockToGCal(block));
    await refreshAllData();
  }

  Future<void> deleteScheduledBlock(String id) async {
    await DatabaseService.instance.deleteScheduledBlock(id);
    await refreshAllData();
  }

  Future<void> syncGoogleCalendar() async {
    final now = DateTime.now();
    final minDate = now.subtract(const Duration(days: 7));
    final maxDate = now.add(const Duration(days: 14));
    await GCalSyncService.instance.fetchScheduledBlocksFromGCal(
      timeMin: minDate,
      timeMax: maxDate,
      projects: _projects,
    );
    await refreshAllData();
  }

  Future<void> updateTimerSettings({
    required int focusMinutes,
    required int shortBreakMinutes,
    required int longBreakMinutes,
  }) async {
    _focusDurationMinutes = focusMinutes;
    _shortBreakDurationMinutes = shortBreakMinutes;
    _longBreakDurationMinutes = longBreakMinutes;

    final db = DatabaseService.instance;
    await db.setSetting(
        AppDefaults.settingKeyFocusDuration, focusMinutes.toString());
    await db.setSetting(
        AppDefaults.settingKeyShortBreakDuration, shortBreakMinutes.toString());
    await db.setSetting(
        AppDefaults.settingKeyLongBreakDuration, longBreakMinutes.toString());

    if (_pomodoroState.status == TimerStatus.idle &&
        !_pomodoroState.isStopwatch) {
      _pomodoroState =
          _pomodoroState.copyWith(targetSeconds: focusMinutes * 60);
    }
    notifyListeners();
  }

  Future<void> updateTxtLogPath(String newPath) async {
    if (newPath.trim().isEmpty) return;
    _txtLogPath = newPath.trim();
    await DatabaseService.instance
        .setSetting(AppDefaults.settingKeyTxtPath, _txtLogPath);
    await TxtLoggerService.instance.syncTxtFile();
    notifyListeners();
  }

  Future<void> updateGCalToken(String token) async {
    _gcalToken = token.trim();
    await DatabaseService.instance
        .setSetting(AppDefaults.settingKeyGCalToken, _gcalToken);
    notifyListeners();
  }

  Future<String?> exportLogsToExcel(List<TaskLogEntry> filteredLogs) async {
    return await ExcelExportService.instance.exportTimesheetToExcel(
      logs: filteredLogs,
      projects: _projects,
      tags: _phaseTags,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
