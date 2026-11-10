import 'dart:async';
import 'dart:math' as math;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../core/platform_helper.dart';
import '../models/music_track.dart';
import '../models/outcome_item.dart';
import '../models/phase_tag.dart';
import '../models/pomodoro_state.dart';
import '../models/project_node.dart';
import '../models/scheduled_block.dart';
import '../models/session_note.dart';
import '../models/time_record.dart';
import '../services/database_service.dart';
import '../services/excel_export_service.dart';
import '../services/gcal_sync_service.dart';
import '../services/music_player_service.dart';
import '../services/sound_service.dart';
import '../services/txt_logger_service.dart';

class AppStateProvider extends ChangeNotifier {
  final Uuid _uuid = const Uuid();
  final bool isTestMode;

  AppStateProvider({this.isTestMode = false});

  PomodoroState _pomodoroState = const PomodoroState();
  AppRealm _dashboardRealm = AppRealm.work;

  TimeRecord? _activeRecord;
  TimeRecord? _recoveredOpenRecord;
  int _activeRecordElapsedSeconds = 0;

  DateTime? _phaseStartedAt;
  int _accumulatedPhaseSeconds = 0;
  DateTime? _recordSliceStartedAt;
  int _accumulatedRecordSeconds = 0;
  Timer? _ticker;

  List<ProjectNode> _projects = [];
  List<OutcomeItem> _outcomes = [];
  List<TimeRecord> _timeRecords = [];
  List<SessionNote> _sessionNotes = [];
  List<PhaseTag> _phaseTags = [];
  List<ScheduledBlock> _scheduledBlocks = [];
  List<MusicPlaylist> _playlists = [];

  // تنظیمات موتور Flowmodoro و بانک استراحت
  int _focusDurationMinutes = 25;
  int _shortBreakDurationMinutes = 5;
  int _longBreakDurationMinutes = 60;
  int _breakRatio = AppDurations.defaultBreakRatio;
  int _cycleWorkTargetMinutes = 100;
  int _cycleAutoResetMinutes = 90;

  // متغیرهای وضعیت بانک استراحت
  int _cycleWorkSeconds = 0;
  int _earnedShortBreakSeconds = 0;
  int _breakDebtSeconds = 0;
  bool _isInLongBreak = false;
  int _currentBreakTargetSeconds = 0;
  DateTime _lastCycleResetAt = DateTime.now();

  // تنظیمات مسیر لاگ و گوگل کلندر دوگانه
  String _txtLogPath = '';
  String _gcalToken = '';
  String _workPlanCalendarId = 'primary';
  String _lifePlanCalendarId = '';
  String _workLogCalendarId = 'primary';
  String _lifeLogCalendarId = '';

  bool _isQuickMenuExpanded = false;
  bool _isWorkNoteOpen = false;
  String? _lastErgonomicNudgeMessage;
  bool _isPinned = true;
  bool _isGoldenScheduledTaskActive = false;

  // اسنپ‌شات آخرین فعالیت کاری برای بازگشت خودکار پس از استراحت
  String? _previousWorkOutcomeId;
  String? _previousWorkTitle;
  String? _previousWorkProjectId;
  List<String> _previousWorkTagIds = [];
  bool _previousWorkWasGolden = false;

  static const Set<String> _genericLifeTitles = {
    'استراحت کوتاه (زندگی)',
    'استراحت طولانی (زندگی)',
    'زندگی و استراحت آزاد',
    'استراحت ۵ دقیقه‌ای',
    'استراحت کوتاه‌مدت',
    'کرنومتر زندگی و استراحت آزاد',
  };

  // ==================== Getters ====================

  PomodoroState get pomodoroState => _pomodoroState;
  AppRealm get dashboardRealm => _dashboardRealm;
  RealmPalette get activePalette =>
      _dashboardRealm == AppRealm.life ? RealmPalette.life : RealmPalette.work;

  TimeRecord? get activeRecord => _activeRecord;
  TimeRecord? get recoveredOpenRecord => _recoveredOpenRecord;
  int get activeRecordElapsedSeconds => _activeRecordElapsedSeconds;
  bool get isGoldenScheduledTaskActive => _isGoldenScheduledTaskActive;

  OutcomeItem? get activeOutcome => _activeRecord?.outcomeId != null
      ? getOutcomeById(_activeRecord!.outcomeId!)
      : null;

  ScheduledBlock? get currentActiveScheduledBlock {
    final now = DateTime.now();
    for (final b in _scheduledBlocks) {
      if (b.startTime.isBefore(now) && b.endTime.isAfter(now)) {
        return b;
      }
    }
    return null;
  }

  List<ProjectNode> get projects => _projects;
  List<OutcomeItem> get outcomes => _outcomes;
  List<TimeRecord> get timeRecords => _timeRecords;
  List<SessionNote> get sessionNotes => _sessionNotes;
  List<PhaseTag> get phaseTags => _phaseTags.where((t) => !t.archived).toList();
  List<ScheduledBlock> get scheduledBlocks => _scheduledBlocks;
  List<MusicPlaylist> get playlists => _playlists;

  List<TimeRecord> get untitledDraftRecords => _timeRecords
      .where((r) => r.isUntitledDraft && r.id != _activeRecord?.id)
      .toList();

  List<TimeRecord> untitledDraftRecordsForRealm(AppRealm realm) => _timeRecords
      .where((r) =>
          r.isUntitledDraft && r.realm == realm && r.id != _activeRecord?.id)
      .toList();

  int get focusDurationMinutes => _focusDurationMinutes;
  int get shortBreakDurationMinutes => _shortBreakDurationMinutes;
  int get longBreakDurationMinutes => _longBreakDurationMinutes;
  int get breakRatio => _breakRatio;
  int get cycleWorkTargetMinutes => _cycleWorkTargetMinutes;
  int get cycleAutoResetMinutes => _cycleAutoResetMinutes;
  int get cycleWorkSeconds => _cycleWorkSeconds;
  int get earnedShortBreakSeconds => _earnedShortBreakSeconds;
  int get breakDebtSeconds => _breakDebtSeconds;
  bool get isInLongBreak => _isInLongBreak;
  int get currentBreakTargetSeconds => _currentBreakTargetSeconds;

  String get txtLogPath => _txtLogPath;
  String get gcalToken => _gcalToken;
  String get workPlanCalendarId => _workPlanCalendarId;
  String get lifePlanCalendarId => _lifePlanCalendarId;
  String get workLogCalendarId => _workLogCalendarId;
  String get lifeLogCalendarId => _lifeLogCalendarId;

  bool get isQuickMenuExpanded => _isQuickMenuExpanded;
  bool get isWorkNoteOpen => _isWorkNoteOpen;
  String? get lastErgonomicNudgeMessage => _lastErgonomicNudgeMessage;
  bool get isPinned => _isPinned;

  void setDashboardRealm(AppRealm realm) {
    if (_dashboardRealm != realm) {
      _dashboardRealm = realm;
      notifyListeners();
    }
  }

  void setWorkNoteOpen(bool value) {
    if (_isWorkNoteOpen != value) {
      _isWorkNoteOpen = value;
      notifyListeners();
    }
  }

  // ==================== جستجوی درختی و Roll-up ====================

  List<ProjectNode> getProjectsForRealm(AppRealm realm,
      {bool includeArchived = false}) {
    return _projects
        .where((p) =>
            p.realm == realm && (includeArchived || !p.isArchived))
        .toList();
  }

  List<ProjectNode> getRootProjects(AppRealm realm,
      {bool includeArchived = false}) {
    return _projects
        .where((p) =>
            p.realm == realm &&
            p.parentId == null &&
            (includeArchived || !p.isArchived))
        .toList();
  }

  List<ProjectNode> getChildProjects(String? parentId,
      {required AppRealm realm, bool includeArchived = false}) {
    return _projects
        .where((p) =>
            p.realm == realm &&
            p.parentId == parentId &&
            (includeArchived || !p.isArchived))
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

  OutcomeItem? getOutcomeById(String id) {
    for (final o in _outcomes) {
      if (o.id == id) return o;
    }
    return null;
  }

  TimeRecord? getTimeRecordById(String id) {
    for (final r in _timeRecords) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<OutcomeItem> getOpenOutcomes({AppRealm? realm}) {
    return _outcomes
        .where((o) => !o.isCompleted && (realm == null || o.realm == realm))
        .toList();
  }

  List<OutcomeItem> getCompletedOutcomes({AppRealm? realm}) {
    return _outcomes
        .where((o) => o.isCompleted && (realm == null || o.realm == realm))
        .toList();
  }

  Set<String> _familyIds(String projectId) {
    return DatabaseService.getProjectAndDescendantIds(projectId, _projects);
  }

  List<OutcomeItem> getOutcomesForProjectRollup(String projectId,
      {bool? onlyOpen}) {
    final ids = _familyIds(projectId);
    return _outcomes.where((o) {
      if (o.projectId == null || !ids.contains(o.projectId)) return false;
      if (onlyOpen == true && o.isCompleted) return false;
      if (onlyOpen == false && !o.isCompleted) return false;
      return true;
    }).toList();
  }

  List<TimeRecord> getTimeRecordsForProjectRollup(String projectId) {
    final ids = _familyIds(projectId);
    final outcomeIds = _outcomes
        .where((o) => o.projectId != null && ids.contains(o.projectId))
        .map((o) => o.id)
        .toSet();
    return _timeRecords.where((r) {
      if (r.projectId != null && ids.contains(r.projectId)) return true;
      if (r.outcomeId != null && outcomeIds.contains(r.outcomeId)) return true;
      return false;
    }).toList();
  }

  List<SessionNote> getSessionNotesForProjectRollup(String projectId) {
    final ids = _familyIds(projectId);
    final outcomeIds = _outcomes
        .where((o) => o.projectId != null && ids.contains(o.projectId))
        .map((o) => o.id)
        .toSet();
    final recordIds = getTimeRecordsForProjectRollup(projectId)
        .map((r) => r.id)
        .toSet();
    return _sessionNotes.where((n) {
      if (n.projectId != null && ids.contains(n.projectId)) return true;
      if (n.outcomeId != null && outcomeIds.contains(n.outcomeId)) return true;
      if (n.timeRecordId != null && recordIds.contains(n.timeRecordId)) {
        return true;
      }
      return false;
    }).toList();
  }

  List<TimeRecord> getRecordsForOutcome(String outcomeId) {
    return _timeRecords.where((r) => r.outcomeId == outcomeId).toList();
  }

  List<SessionNote> getNotesForOutcome(String outcomeId) {
    return _sessionNotes.where((n) => n.outcomeId == outcomeId).toList();
  }

  List<SessionNote> getNotesForRecord(String timeRecordId) {
    return _sessionNotes.where((n) => n.timeRecordId == timeRecordId).toList();
  }

  int getTotalSecondsForOutcome(String outcomeId) {
    int total = 0;
    for (final r in _timeRecords) {
      if (r.outcomeId == outcomeId) {
        if (r.id == _activeRecord?.id) {
          total += _activeRecordElapsedSeconds;
        } else {
          total += r.durationSeconds;
        }
      }
    }
    return total;
  }

  double getEffectiveHourlyRate(String? projectId) {
    return DatabaseService.getEffectiveHourlyRate(projectId, _projects);
  }

  String getProjectBreadcrumbString(String? projectId) {
    final chain = DatabaseService.getProjectBreadcrumb(projectId, _projects);
    return chain.map((e) => e.name).join(' > ');
  }

  bool _isSleepProjectOrAncestor(String? projectId) {
    if (projectId == null) return false;
    final chain = DatabaseService.getProjectBreadcrumb(projectId, _projects);
    return chain.any((p) => p.isSleepProject);
  }

  // ==================== تسک طلایی (Golden Task) ====================

  Future<void> toggleGoldenScheduledTask([ScheduledBlock? targetBlock]) async {
    if (_isGoldenScheduledTaskActive) {
      _isGoldenScheduledTaskActive = false;
      notifyListeners();
    } else {
      final block = targetBlock ?? currentActiveScheduledBlock;
      if (block != null) {
        await activateScheduledBlockTask(block);
      } else if (_activeRecord != null) {
        _isGoldenScheduledTaskActive = true;
        notifyListeners();
      }
    }
  }

  Future<void> activateScheduledBlockTask(ScheduledBlock block) async {
    _isGoldenScheduledTaskActive = true;
    final OutcomeItem? linkedOutcome =
        block.outcomeId != null ? getOutcomeById(block.outcomeId!) : null;
    await switchRealm(
      block.realm,
      outcome: linkedOutcome,
      title: linkedOutcome == null ? block.title : null,
      projectId: linkedOutcome?.projectId ?? block.projectId,
    );
    _isGoldenScheduledTaskActive = true;
    notifyListeners();
  }

  void deactivateGoldenTask() {
    if (_isGoldenScheduledTaskActive) {
      _isGoldenScheduledTaskActive = false;
      notifyListeners();
    }
  }

  // ==================== مقداردهی اولیه و بازیابی پس از کرش (چالش ۳) ====================

  Future<void> initialize() async {
    await _loadSettings();
    await refreshAllData();
    await _recoverOpenSessionIfAny();
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
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
    final ratioStr = await db.getSetting(AppDefaults.settingKeyBreakRatio,
        defaultValue: '5');
    final cycleTargetStr = await db.getSetting(
        AppDefaults.settingKeyCycleWorkTargetMinutes,
        defaultValue: '100');
    final autoResetStr = await db.getSetting(
        AppDefaults.settingKeyCycleAutoResetMinutes,
        defaultValue: '90');

    final musicBreakStr = await db.getSetting(
        AppDefaults.settingKeyPlayMusicDuringBreaks,
        defaultValue: '0');
    final pinnedStr = await db.getSetting(AppDefaults.settingKeyWidgetPinned,
        defaultValue: '1');

    _focusDurationMinutes =
        (int.tryParse(focusStr ?? '25') ?? 25).clamp(1, 240);
    _shortBreakDurationMinutes =
        (int.tryParse(shortStr ?? '5') ?? 5).clamp(1, 60);
    _longBreakDurationMinutes =
        (int.tryParse(longStr ?? '60') ?? 60).clamp(5, 240);
    _breakRatio = (int.tryParse(ratioStr ?? '5') ?? 5).clamp(1, 20);
    _cycleWorkTargetMinutes =
        (int.tryParse(cycleTargetStr ?? '100') ?? 100).clamp(10, 600);
    _cycleAutoResetMinutes =
        (int.tryParse(autoResetStr ?? '90') ?? 90).clamp(15, 600);
    _isPinned = (pinnedStr ?? '1') == '1';

    // بازیابی متغیرهای پایدار بانک استراحت
    _cycleWorkSeconds = int.tryParse(
            await db.getSetting(AppDefaults.stateCycleWorkSeconds) ?? '0') ??
        0;
    _earnedShortBreakSeconds = int.tryParse(
            await db.getSetting(AppDefaults.stateEarnedShortBreakSeconds) ??
                '0') ??
        0;
    _breakDebtSeconds = int.tryParse(
            await db.getSetting(AppDefaults.stateBreakDebtSeconds) ?? '0') ??
        0;
    _isInLongBreak =
        (await db.getSetting(AppDefaults.stateIsInLongBreak) ?? '0') == '1';
    _currentBreakTargetSeconds = int.tryParse(
            await db.getSetting(AppDefaults.stateCurrentBreakTargetSeconds) ??
                '0') ??
        0;
    final savedClockMode =
        await db.getSetting(AppDefaults.stateClockMode, defaultValue: 'pomodoro');
    final clockType = ClockTypeX.fromDb(savedClockMode);
    final resetAtRaw =
        await db.getSetting(AppDefaults.stateLastCycleResetAt);
    _lastCycleResetAt = (resetAtRaw != null && resetAtRaw.isNotEmpty)
        ? (DateTime.tryParse(resetAtRaw) ?? DateTime.now())
        : DateTime.now();

    _gcalToken = await db.getSetting(AppDefaults.settingKeyGCalToken,
            defaultValue: '') ??
        '';
    _workPlanCalendarId = await db.getSetting(
            AppDefaults.settingKeyPlanCalendarId,
            defaultValue: 'primary') ??
        'primary';
    _lifePlanCalendarId = await db.getSetting(
            AppDefaults.settingKeyLifePlanCalendarId,
            defaultValue: '') ??
        '';
    _workLogCalendarId = await db.getSetting(
            AppDefaults.settingKeyWorkLogCalendarId,
            defaultValue: 'primary') ??
        'primary';
    final lifeLogRaw =
        await db.getSetting(AppDefaults.settingKeyLifeLogCalendarId);
    final legacyBreakRaw =
        await db.getSetting(AppDefaults.settingKeyBreakLogCalendarId);
    _lifeLogCalendarId = (lifeLogRaw != null && lifeLogRaw.isNotEmpty)
        ? lifeLogRaw
        : (legacyBreakRaw ?? '');

    if (!isTestMode) {
      MusicPlayerService.instance.setPlayDuringBreaks(musicBreakStr == '1');
      try {
        _txtLogPath = await TxtLoggerService.instance.getEffectiveLogFilePath();
      } catch (_) {}
      _initMultiWindowSync();
    }

    _pomodoroState = _pomodoroState.copyWith(
      clockType: clockType,
      targetSeconds:
          clockType == ClockType.stopwatch ? 0 : _focusDurationMinutes * 60,
      cycleWorkSeconds: _cycleWorkSeconds,
      earnedShortBreakSeconds: _earnedShortBreakSeconds,
      breakDebtSeconds: _breakDebtSeconds,
      cycleWorkTargetSeconds: _cycleWorkTargetMinutes * 60,
      isInLongBreak: _isInLongBreak,
    );
  }

  /// بازیابی خودکار رکورد باز (end_time IS NULL) در صورت کرش یا بسته شدن ناگهانی اپ (چالش ۳)
  Future<void> _recoverOpenSessionIfAny() async {
    final openRecords = await DatabaseService.instance.getOpenTimeRecords();
    if (openRecords.isEmpty) return;

    final TimeRecord newest = openRecords.first;

    // بستن رکوردهای باز جا‌مانده قدیمی‌تر (اگر به ندرت بیش از یک رکورد باز باشد)
    if (openRecords.length > 1) {
      for (int i = 1; i < openRecords.length; i++) {
        final oldRec = openRecords[i];
        final DateTime fallbackEnd = newest.startTime.isAfter(oldRec.startTime)
            ? newest.startTime
            : oldRec.startTime.add(const Duration(seconds: 1));
        final dur =
            math.max(1, fallbackEnd.difference(oldRec.startTime).inSeconds);
        await DatabaseService.instance.updateTimeRecord(
          oldRec.copyWith(
            endTime: fallbackEnd,
            durationSeconds: dur,
            earnedBreakSeconds:
                oldRec.isWork ? (dur ~/ _breakRatio) : 0,
          ),
        );
      }
      await refreshAllData();
    }

    final now = DateTime.now();
    final int elapsed =
        math.max(0, now.difference(newest.startTime).inSeconds);

    _activeRecord = newest;
    _recoveredOpenRecord = newest;
    _dashboardRealm = newest.realm;
    _recordSliceStartedAt = newest.startTime;
    _accumulatedRecordSeconds = 0;
    _activeRecordElapsedSeconds = elapsed;
    _phaseStartedAt = newest.startTime;
    _accumulatedPhaseSeconds = 0;

    int targetSec = 0;
    if (newest.clockMode == ClockType.pomodoro) {
      if (newest.isWork) {
        targetSec = _focusDurationMinutes * 60;
      } else {
        targetSec = _currentBreakTargetSeconds > 0
            ? _currentBreakTargetSeconds
            : _previewLifeBreakTarget();
        _currentBreakTargetSeconds = targetSec;
      }
    }

    int overtimeSec = 0;
    TimerStatus status = TimerStatus.running;
    if (newest.clockMode == ClockType.pomodoro &&
        targetSec > 0 &&
        elapsed >= targetSec) {
      status = TimerStatus.overtime;
      overtimeSec = elapsed - targetSec;
    }

    _pomodoroState = _pomodoroState.copyWith(
      realm: newest.realm,
      clockType: newest.clockMode,
      status: status,
      elapsedSeconds: elapsed,
      targetSeconds: targetSec,
      overtimeSeconds: overtimeSec,
      lastNudgeAtOvertimeSeconds: overtimeSec,
      cycleWorkSeconds: _cycleWorkSeconds,
      earnedShortBreakSeconds: _earnedShortBreakSeconds,
      breakDebtSeconds: _breakDebtSeconds,
      cycleWorkTargetSeconds: _cycleWorkTargetMinutes * 60,
      isInLongBreak: _isInLongBreak,
      activeRecordId: newest.id,
      activeOutcomeId: newest.outcomeId,
      clearActiveOutcome: newest.outcomeId == null,
    );

    _ensureTickerRunning();
    notifyListeners();
  }

  void dismissRecoveredRecordNotice() {
    if (_recoveredOpenRecord != null) {
      _recoveredOpenRecord = null;
      notifyListeners();
    }
  }

  /// بستن رکورد بازیابی‌شده در زمان انتخابی کاربر و شروع پیوسته از همان لحظه (رفع خلأ تایم‌شیت)
  Future<void> closeRecoveredRecordAtTimeAndStartNew({
    required DateTime closedAt,
    AppRealm? nextRealm,
  }) async {
    final rec = _activeRecord;
    if (rec == null) return;

    final now = DateTime.now();
    DateTime safeClosedAt = closedAt;
    if (safeClosedAt.isBefore(rec.startTime)) {
      safeClosedAt = rec.startTime.add(const Duration(seconds: 1));
    }
    if (safeClosedAt.isAfter(now)) {
      safeClosedAt = now;
    }

    final int dur =
        math.max(1, safeClosedAt.difference(rec.startTime).inSeconds);
    final int earned = rec.isWork ? (dur ~/ _breakRatio) : 0;

    final closedRec = rec.copyWith(
      endTime: safeClosedAt,
      durationSeconds: dur,
      earnedBreakSeconds: earned,
      isEdited: true,
      editedAt: now,
      editNote: 'اصلاح زمان پایان پس از بازیابی',
    );
    await DatabaseService.instance.updateTimeRecord(closedRec);

    if (closedRec.isWork) {
      _applyWorkSliceToBank(dur);
    } else {
      _applyLifeSliceToBank(
        dur,
        project: getProjectById(closedRec.projectId),
        resetTime: safeClosedAt,
      );
    }

    _activeRecord = null;
    _recoveredOpenRecord = null;
    _recordSliceStartedAt = null;
    _accumulatedRecordSeconds = 0;
    _activeRecordElapsedSeconds = 0;

    final AppRealm targetRealm = nextRealm ??
        (closedRec.isWork ? AppRealm.life : AppRealm.work);
    await _startNewContinuousSliceAt(
      startTime: safeClosedAt,
      targetRealm: targetRealm,
    );
  }

  void _initMultiWindowSync() {
    if (!PlatformHelper.isDesktop || isTestMode) return;
    try {
      const channel = WindowMethodChannel('work_notes_sync');
      channel.setMethodCallHandler((call) async {
        if (call.method == 'note_added') {
          _sessionNotes = await DatabaseService.instance.getAllSessionNotes();
          notifyListeners();
        }
        return null;
      });
    } catch (_) {}
  }

  Future<void> refreshAllData() async {
    final db = DatabaseService.instance;
    _projects = await db.getProjects(includeArchived: true);
    _outcomes = await db.getOutcomes();
    _timeRecords = await db.getAllTimeRecords();
    _phaseTags = await db.getPhaseTags(includeArchived: true);
    _playlists = await db.getAllMusicPlaylists();
    _sessionNotes = await db.getAllSessionNotes();

    final now = DateTime.now();
    final startRange = now.subtract(const Duration(days: 30));
    final endRange = now.add(const Duration(days: 30));
    _scheduledBlocks = await db.getScheduledBlocksInRange(startRange, endRange);

    if (_activeRecord != null) {
      final refreshedActive = getTimeRecordById(_activeRecord!.id);
      if (refreshedActive != null) {
        _activeRecord = refreshedActive;
      }
    }

    notifyListeners();
  }

  // ==================== منطق بانک استراحت Flowmodoro ====================

  Future<void> _persistFlowmodoroState() async {
    final db = DatabaseService.instance;
    await Future.wait([
      db.setSetting(
          AppDefaults.stateCycleWorkSeconds, _cycleWorkSeconds.toString()),
      db.setSetting(AppDefaults.stateEarnedShortBreakSeconds,
          _earnedShortBreakSeconds.toString()),
      db.setSetting(
          AppDefaults.stateBreakDebtSeconds, _breakDebtSeconds.toString()),
      db.setSetting(
          AppDefaults.stateIsInLongBreak, _isInLongBreak ? '1' : '0'),
      db.setSetting(AppDefaults.stateCurrentBreakTargetSeconds,
          _currentBreakTargetSeconds.toString()),
      db.setSetting(
          AppDefaults.stateClockMode, _pomodoroState.clockType.dbValue),
      db.setSetting(AppDefaults.stateLastCycleResetAt,
          _lastCycleResetAt.toIso8601String()),
    ]);
  }

  void _applyWorkSliceToBank(int workSeconds) {
    final int safeSec = math.max(0, workSeconds);
    final int earned = safeSec ~/ _breakRatio;
    _cycleWorkSeconds += safeSec;
    _earnedShortBreakSeconds += earned;
  }

  int _previewLifeBreakTarget() {
    final int wTarget = _cycleWorkTargetMinutes * 60;
    final int minBreakSec = _shortBreakDurationMinutes * 60;
    final int longBreakBaseSec = _longBreakDurationMinutes * 60;

    if (_cycleWorkSeconds >= wTarget) {
      final int overshootBreak = (_cycleWorkSeconds - wTarget) ~/ _breakRatio;
      return math.max(
          minBreakSec, longBreakBaseSec - _breakDebtSeconds + overshootBreak);
    } else {
      return math.max(minBreakSec, _earnedShortBreakSeconds);
    }
  }

  int _enterLifeBreakTarget() {
    final int wTarget = _cycleWorkTargetMinutes * 60;
    final int minBreakSec = _shortBreakDurationMinutes * 60;
    final int longBreakBaseSec = _longBreakDurationMinutes * 60;

    if (_cycleWorkSeconds >= wTarget) {
      _isInLongBreak = true;
      final int overshootBreak = (_cycleWorkSeconds - wTarget) ~/ _breakRatio;
      _currentBreakTargetSeconds = math.max(
          minBreakSec, longBreakBaseSec - _breakDebtSeconds + overshootBreak);
    } else {
      _isInLongBreak = false;
      _currentBreakTargetSeconds =
          math.max(minBreakSec, _earnedShortBreakSeconds);
    }
    return _currentBreakTargetSeconds;
  }

  void _applyLifeSliceToBank(
    int lifeSeconds, {
    ProjectNode? project,
    DateTime? resetTime,
  }) {
    final int safeSec = math.max(0, lifeSeconds);
    final int autoResetThresholdSec = _cycleAutoResetMinutes * 60;
    final bool isSleep = _isSleepProjectOrAncestor(project?.id);

    if (safeSec >= autoResetThresholdSec || isSleep || _isInLongBreak) {
      _cycleWorkSeconds = 0;
      _earnedShortBreakSeconds = 0;
      _breakDebtSeconds = 0;
      _isInLongBreak = false;
      _currentBreakTargetSeconds = 0;
      _lastCycleResetAt = resetTime ?? DateTime.now();
      return;
    }

    if (safeSec < _earnedShortBreakSeconds) {
      _earnedShortBreakSeconds -= safeSec;
    } else {
      final int overBreak = safeSec - _earnedShortBreakSeconds;
      _breakDebtSeconds += overBreak;
      _earnedShortBreakSeconds = 0;
    }
    _currentBreakTargetSeconds = 0;
  }

  /// محاسبه مجدد بانک استراحت چرخه جاری از روی تاریخچه بسته شده بعد از ریست (برای اصلاح همگام بعد از Swap یا ویرایش)
  Future<void> _recalculateCurrentCycleBankFromHistory() async {
    final wTarget = _cycleWorkTargetMinutes * 60;
    final autoResetThreshold = _cycleAutoResetMinutes * 60;

    final recordsInCycle = _timeRecords
        .where((r) =>
            r.endTime != null && !r.startTime.isBefore(_lastCycleResetAt))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    int w = 0;
    int b = 0;
    int d = 0;
    bool inLong = false;
    DateTime latestReset = _lastCycleResetAt;

    for (final rec in recordsInCycle) {
      if (rec.isWork) {
        w += rec.durationSeconds;
        b += rec.durationSeconds ~/ _breakRatio;
        inLong = w >= wTarget;
      } else {
        final bool isSleep = _isSleepProjectOrAncestor(rec.projectId);
        if (rec.durationSeconds >= autoResetThreshold || isSleep || inLong) {
          w = 0;
          b = 0;
          d = 0;
          inLong = false;
          latestReset = rec.endTime ?? rec.startTime;
        } else {
          if (rec.durationSeconds < b) {
            b -= rec.durationSeconds;
          } else {
            d += (rec.durationSeconds - b);
            b = 0;
          }
        }
      }
    }

    _cycleWorkSeconds = w;
    _earnedShortBreakSeconds = b;
    _breakDebtSeconds = d;
    _lastCycleResetAt = latestReset;

    int targetSec = _pomodoroState.targetSeconds;
    if (_activeRecord != null && _activeRecord!.isLife && _pomodoroState.isPomodoro) {
      targetSec = _enterLifeBreakTarget();
    } else if (_activeRecord == null || _activeRecord!.isWork) {
      _isInLongBreak = false;
      _currentBreakTargetSeconds = 0;
    }

    _pomodoroState = _pomodoroState.copyWith(
      cycleWorkSeconds: _cycleWorkSeconds,
      earnedShortBreakSeconds: _earnedShortBreakSeconds,
      breakDebtSeconds: _breakDebtSeconds,
      cycleWorkTargetSeconds: wTarget,
      isInLongBreak: _isInLongBreak,
      targetSeconds: targetSec,
    );

    await _persistFlowmodoroState();
    notifyListeners();
  }

  /// دکمه ریست دستی چرخه Flowmodoro (چالش ۱)
  Future<void> resetFlowmodoroCycle({DateTime? atTime}) async {
    _cycleWorkSeconds = 0;
    _earnedShortBreakSeconds = 0;
    _breakDebtSeconds = 0;
    _isInLongBreak = false;
    _lastCycleResetAt = atTime ?? DateTime.now();

    int newTarget = _pomodoroState.targetSeconds;
    TimerStatus newStatus = _pomodoroState.status;
    int newOvertime = _pomodoroState.overtimeSeconds;

    if (_pomodoroState.isLife && _pomodoroState.isPomodoro) {
      newTarget = _shortBreakDurationMinutes * 60;
      _currentBreakTargetSeconds = newTarget;
      if (_pomodoroState.status == TimerStatus.running ||
          _pomodoroState.status == TimerStatus.overtime) {
        if (_pomodoroState.elapsedSeconds >= newTarget) {
          newStatus = TimerStatus.overtime;
          newOvertime = _pomodoroState.elapsedSeconds - newTarget;
        } else {
          newStatus = TimerStatus.running;
          newOvertime = 0;
        }
      }
    } else {
      _currentBreakTargetSeconds = 0;
    }

    _pomodoroState = _pomodoroState.copyWith(
      cycleWorkSeconds: 0,
      earnedShortBreakSeconds: 0,
      breakDebtSeconds: 0,
      isInLongBreak: false,
      targetSeconds: newTarget,
      status: newStatus,
      overtimeSeconds: newOvertime,
    );

    await _persistFlowmodoroState();
    notifyListeners();
  }

  // ==================== موتور زمان‌سنج بر پایه Timestamp-Delta ====================

  void _ensureTickerRunning() {
    _ticker?.cancel();
    if (isTestMode) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (_pomodoroState.status != TimerStatus.running &&
        _pomodoroState.status != TimerStatus.overtime) {
      return;
    }

    final now = DateTime.now();
    final int currentPhaseDelta = _phaseStartedAt != null
        ? math.max(0, now.difference(_phaseStartedAt!).inSeconds)
        : 0;
    final int totalPhaseElapsed = _accumulatedPhaseSeconds + currentPhaseDelta;

    if (_activeRecord != null && _recordSliceStartedAt != null) {
      final int currentRecordDelta =
          math.max(0, now.difference(_recordSliceStartedAt!).inSeconds);
      _activeRecordElapsedSeconds =
          _accumulatedRecordSeconds + currentRecordDelta;
    }

    // حالت ۱: کرنومتر آزاد
    if (_pomodoroState.isStopwatch) {
      _pomodoroState = _pomodoroState.copyWith(
        elapsedSeconds: totalPhaseElapsed,
      );
      notifyListeners();
      return;
    }

    // حالت ۲: پومودورو (در هر دو قلمرو کار و زندگی)
    TimerStatus newStatus = _pomodoroState.status;
    int overtimeSec = 0;
    int lastNudge = _pomodoroState.lastNudgeAtOvertimeSeconds;

    if (_pomodoroState.targetSeconds > 0 &&
        totalPhaseElapsed >= _pomodoroState.targetSeconds) {
      overtimeSec = totalPhaseElapsed - _pomodoroState.targetSeconds;
      if (_pomodoroState.status != TimerStatus.overtime) {
        newStatus = TimerStatus.overtime;
        if (!isTestMode) {
          SoundService.instance.playCompletionChime();
        }
        if (_pomodoroState.isLife) {
          _lastErgonomicNudgeMessage =
              'زمان استراحت تمام شد؛ ادامه حضور در زندگی از استراحت طولانی آینده کسر می‌شود.';
        }
      }

      if (overtimeSec - lastNudge >=
          AppDurations.overtimeNudgeIntervalSeconds) {
        lastNudge = overtimeSec;
        if (!isTestMode) {
          SoundService.instance.playOvertimeNudge();
        }
        if (_pomodoroState.isWork) {
          _lastErgonomicNudgeMessage =
              '۵ دقیقه از زمان پومودورو گذشته است؛ آیا مایل به استراحت هستید؟';
        } else {
          final overMin = (overtimeSec / 60).floor();
          _lastErgonomicNudgeMessage =
              '$overMin دقیقه اضافه‌استراحت (کسر از سهمیه آینده)؛ آماده بازگشت به کار هستید؟';
        }
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

  // ==================== کنترل دوگانه کار و زندگی (متد یکپارچه switchRealm - چالش ۴) ====================

  Future<void> togglePin() async {
    _isPinned = !_isPinned;
    await DatabaseService.instance.setSetting(
      AppDefaults.settingKeyWidgetPinned,
      _isPinned ? '1' : '0',
    );
    if (!isTestMode) {
      await PlatformHelper.setPinned(_isPinned);
    }
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    await toggleWorkLife();
  }

  Future<void> toggleWorkLife() async {
    final target =
        _pomodoroState.isWork ? AppRealm.life : AppRealm.work;
    await switchRealm(target);
  }

  /// متد واحد و یکپارچه برای سوییچ بین قلمرو «کار» و «زندگی» بر اساس قوانین Flowmodoro
  Future<void> switchRealm(
    AppRealm targetRealm, {
    OutcomeItem? outcome,
    String? title,
    String? projectId,
    List<String>? tagIds,
    ClockType? clockType,
    DateTime? atTime,
  }) async {
    final now = atTime ?? DateTime.now();

    // ۰. اگر از کار به زندگی می‌رویم، آخرین تسک کاری را اسنپ‌شات می‌گیریم
    if (_activeRecord != null &&
        _activeRecord!.isWork &&
        targetRealm == AppRealm.life) {
      _previousWorkOutcomeId = _activeRecord!.outcomeId;
      _previousWorkTitle = _activeRecord!.isUntitledDraft
          ? null
          : _activeRecord!.titleSnapshot;
      _previousWorkProjectId = _activeRecord!.projectId;
      _previousWorkTagIds = List.from(_activeRecord!.tagIds);
      _previousWorkWasGolden = _isGoldenScheduledTaskActive;
    }

    // ۱. بستن رکورد فعال قبلی و ثبت تاثیر آن روی بانک استراحت
    if (_activeRecord != null) {
      await _closeActiveRecordAndUpdateBank(endTime: now);
    }

    // اگر ساعت مشخص‌شده روی کرنومتر یا پومودورو نبود، از وضعیت فعلی استفاده می‌کنیم
    final ClockType activeClock = clockType ?? _pomodoroState.clockType;
    if (clockType != null) {
      _pomodoroState = _pomodoroState.copyWith(clockType: clockType);
    }

    _recoveredOpenRecord = null;
    await _startNewContinuousSliceAt(
      startTime: now,
      targetRealm: targetRealm,
      outcome: outcome,
      title: title,
      projectId: projectId,
      tagIds: tagIds,
      clockType: activeClock,
    );
  }

  Future<void> _closeActiveRecordAndUpdateBank({DateTime? endTime}) async {
    final current = _activeRecord;
    if (current == null) return;

    final now = endTime ?? DateTime.now();
    int finalSeconds = _accumulatedRecordSeconds;
    if (_recordSliceStartedAt != null) {
      finalSeconds +=
          math.max(0, now.difference(_recordSliceStartedAt!).inSeconds);
    }
    if (finalSeconds < 1) finalSeconds = 1;

    final int earnedBreak =
        current.isWork ? (finalSeconds ~/ _breakRatio) : 0;

    final closed = current.copyWith(
      endTime: now,
      durationSeconds: finalSeconds,
      overtimeSeconds: _pomodoroState.overtimeSeconds,
      earnedBreakSeconds: earnedBreak,
    );

    await DatabaseService.instance.updateTimeRecord(closed);

    if (closed.isWork) {
      _applyWorkSliceToBank(finalSeconds);
    } else {
      _applyLifeSliceToBank(
        finalSeconds,
        project: getProjectById(closed.projectId),
        resetTime: now,
      );
    }

    _activeRecord = null;
    _recordSliceStartedAt = null;
    _accumulatedRecordSeconds = 0;
    _activeRecordElapsedSeconds = 0;

    if (!isTestMode) {
      unawaited(GCalSyncService.instance.syncTimeRecord(
        closed,
        projects: _projects,
      ));
    }
  }

  Future<void> _startNewContinuousSliceAt({
    required DateTime startTime,
    required AppRealm targetRealm,
    OutcomeItem? outcome,
    String? title,
    String? projectId,
    List<String>? tagIds,
    ClockType? clockType,
  }) async {
    final ClockType effectiveClock = clockType ?? _pomodoroState.clockType;

    String? effectiveOutcomeId;
    String? effectiveProjectId;
    String effectiveTitle;
    bool isUntitled = false;
    List<String> effectiveTags = tagIds != null ? List.from(tagIds) : [];
    int targetSeconds = 0;

    if (targetRealm == AppRealm.life) {
      final int breakTargetSec = _enterLifeBreakTarget();
      targetSeconds =
          effectiveClock == ClockType.stopwatch ? 0 : breakTargetSec;
      _isGoldenScheduledTaskActive = outcome != null && _isGoldenScheduledTaskActive;

      if (outcome != null && outcome.isLife) {
        effectiveOutcomeId = outcome.id;
        effectiveProjectId = outcome.projectId ?? projectId;
        effectiveTitle = outcome.title;
      } else if (title != null && title.trim().isNotEmpty) {
        effectiveTitle = title.trim();
        effectiveProjectId = projectId;
        isUntitled = effectiveTitle == AppDefaults.untitledTaskTitle;
      } else {
        effectiveTitle = effectiveClock == ClockType.stopwatch
            ? 'زندگی و استراحت آزاد'
            : (_isInLongBreak
                ? 'استراحت طولانی (زندگی)'
                : 'استراحت کوتاه (زندگی)');
        effectiveProjectId = projectId;
        isUntitled = false;
      }
    } else {
      // ورود به کار
      _isInLongBreak = false;
      _currentBreakTargetSeconds = 0;
      targetSeconds = effectiveClock == ClockType.stopwatch
          ? 0
          : (_focusDurationMinutes * 60);

      if (outcome != null && outcome.isWork) {
        effectiveOutcomeId = outcome.id;
        effectiveProjectId = outcome.projectId ?? projectId;
        effectiveTitle = outcome.title;
      } else if (title != null && title.trim().isNotEmpty) {
        effectiveTitle = title.trim();
        effectiveProjectId = projectId;
        isUntitled = effectiveTitle == AppDefaults.untitledTaskTitle;
      } else {
        // بازگشت هوشمند به آخرین کار باز قبل از استراحت (در صورت تکمیل نشدن)
        OutcomeItem? prevOutcome;
        if (_previousWorkOutcomeId != null) {
          prevOutcome = await DatabaseService.instance
              .getOutcomeById(_previousWorkOutcomeId!);
        }
        if (prevOutcome != null && !prevOutcome.isCompleted) {
          effectiveOutcomeId = prevOutcome.id;
          effectiveProjectId = prevOutcome.projectId ?? _previousWorkProjectId;
          effectiveTitle = prevOutcome.title;
          if (effectiveTags.isEmpty) {
            effectiveTags = List.from(_previousWorkTagIds);
          }
          _isGoldenScheduledTaskActive = _previousWorkWasGolden;
        } else if (prevOutcome == null &&
            _previousWorkTitle != null &&
            _previousWorkTitle!.isNotEmpty) {
          effectiveTitle = _previousWorkTitle!;
          effectiveProjectId = projectId ?? _previousWorkProjectId;
          if (effectiveTags.isEmpty) {
            effectiveTags = List.from(_previousWorkTagIds);
          }
          _isGoldenScheduledTaskActive = _previousWorkWasGolden;
        } else {
          effectiveTitle = AppDefaults.untitledTaskTitle;
          effectiveProjectId = projectId;
          isUntitled = true;
          _isGoldenScheduledTaskActive = false;
        }
      }
    }

    // اعمال قانون طلایی وراثت پروژه
    if (effectiveOutcomeId != null) {
      final linkedOutcome =
          outcome ?? await DatabaseService.instance.getOutcomeById(effectiveOutcomeId);
      if (linkedOutcome != null && linkedOutcome.projectId != null) {
        effectiveProjectId = linkedOutcome.projectId;
      }
    }

    final newRecord = TimeRecord(
      id: _uuid.v4(),
      realm: targetRealm,
      clockMode: effectiveClock,
      outcomeId: effectiveOutcomeId,
      projectId: effectiveProjectId,
      titleSnapshot: effectiveTitle,
      isUntitledDraft: isUntitled,
      tagIds: effectiveTags,
      startTime: startTime,
    );

    await DatabaseService.instance.insertTimeRecord(newRecord);
    _activeRecord = newRecord;
    _recordSliceStartedAt = startTime;
    _accumulatedRecordSeconds = 0;
    _activeRecordElapsedSeconds =
        math.max(0, DateTime.now().difference(startTime).inSeconds);

    _phaseStartedAt = startTime;
    _accumulatedPhaseSeconds = 0;
    _lastErgonomicNudgeMessage = null;

    _pomodoroState = _pomodoroState.copyWith(
      realm: targetRealm,
      clockType: effectiveClock,
      status: TimerStatus.running,
      elapsedSeconds: _activeRecordElapsedSeconds,
      targetSeconds: targetSeconds,
      overtimeSeconds: 0,
      lastNudgeAtOvertimeSeconds: 0,
      cycleWorkSeconds: _cycleWorkSeconds,
      earnedShortBreakSeconds: _earnedShortBreakSeconds,
      breakDebtSeconds: _breakDebtSeconds,
      cycleWorkTargetSeconds: _cycleWorkTargetMinutes * 60,
      isInLongBreak: _isInLongBreak,
      activeRecordId: newRecord.id,
      activeOutcomeId: effectiveOutcomeId,
      clearActiveOutcome: effectiveOutcomeId == null,
    );

    await _persistFlowmodoroState();
    if (!isTestMode) {
      MusicPlayerService.instance.onRealmChanged(targetRealm);
    }
    _ensureTickerRunning();
    await refreshAllData();
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
  }

  /// تغییر آنی ماهیت رکورد در حال اجرا (بدون بستن رکورد، از همان ثانیه شروع - چالش ۲)
  Future<void> swapCurrentSliceRealm({DateTime? atTime}) async {
    final current = _activeRecord;
    if (current == null) {
      final target =
          _pomodoroState.isWork ? AppRealm.life : AppRealm.work;
      await switchRealm(target, atTime: atTime);
      return;
    }

    final AppRealm targetRealm =
        current.isWork ? AppRealm.life : AppRealm.work;
    final int elapsed = math.max(
        0, (atTime ?? DateTime.now()).difference(current.startTime).inSeconds);

    // بررسی انطباق پروژه با قلمرو جدید
    String? newProjectId = current.projectId;
    if (newProjectId != null) {
      final p = getProjectById(newProjectId);
      if (p != null && p.realm != targetRealm) {
        newProjectId = null;
      }
    }

    String newTitle = current.titleSnapshot;
    bool newIsUntitled = current.isUntitledDraft;
    if (targetRealm == AppRealm.work && _genericLifeTitles.contains(newTitle)) {
      newTitle = AppDefaults.untitledTaskTitle;
      newIsUntitled = true;
    }

    int newTargetSec = 0;
    if (current.isStopwatch) {
      newTargetSec = 0;
    } else if (targetRealm == AppRealm.life) {
      newTargetSec = _enterLifeBreakTarget();
    } else {
      _isInLongBreak = false;
      _currentBreakTargetSeconds = 0;
      newTargetSec = _focusDurationMinutes * 60;
    }

    int newOvertime = 0;
    TimerStatus newStatus = TimerStatus.running;
    if (!current.isStopwatch && newTargetSec > 0 && elapsed >= newTargetSec) {
      newStatus = TimerStatus.overtime;
      newOvertime = elapsed - newTargetSec;
    }

    final swapped = current.copyWith(
      realm: targetRealm,
      clearOutcomeId: true,
      projectId: newProjectId,
      clearProjectId: newProjectId == null,
      titleSnapshot: newTitle,
      isUntitledDraft: newIsUntitled,
    );

    await DatabaseService.instance
        .updateTimeRecord(swapped, cascadeNotes: true);

    _activeRecord = swapped;
    _activeRecordElapsedSeconds = elapsed;
    _isGoldenScheduledTaskActive = false;
    _lastErgonomicNudgeMessage = null;

    _pomodoroState = _pomodoroState.copyWith(
      realm: targetRealm,
      status: newStatus,
      elapsedSeconds: elapsed,
      targetSeconds: newTargetSec,
      overtimeSeconds: newOvertime,
      lastNudgeAtOvertimeSeconds: newOvertime,
      isInLongBreak: _isInLongBreak,
      cycleWorkSeconds: _cycleWorkSeconds,
      earnedShortBreakSeconds: _earnedShortBreakSeconds,
      breakDebtSeconds: _breakDebtSeconds,
      activeRecordId: swapped.id,
      clearActiveOutcome: true,
    );

    await _persistFlowmodoroState();
    if (!isTestMode) {
      MusicPlayerService.instance.onRealmChanged(targetRealm);
    }
    _ensureTickerRunning();
    await refreshAllData();
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
  }

  /// تغییر یک‌کلیکی قلمرو کار <-> زندگی روی هر رکورد ثبت‌شده (چالش ۲)
  Future<void> swapSavedRecordRealm(String recordId) async {
    if (_activeRecord?.id == recordId) {
      await swapCurrentSliceRealm();
      return;
    }

    final rec = await DatabaseService.instance.getTimeRecordById(recordId);
    if (rec == null) return;

    final AppRealm newRealm = rec.isWork ? AppRealm.life : AppRealm.work;
    String? newProjectId = rec.projectId;
    if (newProjectId != null) {
      final p = getProjectById(newProjectId);
      if (p != null && p.realm != newRealm) {
        newProjectId = null;
      }
    }

    String newTitle = rec.titleSnapshot;
    bool newIsUntitled = rec.isUntitledDraft;
    if (newRealm == AppRealm.work && _genericLifeTitles.contains(newTitle)) {
      newTitle = AppDefaults.untitledTaskTitle;
      newIsUntitled = true;
    }

    final int newEarned = newRealm == AppRealm.work
        ? (rec.durationSeconds ~/ _breakRatio)
        : 0;

    final updated = rec.copyWith(
      realm: newRealm,
      clearOutcomeId: true,
      projectId: newProjectId,
      clearProjectId: newProjectId == null,
      titleSnapshot: newTitle,
      isUntitledDraft: newIsUntitled,
      earnedBreakSeconds: newEarned,
      syncStatus: 'pending',
    );

    await DatabaseService.instance
        .updateTimeRecord(updated, cascadeNotes: true);

    await refreshAllData();
    if (!rec.startTime.isBefore(_lastCycleResetAt)) {
      await _recalculateCurrentCycleBankFromHistory();
    }
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
      unawaited(
          GCalSyncService.instance.syncTimeRecord(updated, projects: _projects));
    }
  }

  /// سوییچ بین پومودورو و کرنومتر در هر دو قلمرو کار و زندگی (چالش ۵)
  Future<void> toggleClockType() async {
    final bool willBeStopwatch = !_pomodoroState.isStopwatch;
    final ClockType newClock =
        willBeStopwatch ? ClockType.stopwatch : ClockType.pomodoro;

    if (willBeStopwatch) {
      _pomodoroState = _pomodoroState.copyWith(
        clockType: ClockType.stopwatch,
        targetSeconds: 0,
        overtimeSeconds: 0,
        status: _pomodoroState.status == TimerStatus.idle
            ? TimerStatus.idle
            : TimerStatus.running,
      );
    } else {
      final int target = _pomodoroState.isWork
          ? (_focusDurationMinutes * 60)
          : (_currentBreakTargetSeconds > 0
              ? _currentBreakTargetSeconds
              : _enterLifeBreakTarget());

      final bool alreadyPast = _pomodoroState.elapsedSeconds >= target;
      final newStatus = _pomodoroState.status == TimerStatus.idle
          ? TimerStatus.idle
          : (alreadyPast ? TimerStatus.overtime : TimerStatus.running);

      _pomodoroState = _pomodoroState.copyWith(
        clockType: ClockType.pomodoro,
        targetSeconds: target,
        overtimeSeconds:
            alreadyPast ? (_pomodoroState.elapsedSeconds - target) : 0,
        status: newStatus,
      );
    }

    if (_activeRecord != null) {
      final updatedRec = _activeRecord!.copyWith(clockMode: newClock);
      await DatabaseService.instance.updateTimeRecord(updatedRec);
      _activeRecord = updatedRec;
    }

    await _persistFlowmodoroState();
    _ensureTickerRunning();
    notifyListeners();
  }

  // ==================== شروع و تغییر فعالیت‌ها و اهداف (Outcomes) ====================

  Future<void> startInstantWork({
    String? title,
    String? projectId,
    List<String>? tagIds,
    OutcomeItem? outcome,
  }) async {
    await switchRealm(
      AppRealm.work,
      outcome: outcome,
      title: title,
      projectId: projectId,
      tagIds: tagIds,
      clockType: ClockType.pomodoro,
    );
  }

  Future<void> startWorkStopwatch({
    String? title,
    String? projectId,
    OutcomeItem? outcome,
  }) async {
    await switchRealm(
      AppRealm.work,
      outcome: outcome,
      title: title ?? (outcome == null ? 'کار با کرنومتر آزاد' : null),
      projectId: projectId,
      clockType: ClockType.stopwatch,
    );
  }

  Future<void> startLifeStopwatch({
    String title = 'زندگی و استراحت آزاد',
    String? projectId,
    OutcomeItem? outcome,
  }) async {
    await switchRealm(
      AppRealm.life,
      outcome: outcome,
      title: outcome == null ? title : null,
      projectId: projectId,
      clockType: ClockType.stopwatch,
    );
  }

  /// شروع یا تغییر به یک کار/هدف (OutcomeItem) در همان قلمرو یا قلمرو متناظر
  Future<void> startOrSwitchToOutcome(
    OutcomeItem outcome, {
    List<String>? tagIds,
  }) async {
    if (_activeRecord == null ||
        _activeRecord!.realm != outcome.realm ||
        _pomodoroState.status == TimerStatus.idle) {
      await switchRealm(
        outcome.realm,
        outcome: outcome,
        tagIds: tagIds,
      );
      return;
    }

    // اگر در همین قلمرو هستیم: رکورد قبلی را ببند و رکورد جدید را با حفظ فاز جاری باز کن
    await _closeActiveRecordAndUpdateBank();
    final now = DateTime.now();

    final newRecord = TimeRecord(
      id: _uuid.v4(),
      realm: outcome.realm,
      clockMode: _pomodoroState.clockType,
      outcomeId: outcome.id,
      projectId: outcome.projectId, // قانون وراثت پروژه
      titleSnapshot: outcome.title,
      isUntitledDraft: false,
      tagIds: tagIds ?? const [],
      startTime: now,
    );

    await DatabaseService.instance.insertTimeRecord(newRecord);
    _activeRecord = newRecord;
    _recordSliceStartedAt = now;
    _accumulatedRecordSeconds = 0;
    _activeRecordElapsedSeconds = 0;
    _isGoldenScheduledTaskActive = false;

    _pomodoroState = _pomodoroState.copyWith(
      cycleWorkSeconds: _cycleWorkSeconds,
      earnedShortBreakSeconds: _earnedShortBreakSeconds,
      breakDebtSeconds: _breakDebtSeconds,
      isInLongBreak: _isInLongBreak,
      activeRecordId: newRecord.id,
      activeOutcomeId: outcome.id,
    );

    await _persistFlowmodoroState();
    _ensureTickerRunning();
    await refreshAllData();
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
  }

  /// ساخت کار/هدف (OutcomeItem) جدید و شروع تایمر روی آن (یا اتصال به رکورد جاری)
  Future<OutcomeItem> createAndStartOutcome({
    required AppRealm realm,
    required String title,
    String? projectId,
    String description = '',
    List<String>? tagIds,
    bool attachToCurrentRecordIfUntitled = false,
  }) async {
    final cleanTitle =
        title.trim().isEmpty ? AppDefaults.untitledTaskTitle : title.trim();

    final newOutcome = OutcomeItem(
      id: _uuid.v4(),
      realm: realm,
      projectId: projectId,
      title: cleanTitle,
      description: description,
      isCompleted: false,
    );

    await DatabaseService.instance.insertOutcome(newOutcome);
    await refreshAllData();

    if (attachToCurrentRecordIfUntitled &&
        _activeRecord != null &&
        _activeRecord!.realm == realm &&
        _activeRecord!.isUntitledDraft) {
      await updateActiveRecordMetadata(
        title: newOutcome.title,
        outcomeId: newOutcome.id,
        projectId: newOutcome.projectId,
        clearProjectId: newOutcome.projectId == null,
        tagIds: tagIds ?? _activeRecord!.tagIds,
      );
    } else {
      await startOrSwitchToOutcome(newOutcome, tagIds: tagIds);
    }

    return newOutcome;
  }

  Future<void> updateActiveRecordMetadata({
    required String title,
    String? projectId,
    bool clearProjectId = false,
    String? outcomeId,
    bool clearOutcomeId = false,
    required List<String> tagIds,
    bool createOutcomeIfMissing = true,
  }) async {
    final current = _activeRecord;
    if (current == null) return;

    final cleanTitle =
        title.trim().isEmpty ? AppDefaults.untitledTaskTitle : title.trim();
    final bool isUntitled = cleanTitle == AppDefaults.untitledTaskTitle;

    if (current.titleSnapshot != cleanTitle) {
      _isGoldenScheduledTaskActive = false;
    }

    String? effectiveOutcomeId =
        clearOutcomeId ? null : (outcomeId ?? current.outcomeId);
    String? effectiveProjectId =
        clearProjectId ? null : (projectId ?? current.projectId);

    if (effectiveOutcomeId != null) {
      final outcome =
          await DatabaseService.instance.getOutcomeById(effectiveOutcomeId);
      if (outcome != null && outcome.projectId != null) {
        effectiveProjectId = outcome.projectId;
      }
    } else if (createOutcomeIfMissing &&
        !isUntitled &&
        !_genericLifeTitles.contains(cleanTitle)) {
      final newOutcome = OutcomeItem(
        id: _uuid.v4(),
        realm: current.realm,
        projectId: effectiveProjectId,
        title: cleanTitle,
        isCompleted: false,
      );
      await DatabaseService.instance.insertOutcome(newOutcome);
      effectiveOutcomeId = newOutcome.id;
    }

    final updated = current.copyWith(
      outcomeId: effectiveOutcomeId,
      clearOutcomeId: effectiveOutcomeId == null,
      projectId: effectiveProjectId,
      clearProjectId: effectiveProjectId == null,
      titleSnapshot: cleanTitle,
      isUntitledDraft: isUntitled,
      tagIds: tagIds,
    );

    await DatabaseService.instance
        .updateTimeRecord(updated, cascadeNotes: true);
    _activeRecord = updated;
    _pomodoroState = _pomodoroState.copyWith(
      activeOutcomeId: effectiveOutcomeId,
      clearActiveOutcome: effectiveOutcomeId == null,
    );

    await refreshAllData();
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
  }

  Future<void> switchRecordMidSession({
    required String newTitle,
    String? projectId,
    OutcomeItem? outcome,
    required List<String> tagIds,
  }) async {
    if (outcome != null) {
      await startOrSwitchToOutcome(outcome, tagIds: tagIds);
      return;
    }

    final cleanTitle = newTitle.trim();
    if (cleanTitle.isNotEmpty && cleanTitle != AppDefaults.untitledTaskTitle) {
      await createAndStartOutcome(
        realm: _pomodoroState.realm,
        title: cleanTitle,
        projectId: projectId,
        tagIds: tagIds,
      );
      return;
    }

    // سوییچ به یک رکورد بدون عنوان جدید در همین قلمرو
    await _closeActiveRecordAndUpdateBank();
    final now = DateTime.now();
    final nextRec = TimeRecord(
      id: _uuid.v4(),
      realm: _pomodoroState.realm,
      clockMode: _pomodoroState.clockType,
      projectId: projectId,
      titleSnapshot: AppDefaults.untitledTaskTitle,
      isUntitledDraft: true,
      tagIds: tagIds,
      startTime: now,
    );

    await DatabaseService.instance.insertTimeRecord(nextRec);
    _activeRecord = nextRec;
    _recordSliceStartedAt = now;
    _accumulatedRecordSeconds = 0;
    _activeRecordElapsedSeconds = 0;
    _isGoldenScheduledTaskActive = false;

    _pomodoroState = _pomodoroState.copyWith(
      cycleWorkSeconds: _cycleWorkSeconds,
      earnedShortBreakSeconds: _earnedShortBreakSeconds,
      breakDebtSeconds: _breakDebtSeconds,
      activeRecordId: nextRec.id,
      clearActiveOutcome: true,
    );

    await _persistFlowmodoroState();
    _ensureTickerRunning();
    await refreshAllData();
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
  }

  Future<void> stopAndResetSession() async {
    _ticker?.cancel();
    await _closeActiveRecordAndUpdateBank();
    _phaseStartedAt = null;
    _accumulatedPhaseSeconds = 0;
    _lastErgonomicNudgeMessage = null;

    _pomodoroState = PomodoroState(
      realm: _pomodoroState.realm,
      clockType: _pomodoroState.clockType,
      status: TimerStatus.idle,
      elapsedSeconds: 0,
      targetSeconds: _pomodoroState.isStopwatch
          ? 0
          : (_focusDurationMinutes * 60),
      cycleWorkSeconds: _cycleWorkSeconds,
      earnedShortBreakSeconds: _earnedShortBreakSeconds,
      breakDebtSeconds: _breakDebtSeconds,
      cycleWorkTargetSeconds: _cycleWorkTargetMinutes * 60,
      isInLongBreak: _isInLongBreak,
      windowPosture: _pomodoroState.windowPosture,
    );

    await _persistFlowmodoroState();
    await refreshAllData();
  }

  // ==================== مدیریت کارها / اهداف (Outcomes CRUD) ====================

  Future<void> saveOutcome(OutcomeItem outcome) async {
    final existing = await DatabaseService.instance.getOutcomeById(outcome.id);
    if (existing == null) {
      await DatabaseService.instance.insertOutcome(outcome);
    } else {
      await DatabaseService.instance.updateOutcome(outcome);
    }
    await refreshAllData();
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
  }

  Future<void> markOutcomeCompleted(String id) async {
    await DatabaseService.instance.markOutcomeCompleted(id);
    if (_previousWorkOutcomeId == id) {
      _previousWorkOutcomeId = null;
      _previousWorkTitle = null;
    }
    await refreshAllData();
  }

  Future<void> reopenOutcome(String id) async {
    await DatabaseService.instance.reopenOutcome(id);
    await refreshAllData();
  }

  Future<void> deleteOutcome(String id) async {
    await DatabaseService.instance.deleteOutcome(id);
    if (_previousWorkOutcomeId == id) {
      _previousWorkOutcomeId = null;
      _previousWorkTitle = null;
    }
    await refreshAllData();
  }

  // ==================== مدیریت یادداشت‌های حین کار (SessionNotes) ====================

  Future<void> saveSessionNote(SessionNote note) async {
    await DatabaseService.instance.insertSessionNote(note);
    _sessionNotes = await DatabaseService.instance.getAllSessionNotes();
    notifyListeners();
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
  }

  Future<void> deleteSessionNote(String id) async {
    await DatabaseService.instance.deleteSessionNote(id);
    _sessionNotes = await DatabaseService.instance.getAllSessionNotes();
    notifyListeners();
  }

  Future<String?> exportSessionNotesToExcel(
      [List<SessionNote>? customList]) async {
    return await ExcelExportService.instance.exportSessionNotesToExcel(
      notes: customList ?? _sessionNotes,
      outcomes: _outcomes,
      records: _timeRecords,
      projects: _projects,
    );
  }

  // ==================== مدیریت پنجره ویندوز ====================

  Future<void> setWindowPosture(WindowPosture posture,
      {bool expanded = false}) async {
    _isQuickMenuExpanded = expanded;
    _pomodoroState = _pomodoroState.copyWith(windowPosture: posture);
    notifyListeners();
    if (isTestMode) return;

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
    if (!isTestMode && _pomodoroState.windowPosture == WindowPosture.floatingCircle) {
      await PlatformHelper.updateFloatingSheetExpansion(expanded);
    }
  }

  // ==================== تکمیل نواقص، ویرایش با ممیزی و رکوردهای دستی ====================

  Future<void> completeUntitledDraft({
    required String id,
    required String title,
    String? existingOutcomeId,
    String? projectId,
    AppRealm? newRealm,
    required List<String> tagIds,
  }) async {
    final existing = await DatabaseService.instance.getTimeRecordById(id);
    if (existing == null) return;

    final AppRealm effectiveRealm = newRealm ?? existing.realm;
    String? targetOutcomeId = existingOutcomeId;
    String? targetProjectId = projectId;

    if (targetOutcomeId == null &&
        title.trim().isNotEmpty &&
        title.trim() != AppDefaults.untitledTaskTitle) {
      final createdOutcome = OutcomeItem(
        id: _uuid.v4(),
        realm: effectiveRealm,
        projectId: projectId,
        title: title.trim(),
        isCompleted: false,
      );
      await DatabaseService.instance.insertOutcome(createdOutcome);
      targetOutcomeId = createdOutcome.id;
      targetProjectId = createdOutcome.projectId;
    }

    final updated = await DatabaseService.instance.updateTimeRecordWithAudit(
      id: id,
      newTitle: title,
      newRealm: effectiveRealm,
      newOutcomeId: targetOutcomeId,
      clearOutcomeId: targetOutcomeId == null,
      newProjectId: targetProjectId,
      clearProjectId: targetProjectId == null,
      newTagIds: tagIds,
      newStartTime: existing.startTime,
      newEndTime: existing.endTime ??
          existing.startTime.add(Duration(seconds: existing.durationSeconds)),
      newDurationSeconds: existing.durationSeconds,
    );

    await refreshAllData();
    if (existing.realm != effectiveRealm &&
        !existing.startTime.isBefore(_lastCycleResetAt)) {
      await _recalculateCurrentCycleBankFromHistory();
    }
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
      unawaited(
          GCalSyncService.instance.syncTimeRecord(updated, projects: _projects));
    }
  }

  Future<void> updateTimeRecordTimes({
    required String id,
    required DateTime newStartTime,
    required DateTime newEndTime,
    String? editNote,
  }) async {
    final existing = await DatabaseService.instance.getTimeRecordById(id);
    if (existing == null) return;
    final int newDurationSec =
        math.max(1, newEndTime.difference(newStartTime).inSeconds);
    final tags = existing.tagIds.toList();
    if (!tags.contains('دستی') && !tags.contains('manual')) {
      tags.add('دستی');
    }

    await editTimeRecordWithAudit(
      id: id,
      newTitle: existing.titleSnapshot,
      newRealm: existing.realm,
      newOutcomeId: existing.outcomeId,
      clearOutcomeId: existing.outcomeId == null,
      newProjectId: existing.projectId,
      clearProjectId: existing.projectId == null,
      newTagIds: tags,
      newStartTime: newStartTime,
      newEndTime: newEndTime,
      newDurationSeconds: newDurationSec,
      editNote: editNote ?? 'جابه‌جایی در تقویم',
    );
  }

  Future<void> editTimeRecordWithAudit({
    required String id,
    required String newTitle,
    AppRealm? newRealm,
    String? newOutcomeId,
    bool clearOutcomeId = false,
    String? newProjectId,
    bool clearProjectId = false,
    required List<String> newTagIds,
    required DateTime newStartTime,
    required DateTime newEndTime,
    required int newDurationSeconds,
    String? editNote,
  }) async {
    final updated = await DatabaseService.instance.updateTimeRecordWithAudit(
      id: id,
      newTitle: newTitle,
      newRealm: newRealm,
      newOutcomeId: newOutcomeId,
      clearOutcomeId: clearOutcomeId,
      newProjectId: newProjectId,
      clearProjectId: clearProjectId,
      newTagIds: newTagIds,
      newStartTime: newStartTime,
      newEndTime: newEndTime,
      newDurationSeconds: newDurationSeconds,
      editNote: editNote,
    );

    await refreshAllData();
    if (!newStartTime.isBefore(_lastCycleResetAt)) {
      await _recalculateCurrentCycleBankFromHistory();
    }
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
      unawaited(
          GCalSyncService.instance.syncTimeRecord(updated, projects: _projects));
    }
  }

  Future<void> deleteTimeRecord(String id) async {
    final existing = await DatabaseService.instance.getTimeRecordById(id);
    await DatabaseService.instance.deleteTimeRecord(id);
    if (_activeRecord?.id == id) {
      _activeRecord = null;
      _ticker?.cancel();
      _pomodoroState = _pomodoroState.copyWith(
        status: TimerStatus.idle,
        elapsedSeconds: 0,
        overtimeSeconds: 0,
        clearActiveRecord: true,
        clearActiveOutcome: true,
      );
    }
    await refreshAllData();
    if (existing != null && !existing.startTime.isBefore(_lastCycleResetAt)) {
      await _recalculateCurrentCycleBankFromHistory();
    }
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
  }

  Future<void> createManualTimeRecord({
    required AppRealm realm,
    required ClockType clockMode,
    required String title,
    String? outcomeId,
    String? projectId,
    required DateTime startTime,
    required DateTime endTime,
    List<String>? tagIds,
  }) async {
    final now = DateTime.now();
    final int durationSeconds =
        math.max(1, endTime.difference(startTime).inSeconds);
    final tags = (tagIds ?? []).toList();
    if (!tags.contains('دستی') && !tags.contains('manual')) {
      tags.add('دستی');
    }

    String? resolvedProjectId = projectId;
    if (outcomeId != null) {
      final outcome = await DatabaseService.instance.getOutcomeById(outcomeId);
      if (outcome != null && outcome.projectId != null) {
        resolvedProjectId = outcome.projectId;
      }
    }

    final record = TimeRecord(
      id: _uuid.v4(),
      realm: realm,
      clockMode: clockMode,
      outcomeId: outcomeId,
      projectId: resolvedProjectId,
      titleSnapshot: title.trim().isEmpty ? 'گزارش دستی' : title.trim(),
      isUntitledDraft: false,
      tagIds: tags,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: durationSeconds,
      earnedBreakSeconds:
          realm == AppRealm.work ? (durationSeconds ~/ _breakRatio) : 0,
      isEdited: true,
      editedAt: now,
      editNote: 'ثبت دستی از تقویم',
    );

    await DatabaseService.instance.insertTimeRecord(record);
    await refreshAllData();
    if (!startTime.isBefore(_lastCycleResetAt)) {
      await _recalculateCurrentCycleBankFromHistory();
    }
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
  }

  // ==================== پروژه‌ها، تگ‌ها و تقویم ====================

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
    if (!isTestMode) {
      unawaited(GCalSyncService.instance.pushScheduledBlockToGCal(block).then((ok) {
        if (ok) refreshAllData();
      }));
    }
    await refreshAllData();
  }

  Future<void> deleteScheduledBlock(String id) async {
    await DatabaseService.instance.deleteScheduledBlock(id);
    await refreshAllData();
  }

  Future<void> syncGoogleCalendar() async {
    final now = DateTime.now();
    final minDate = now.subtract(const Duration(days: 14));
    final maxDate = now.add(const Duration(days: 14));
    await GCalSyncService.instance.fetchScheduledBlocksFromGCal(
      timeMin: minDate,
      timeMax: maxDate,
      projects: _projects,
    );
    await refreshAllData();
  }

  // ==================== تنظیمات ====================

  Future<void> updateTimerSettings({
    required int focusMinutes,
    required int shortBreakMinutes,
    required int longBreakMinutes,
    int? breakRatio,
    int? cycleWorkTargetMinutes,
    int? cycleAutoResetMinutes,
  }) async {
    _focusDurationMinutes = focusMinutes.clamp(1, 240);
    _shortBreakDurationMinutes = shortBreakMinutes.clamp(1, 60);
    _longBreakDurationMinutes = longBreakMinutes.clamp(5, 240);
    if (breakRatio != null) {
      _breakRatio = breakRatio.clamp(1, 20);
    }
    if (cycleWorkTargetMinutes != null) {
      _cycleWorkTargetMinutes = cycleWorkTargetMinutes.clamp(10, 600);
    }
    if (cycleAutoResetMinutes != null) {
      _cycleAutoResetMinutes = cycleAutoResetMinutes.clamp(15, 600);
    }

    final db = DatabaseService.instance;
    await Future.wait([
      db.setSetting(AppDefaults.settingKeyFocusDuration,
          _focusDurationMinutes.toString()),
      db.setSetting(AppDefaults.settingKeyShortBreakDuration,
          _shortBreakDurationMinutes.toString()),
      db.setSetting(AppDefaults.settingKeyLongBreakDuration,
          _longBreakDurationMinutes.toString()),
      db.setSetting(AppDefaults.settingKeyBreakRatio, _breakRatio.toString()),
      db.setSetting(AppDefaults.settingKeyCycleWorkTargetMinutes,
          _cycleWorkTargetMinutes.toString()),
      db.setSetting(AppDefaults.settingKeyCycleAutoResetMinutes,
          _cycleAutoResetMinutes.toString()),
    ]);

    _pomodoroState = _pomodoroState.copyWith(
      cycleWorkTargetSeconds: _cycleWorkTargetMinutes * 60,
      targetSeconds: (_pomodoroState.status == TimerStatus.idle &&
              !_pomodoroState.isStopwatch)
          ? _focusDurationMinutes * 60
          : _pomodoroState.targetSeconds,
    );
    notifyListeners();
  }

  Future<void> updateTxtLogPath(String newPath) async {
    if (newPath.trim().isEmpty) return;
    _txtLogPath = newPath.trim();
    await DatabaseService.instance
        .setSetting(AppDefaults.settingKeyTxtPath, _txtLogPath);
    if (!isTestMode) {
      await TxtLoggerService.instance.syncTxtFile();
    }
    notifyListeners();
  }

  Future<void> updateGCalToken(String token) async {
    _gcalToken = token.trim();
    await DatabaseService.instance
        .setSetting(AppDefaults.settingKeyGCalToken, _gcalToken);
    notifyListeners();
  }

  Future<void> updateGCalCalendars({
    required String token,
    required String workPlanId,
    required String lifePlanId,
    required String workLogId,
    required String lifeLogId,
  }) async {
    _gcalToken = token.trim();
    _workPlanCalendarId =
        workPlanId.trim().isEmpty ? 'primary' : workPlanId.trim();
    _lifePlanCalendarId = lifePlanId.trim();
    _workLogCalendarId =
        workLogId.trim().isEmpty ? 'primary' : workLogId.trim();
    _lifeLogCalendarId = lifeLogId.trim();

    final db = DatabaseService.instance;
    await Future.wait([
      db.setSetting(AppDefaults.settingKeyGCalToken, _gcalToken),
      db.setSetting(
          AppDefaults.settingKeyPlanCalendarId, _workPlanCalendarId),
      db.setSetting(
          AppDefaults.settingKeyLifePlanCalendarId, _lifePlanCalendarId),
      db.setSetting(
          AppDefaults.settingKeyWorkLogCalendarId, _workLogCalendarId),
      db.setSetting(
          AppDefaults.settingKeyLifeLogCalendarId, _lifeLogCalendarId),
    ]);
    notifyListeners();
  }

  Future<String?> exportRecordsToExcel(List<TimeRecord> filteredRecords) async {
    return await ExcelExportService.instance.exportTimesheetToExcel(
      records: filteredRecords,
      outcomes: _outcomes,
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
