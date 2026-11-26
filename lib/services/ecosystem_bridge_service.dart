import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';
import 'database_service.dart';
import 'ecosystem_core_service.dart';

/// سرویس پل ارتباطی زنده اکوسیستم (اتصال دوطرفه بین Mab-Focus و Mab-Compass)
class EcosystemBridgeService {
  static final EcosystemBridgeService instance =
      EcosystemBridgeService._init();
  EcosystemBridgeService._init();

  DirectoryWatcher? _watcher;
  StreamSubscription<WatchEvent>? _subscription;
  DirectoryWatcher? _coreWatcher;
  StreamSubscription<WatchEvent>? _coreSubscription;
  Timer? _debounceTimer;
  Timer? _coreDebounceTimer;
  DateTime? _lastInternalWrite;
  DateTime? _lastInternalCoreWrite;
  String? _cachedDbDirPath;
  DateTime? _lastSyncWriteTime;

  /// کالبک هنگام تشخیص تغییرات بیرونی در دیتابیس توسط Mab-Compass
  Future<void> Function()? onExternalDatabaseChanged;

  /// ثبت زمان آخرین عملیات نوشتن داخلی توسط مب‌فوکس جهت جلوگیری از چرخه بی‌پایان رفرش
  void notifyInternalWrite() {
    _lastInternalWrite = DateTime.now();
  }

  bool get isRecentInternalWrite {
    if (_lastInternalWrite == null) return false;
    return DateTime.now().difference(_lastInternalWrite!).inMilliseconds < 1500;
  }

  void notifyInternalCoreWrite() {
    _lastInternalCoreWrite = DateTime.now();
  }

  bool get isRecentInternalCoreWrite {
    if (_lastInternalCoreWrite == null) return false;
    return DateTime.now().difference(_lastInternalCoreWrite!).inMilliseconds <
        1500;
  }

  /// راه‌اندازی ناظر دیتابیس (DirectoryWatcher) روی پوشه دیتابیس محلی و پوشه هسته مرکزی اکوسیستم
  Future<void> startDatabaseWatcher({
    required Future<void> Function() onExternalChange,
  }) async {
    onExternalDatabaseChanged = onExternalChange;

    try {
      final dbDirPath =
          await DatabaseService.instance.getDatabaseDirectoryPath();
      _cachedDbDirPath = dbDirPath;

      await stopDatabaseWatcher();

      final dir = Directory(dbDirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _watcher = DirectoryWatcher(dbDirPath);
      _subscription = _watcher!.events.listen(
        (event) {
          final path = event.path.toLowerCase();
          if (path.endsWith('.db') || path.endsWith('.db-wal')) {
            // اگر تغییر توسط خود مب‌فوکس در ۱.۵ ثانیه اخیر انجام شده، نادیده بگیر
            if (isRecentInternalWrite) return;

            // دیبانس ۸۰۰ میلی‌ثانیه‌ای برای تجمیع تراکنش‌ها
            _debounceTimer?.cancel();
            _debounceTimer =
                Timer(const Duration(milliseconds: 800), () async {
              if (isRecentInternalWrite) return;
              debugPrint(
                  '[EcosystemBridge] External database change detected: $path');
              try {
                await DatabaseService.instance.reconcileWithEcosystemCore();
                await onExternalDatabaseChanged?.call();
              } catch (e) {
                debugPrint('[EcosystemBridge] Error refreshing data: $e');
              }
            });
          }
        },
        onError: (err) {
          debugPrint('[EcosystemBridge] DirectoryWatcher error: $err');
        },
      );

      // ناظر پوشه هسته مرکزی (%APPDATA%/MabEcosystem) برای دریافت آنی تغییرات Mab-Compass
      try {
        final coreDirPath =
            await EcosystemCoreService.instance.getCoreDirectoryPath();
        final coreDir = Directory(coreDirPath);
        if (!await coreDir.exists()) {
          await coreDir.create(recursive: true);
        }
        _coreWatcher = DirectoryWatcher(coreDirPath);
        _coreSubscription = _coreWatcher!.events.listen(
          (event) {
            final path = event.path.toLowerCase();
            if (path.endsWith('.db') || path.endsWith('.db-wal')) {
              if (isRecentInternalCoreWrite) return;
              _coreDebounceTimer?.cancel();
              _coreDebounceTimer =
                  Timer(const Duration(milliseconds: 800), () async {
                if (isRecentInternalCoreWrite) return;
                debugPrint(
                    '[EcosystemBridge] Core ecosystem DB change detected: $path');
                try {
                  final changed = await DatabaseService.instance
                      .reconcileWithEcosystemCore();
                  if (changed) {
                    await onExternalDatabaseChanged?.call();
                  }
                } catch (e) {
                  debugPrint('[EcosystemBridge] Core reconcile error: $e');
                }
              });
            }
          },
          onError: (err) {
            debugPrint('[EcosystemBridge] Core DirectoryWatcher error: $err');
          },
        );
        debugPrint(
            '[EcosystemBridge] Watching core ecosystem folder: $coreDirPath');
      } catch (e) {
        debugPrint('[EcosystemBridge] Core watcher setup warning: $e');
      }

      debugPrint('[EcosystemBridge] Watching database folder: $dbDirPath');
    } catch (e) {
      debugPrint('[EcosystemBridge] Failed to start watcher: $e');
    }
  }

  /// توقف ناظر
  Future<void> stopDatabaseWatcher() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _coreDebounceTimer?.cancel();
    _coreDebounceTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _watcher = null;
    await _coreSubscription?.cancel();
    _coreSubscription = null;
    _coreWatcher = null;
  }

  /// بروزرسانی فایل وضعیت زنده پومودورو (Runtime Bridge File: mab_ecosystem_sync.json)
  Future<void> syncPomodoroState({
    required bool isRunning,
    String? projectId,
    String? projectName,
    String? taskTitle,
    required int remainingSeconds,
    String? realm,
    String? status,
    int? elapsedSeconds,
    int? targetSeconds,
    int? breakBankSeconds,
    bool force = false,
  }) async {
    final now = DateTime.now();
    // جلوگیری از نوشتن‌های بیش‌ازحد در هر ثانیه (حداکثر یک‌بار در هر ۱.۵ ثانیه مگر با force)
    if (!force &&
        _lastSyncWriteTime != null &&
        now.difference(_lastSyncWriteTime!).inMilliseconds < 1500) {
      return;
    }
    _lastSyncWriteTime = now;

    try {
      final dbDirPath = _cachedDbDirPath ??
          await DatabaseService.instance.getDatabaseDirectoryPath();
      final syncFilePath = p.join(dbDirPath, 'mab_ecosystem_sync.json');

      final payload = {
        'active_pomodoro': {
          'is_running': isRunning,
          'project_id': projectId,
          'project_name': projectName,
          'task_title': taskTitle,
          'remaining_seconds': remainingSeconds,
          if (realm != null) 'realm': realm,
          if (status != null) 'status': status,
          if (elapsedSeconds != null) 'elapsed_seconds': elapsedSeconds,
          if (targetSeconds != null) 'target_seconds': targetSeconds,
          if (breakBankSeconds != null) 'break_bank_seconds': breakBankSeconds,
        },
        'last_synced_at': now.toIso8601String(),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      final file = File(syncFilePath);
      await file.writeAsString(jsonStr, flush: true);
    } catch (e) {
      debugPrint('[EcosystemBridge] Failed to write ecosystem sync file: $e');
    }
  }
}
