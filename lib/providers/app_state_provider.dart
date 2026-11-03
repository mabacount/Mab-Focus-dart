// موتور دو ساعته، Timestamp-Delta Ticker و مدیریت وضعیت برنامه
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../core/platform_helper.dart';
import '../models/phase_tag.dart';
import '../models/pomodoro_state.dart';
import '../models/project_node.dart';
import '../models/task_log_entry.dart';
import '../services/database_service.dart';
import '../services/excel_export_service.dart';
import '../services/gcal_sync_service.dart';
import '../services/sound_service.dart';
import '../services/txt_logger_service.dart';

class AppStateProvider extends ChangeNotifier {
  final Uuid _uuid = const Uuid();

  PomodoroState _pomodoroState = const PomodoroState();
  TaskLogEntry? _activeTaskLog;
  int _activeTaskElapsedSeconds = 0;

  // متغیرهای مرجع زمانی برای محاسبه دقیق Timestamp-Delta
  DateTime? _phaseStartedAt;
  int _accumulatedPhaseSeconds = 0;
  DateTime? _taskSliceStartedAt;
  int _accumulatedTaskSeconds = 0;
  Timer? _ticker;

  List<ProjectNode> _projects = [];
  List<PhaseTag> _phaseTags = [];
  List<TaskLogEntry> _taskLogs = [];

  int _focusDurationMinutes = 25;
  int _shortBreakDurationMinutes = 5;
  int _longBreakDurationMinutes = 60;
  String _txtLogPath = '';
  String _gcalToken = '';
  String _gcalSyncLevel = 'task';
  bool _isQuickMenuExpanded = false;
  String? _lastErgonomicNudgeMessage;

  // ==================== Getters ====================

  PomodoroState get pomodoroState => _pomodoroState;
  TaskLogEntry? get activeTaskLog => _activeTaskLog;
  int get activeTaskElapsedSeconds => _activeTaskElapsedSeconds;
  List<ProjectNode> get projects => _projects;
  List<ProjectNode> get macroProjects =>
      _projects.where((p) => p.isMacro && !p.archived).toList();
  List<PhaseTag> get phaseTags => _phaseTags.where((t) => !t.archived).toList();
  List<TaskLogEntry> get taskLogs => _taskLogs;
  List<TaskLogEntry> get untitledDraftLogs => _taskLogs
      .where((log) => log.isUntitledDraft && log.id != _activeTaskLog?.id)
      .toList();

  int get focusDurationMinutes => _focusDurationMinutes;
  int get shortBreakDurationMinutes => _shortBreakDurationMinutes;
  int get longBreakDurationMinutes => _longBreakDurationMinutes;
  String get txtLogPath => _txtLogPath;
  String get gcalToken => _gcalToken;
  String get gcalSyncLevel => _gcalSyncLevel;
  bool get isQuickMenuExpanded => _isQuickMenuExpanded;
  String? get lastErgonomicNudgeMessage => _lastErgonomicNudgeMessage;

  List<ProjectNode> getSubProjects(String? macroProjectId) {
    if (macroProjectId == null) return [];
    return _projects
        .where((p) => p.parentId == macroProjectId && !p.archived)
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

    _focusDurationMinutes = int.tryParse(focusStr ?? '25') ?? 25;
    _shortBreakDurationMinutes = int.tryParse(shortStr ?? '5') ?? 5;
    _longBreakDurationMinutes = int.tryParse(longStr ?? '60') ?? 60;

    _txtLogPath = await TxtLoggerService.instance.getEffectiveLogFilePath();
    _gcalToken = await db.getSetting(AppDefaults.settingKeyGCalToken,
            defaultValue: '') ??
        '';
    _gcalSyncLevel = await db.getSetting(AppDefaults.settingKeyGCalSyncLevel,
            defaultValue: 'task') ??
        'task';

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
    notifyListeners();
  }

  // ==================== موتور دو ساعته (Dual-Clock Engine) ====================

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

  /// ۱. شروع فوری کار با اصطکاک صفر (ساخت تسک بدون عنوان در صورت عدم ورود اطلاعات)
  Future<void> startInstantWork({
    String? title,
    String? macroProjectId,
    String? subProjectId,
    List<String>? tagIds,
  }) async {
    final now = DateTime.now();

    if (_pomodoroState.status == TimerStatus.idle ||
        _pomodoroState.mode != PomodoroMode.focus) {
      _accumulatedPhaseSeconds = 0;
      _phaseStartedAt = now;
      _pomodoroState = _pomodoroState.copyWith(
        mode: PomodoroMode.focus,
        status: TimerStatus.running,
        elapsedSeconds: 0,
        targetSeconds: _focusDurationMinutes * 60,
        overtimeSeconds: 0,
        lastNudgeAtOvertimeSeconds: 0,
      );
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

  /// ۲. به‌روزرسانی مشخصات تسکِ در حال اجرا بدون درج تگ [Edited]
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

  /// ۳. تعویض تسک در میانه پومودورو بدون ریست شدن ساعت پومودورو
  Future<void> switchTaskMidPomodoro({
    required String newTitle,
    String? macroProjectId,
    String? subProjectId,
    required List<String> tagIds,
  }) async {
    await _closeAndPersistActiveTask();

    final now = DateTime.now();
    final cleanTitle = newTitle.trim().isEmpty
        ? AppDefaults.untitledTaskTitle
        : newTitle.trim();
    final isUntitled = cleanTitle == AppDefaults.untitledTaskTitle;

    final nextTask = TaskLogEntry(
      id: _uuid.v4(),
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

    if (_pomodoroState.status == TimerStatus.idle ||
        _pomodoroState.status == TimerStatus.paused) {
      _phaseStartedAt = now;
      _pomodoroState = _pomodoroState.copyWith(status: TimerStatus.running);
      _ensureTickerRunning();
    }

    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
  }

  /// ۴. شروع استراحت با بررسی قانون استراحت در پروژه کلان
  Future<void> startBreak() async {
    final now = DateTime.now();
    final int nextCompletedSets = _pomodoroState.mode == PomodoroMode.focus
        ? _pomodoroState.completedSetsInCycle + 1
        : _pomodoroState.completedSetsInCycle;

    final bool isLongBreak =
        (nextCompletedSets % AppDurations.setsPerCycle) == 0 &&
            nextCompletedSets > 0;
    final PomodoroMode nextMode =
        isLongBreak ? PomodoroMode.longBreak : PomodoroMode.shortBreak;
    final int breakTargetSeconds = isLongBreak
        ? _longBreakDurationMinutes * 60
        : _shortBreakDurationMinutes * 60;

    bool keepTaskOpenDuringBreak = false;
    if (_activeTaskLog != null && _activeTaskLog!.macroProjectId != null) {
      final macroProject = getProjectById(_activeTaskLog!.macroProjectId);
      if (macroProject != null) {
        keepTaskOpenDuringBreak = isLongBreak
            ? macroProject.countLongBreaksAsWork
            : macroProject.countShortBreaksAsWork;
      }
    }

    if (!keepTaskOpenDuringBreak) {
      await _closeAndPersistActiveTask();
    }

    _accumulatedPhaseSeconds = 0;
    _phaseStartedAt = now;
    _lastErgonomicNudgeMessage = null;

    _pomodoroState = _pomodoroState.copyWith(
      mode: nextMode,
      status: TimerStatus.running,
      elapsedSeconds: 0,
      targetSeconds: breakTargetSeconds,
      completedSetsInCycle: nextCompletedSets,
      overtimeSeconds: 0,
      lastNudgeAtOvertimeSeconds: 0,
      activeTaskId: _activeTaskLog?.id,
    );

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
        _pomodoroState.elapsedSeconds >= _pomodoroState.targetSeconds
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
      mode: PomodoroMode.focus,
      status: TimerStatus.idle,
      elapsedSeconds: 0,
      targetSeconds: _focusDurationMinutes * 60,
      completedSetsInCycle: _pomodoroState.completedSetsInCycle,
      windowPosture: _pomodoroState.windowPosture,
    );

    await refreshAllData();
  }

  Future<void> _closeAndPersistActiveTask() async {
    if (_activeTaskLog == null) return;

    final now = DateTime.now();
    int finalTaskSeconds = _accumulatedTaskSeconds;
    if (_taskSliceStartedAt != null) {
      finalTaskSeconds += now.difference(_taskSliceStartedAt!).inSeconds;
    }
    if (finalTaskSeconds <= 0) {
      finalTaskSeconds = now.difference(_activeTaskLog!.startTime).inSeconds;
    }
    if (finalTaskSeconds < 1) {
      finalTaskSeconds = 1;
    }

    final closedEntry = _activeTaskLog!.copyWith(
      endTime: now,
      durationSeconds: finalTaskSeconds,
      overtimeSeconds: _pomodoroState.overtimeSeconds,
    );

    await DatabaseService.instance.updateTaskLog(closedEntry);
    _activeTaskLog = null;
    _taskSliceStartedAt = null;
    _accumulatedTaskSeconds = 0;
    _activeTaskElapsedSeconds = 0;

    await TxtLoggerService.instance.syncTxtFile();
    unawaited(GCalSyncService.instance.syncTaskLogEntry(closedEntry));
  }

  // ==================== تغییر کالبد پنجره ویندوز (Window Morphing) ====================

  Future<void> setWindowPosture(WindowPosture posture,
      {bool expanded = false}) async {
    _isQuickMenuExpanded = expanded;
    _pomodoroState = _pomodoroState.copyWith(windowPosture: posture);
    notifyListeners();

    if (posture == WindowPosture.dashboard) {
      await PlatformHelper.switchToDashboardMode();
    } else if (posture == WindowPosture.floatingCircle) {
      await PlatformHelper.switchToFloatingWidgetMode(expanded: expanded);
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
      await PlatformHelper.switchToFloatingWidgetMode(expanded: expanded);
    }
  }

  // ==================== عملیات ممیزی، کارتابل و CRUD داشبورد ====================

  /// تکمیل مشخصات تسک بدون عنوان در کارتابل بدون خوردن تگ [Edited]
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
    unawaited(GCalSyncService.instance.syncTaskLogEntry(updated));
  }

  /// ویرایش کامل رکورد در جدول فعالیت‌ها همراه با اعمال قانون ممیزی [Edited]
  Future<void> editTaskLogWithAudit({
    required String id,
    required String newTitle,
    String? newMacroProjectId,
    String? newSubProjectId,
    required List<String> newTagIds,
    required DateTime newStartTime,
    required DateTime newEndTime,
    required int newDurationSeconds,
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
      editNote: editNote,
    );

    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
    unawaited(GCalSyncService.instance.syncTaskLogEntry(updated));
  }

  Future<void> deleteTaskLog(String id) async {
    await DatabaseService.instance.deleteTaskLog(id);
    await refreshAllData();
    await TxtLoggerService.instance.syncTxtFile();
  }

  Future<void> saveProject({
    String? id,
    required String name,
    String? parentId,
    bool countShortBreaksAsWork = false,
    bool countLongBreaksAsWork = false,
    String colorHex = '#3B82F6',
  }) async {
    final project = ProjectNode(
      id: id ?? _uuid.v4(),
      name: name.trim(),
      parentId: parentId,
      countShortBreaksAsWork: countShortBreaksAsWork,
      countLongBreaksAsWork: countLongBreaksAsWork,
      colorHex: colorHex,
    );
    await DatabaseService.instance.insertProject(project);
    await refreshAllData();
  }

  Future<void> deleteProject(String id) async {
    await DatabaseService.instance.deleteProject(id);
    await refreshAllData();
  }

  Future<void> savePhaseTag({
    String? id,
    required String name,
    String category = 'phase',
  }) async {
    final tag = PhaseTag(
      id: id ?? _uuid.v4(),
      name: name.trim(),
      category: category,
    );
    await DatabaseService.instance.insertPhaseTag(tag);
    await refreshAllData();
  }

  Future<void> deletePhaseTag(String id) async {
    await DatabaseService.instance.deletePhaseTag(id);
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

    if (_pomodoroState.status == TimerStatus.idle) {
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

  Future<void> updateGCalSettings({
    required String token,
    required String syncLevel,
  }) async {
    _gcalToken = token.trim();
    _gcalSyncLevel = syncLevel;
    final db = DatabaseService.instance;
    await db.setSetting(AppDefaults.settingKeyGCalToken, _gcalToken);
    await db.setSetting(AppDefaults.settingKeyGCalSyncLevel, _gcalSyncLevel);
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
