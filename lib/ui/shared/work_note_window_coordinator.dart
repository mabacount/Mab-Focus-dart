import 'dart:async';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants.dart';
import '../../core/platform_helper.dart';

/// هماهنگ‌کننده پنجره مستقل یادداشت حین فعالیت:
/// یک پنجره مخفی را در پس‌زمینه پیش‌گرم (Pre-warm) می‌کند تا بازشدن پنجره یادداشت
/// بی‌درنگ و بدون هیچ پرش/صفحه سفید انجام شود.
class WorkNoteWindowCoordinator {
  WorkNoteWindowCoordinator._();

  static final WorkNoteWindowCoordinator instance = WorkNoteWindowCoordinator._();

  static const String syncChannelName = 'work_notes_sync';
  static const String methodHostReady = 'host_ready';
  static const String methodNoteAdded = 'note_added';
  static const String methodNoteWindowHidden = 'note_window_hidden';
  static const String methodOpenNote = 'open_note';
  static const String methodShutdown = 'shutdown';

  WindowController? _hostController;
  Completer<void>? _readyCompleter;
  Future<WindowController?>? _warmupFuture;
  bool _channelRegistered = false;
  bool _isDisposing = false;
  final Set<VoidCallback> _noteAddedListeners = {};

  @visibleForTesting
  Future<WindowController> Function(WindowConfiguration config)?
      windowCreatorOverride;

  @visibleForTesting
  Future<dynamic> Function(WindowController controller, String method, dynamic args)?
      invokeHostOverride;

  @visibleForTesting
  bool? isDesktopOverride;

  bool get _isDesktop => isDesktopOverride ?? PlatformHelper.isDesktop;

  bool get hasLiveHostWindow => _hostController != null;

  bool get isHostReady => _readyCompleter?.isCompleted == true;

  void addOnNoteAddedListener(VoidCallback listener) {
    _noteAddedListeners.add(listener);
  }

  void removeOnNoteAddedListener(VoidCallback listener) {
    _noteAddedListeners.remove(listener);
  }

  /// ثبت کانال ارتباطی یک‌طرفه بین پنجره یادداشت و پنجره اصلی
  void ensureChannelRegistered() {
    if (!_isDesktop || _channelRegistered) return;
    _channelRegistered = true;
    try {
      const channel = WindowMethodChannel(
        syncChannelName,
        mode: ChannelMode.unidirectional,
      );
      channel.setMethodCallHandler((call) async {
        if (call.method == methodHostReady) {
          final args = call.arguments;
          final readyWindowId = args is Map ? args['windowId'] as String? : null;
          if (readyWindowId == null ||
              _hostController == null ||
              readyWindowId == _hostController!.windowId) {
            if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
              _readyCompleter!.complete();
            }
          }
          return null;
        }
        if (call.method == methodNoteAdded) {
          for (final listener in List<VoidCallback>.from(_noteAddedListeners)) {
            listener();
          }
          return null;
        }
        if (call.method == methodNoteWindowHidden) {
          return null;
        }
        return null;
      });
    } catch (e) {
      _channelRegistered = false;
      debugPrint('Failed to register work_notes_sync channel: $e');
    }
  }

  /// ساخت و آماده‌سازی مخفی پنجره مستقل در پس‌زمینه (بدون نمایش)
  Future<WindowController?> prewarm() {
    if (!_isDesktop || _isDisposing) return Future.value(null);
    ensureChannelRegistered();

    if (_hostController != null && _readyCompleter != null) {
      return Future.value(_hostController);
    }
    if (_warmupFuture != null) {
      return _warmupFuture!;
    }

    _warmupFuture = _createHiddenHost();
    return _warmupFuture!;
  }

  Future<WindowController?> _createHiddenHost() async {
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;
    try {
      final creator = windowCreatorOverride ?? WindowController.create;
      final controller = await creator(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            'type': 'work_note',
            'prewarm': true,
            'realm': 'work',
            'taskTitle': AppDefaults.untitledTaskTitle,
          }),
        ),
      );
      if (_isDisposing) {
        unawaited(_invokeHost(controller, methodShutdown, null).catchError((_) {}));
        return null;
      }
      _hostController = controller;
      return controller;
    } catch (e) {
      debugPrint('Failed to prewarm work note standalone window: $e');
      _hostController = null;
      _readyCompleter = null;
      return null;
    } finally {
      _warmupFuture = null;
    }
  }

  Future<dynamic> _invokeHost(
    WindowController controller,
    String method,
    dynamic args,
  ) {
    final override = invokeHostOverride;
    if (override != null) {
      return override(controller, method, args);
    }
    return controller.invokeMethod(method, args);
  }

  /// نمایش فوری پنجره مستقل با کانتکست فعالیت جاری؛ پیش از آماده شدن کامل و رندر فریم، نمایش داده نمی‌شود
  Future<bool> openWorkNote(Map<String, dynamic> payload) async {
    if (!_isDesktop || _isDisposing) return false;
    ensureChannelRegistered();

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final controller = await prewarm();
        final readyCompleter = _readyCompleter;
        if (controller == null || readyCompleter == null) {
          _resetHostState();
          continue;
        }

        await readyCompleter.future.timeout(const Duration(seconds: 6));
        await _invokeHost(controller, methodOpenNote, payload);
        return true;
      } catch (e) {
        debugPrint('WorkNoteWindowCoordinator open attempt $attempt failed: $e');
        _resetHostState();
      }
    }
    return false;
  }

  /// بستن قطعی پنجره مخفی هنگام خروج از برنامه اصلی
  Future<void> disposeHostWindow() async {
    _isDisposing = true;
    final controller = _hostController;
    _resetHostState();
    if (controller == null) return;
    try {
      await _invokeHost(controller, methodShutdown, null)
          .timeout(const Duration(milliseconds: 350));
    } catch (_) {}
  }

  void _resetHostState() {
    _hostController = null;
    _readyCompleter = null;
    _warmupFuture = null;
  }

  @visibleForTesting
  void resetForTest() {
    _resetHostState();
    _channelRegistered = false;
    _isDisposing = false;
    _noteAddedListeners.clear();
    windowCreatorOverride = null;
    invokeHostOverride = null;
    isDesktopOverride = null;
  }
}
