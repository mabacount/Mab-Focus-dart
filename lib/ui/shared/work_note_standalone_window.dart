import 'dart:async';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants.dart';
import '../../core/jalali_date.dart';
import '../../models/pomodoro_state.dart';
import '../../models/session_note.dart';
import '../../services/database_service.dart';
import 'work_note_window_coordinator.dart';

class WorkNoteStandaloneApp extends StatelessWidget {
  final WindowController windowController;
  final AppRealm realm;
  final String? timeRecordId;
  final String? outcomeId;
  final String? projectId;
  final String taskTitle;
  final String? projectName;
  final String? projectColorHex;
  final bool startHidden;

  const WorkNoteStandaloneApp({
    super.key,
    required this.windowController,
    this.realm = AppRealm.work,
    this.timeRecordId,
    this.outcomeId,
    this.projectId,
    required this.taskTitle,
    this.projectName,
    this.projectColorHex,
    this.startHidden = false,
  });

  @override
  Widget build(BuildContext context) {
    final baseTextTheme =
        GoogleFonts.vazirmatnTextTheme(ThemeData.dark().textTheme);

    return MaterialApp(
      title: 'یادداشت حین فعالیت',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [
        Locale('fa', 'IR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(
          surface: AppColors.surface,
        ),
        textTheme: baseTextTheme,
      ),
      home: WorkNoteStandaloneView(
        windowController: windowController,
        realm: realm,
        timeRecordId: timeRecordId,
        outcomeId: outcomeId,
        projectId: projectId,
        taskTitle: taskTitle,
        projectName: projectName,
        projectColorHex: projectColorHex,
        startHidden: startHidden,
      ),
    );
  }
}

class WorkNoteStandaloneView extends StatefulWidget {
  final WindowController windowController;
  final AppRealm realm;
  final String? timeRecordId;
  final String? outcomeId;
  final String? projectId;
  final String taskTitle;
  final String? projectName;
  final String? projectColorHex;
  final bool startHidden;
  final bool manageNativeWindow;
  final bool useGoogleFonts;

  const WorkNoteStandaloneView({
    super.key,
    required this.windowController,
    this.realm = AppRealm.work,
    this.timeRecordId,
    this.outcomeId,
    this.projectId,
    required this.taskTitle,
    this.projectName,
    this.projectColorHex,
    this.startHidden = false,
    this.manageNativeWindow = true,
    this.useGoogleFonts = true,
  });

  @override
  State<WorkNoteStandaloneView> createState() => WorkNoteStandaloneViewState();
}

class WorkNoteStandaloneViewState extends State<WorkNoteStandaloneView>
    with WindowListener {
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _noteFocusNode = FocusNode();
  final List<String> _attachedImagePaths = [];
  SessionNoteType _noteType = SessionNoteType.report;
  bool _isSaving = false;

  late AppRealm _realm;
  String? _timeRecordId;
  String? _outcomeId;
  String? _projectId;
  late String _taskTitle;
  String? _projectName;
  String? _projectColorHex;
  late DateTime _openedAt;

  bool _isVisible = false;
  bool _allowPermanentClose = false;
  Future<void>? _initFuture;

  @visibleForTesting
  bool get isVisibleForTest => _isVisible;

  @visibleForTesting
  String get currentTaskTitleForTest => _taskTitle;

  @visibleForTesting
  AppRealm get currentRealmForTest => _realm;

  @override
  void initState() {
    super.initState();
    _realm = widget.realm;
    _timeRecordId = widget.timeRecordId;
    _outcomeId = widget.outcomeId;
    _projectId = widget.projectId;
    _taskTitle = widget.taskTitle;
    _projectName = widget.projectName;
    _projectColorHex = widget.projectColorHex;
    _openedAt = DateTime.now();

    if (widget.manageNativeWindow) {
      windowManager.addListener(this);
      _initFuture = _initSubWindow();
    }
  }

  Future<void> _waitForNextFrame(Duration timeout) async {
    try {
      SchedulerBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame.timeout(timeout);
    } catch (_) {}
  }

  Future<void> _initSubWindow() async {
    await widget.windowController.setWindowMethodHandler(_handleHostMethodCall);

    await windowManager.ensureInitialized();
    final windowOptions = WindowOptions(
      size: const Size(450, 560),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: widget.startHidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
      await windowManager.setAsFrameless();
      await windowManager.setResizable(false);
      await windowManager.setHasShadow(false);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(450, 560));
      await windowManager.center();
      await _waitForNextFrame(const Duration(milliseconds: 500));

      if (!widget.startHidden) {
        _isVisible = true;
        await widget.windowController.show();
        await windowManager.focus();
        await windowManager.setAlwaysOnTop(true);
        unawaited(windowManager.setSkipTaskbar(false).catchError((_) {}));
      }
    });

    // پیش‌گرم کردن دیتابیس SQLite در پس‌زمینه برای ثبت بدون تاخیر
    try {
      await DatabaseService.instance.database;
    } catch (_) {}

    try {
      const syncChannel = WindowMethodChannel(
        WorkNoteWindowCoordinator.syncChannelName,
        mode: ChannelMode.unidirectional,
      );
      await syncChannel.invokeMethod(
        WorkNoteWindowCoordinator.methodHostReady,
        {'windowId': widget.windowController.windowId},
      );
    } catch (_) {}
  }

  Future<dynamic> _handleHostMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'ping':
        return 'pong';
      case WorkNoteWindowCoordinator.methodOpenNote:
        final args = call.arguments;
        if (args is Map) {
          await applyOpenPayload(args);
        }
        return true;
      case WorkNoteWindowCoordinator.methodShutdown:
        _allowPermanentClose = true;
        try {
          await windowManager.setPreventClose(false);
        } catch (_) {}
        try {
          await windowManager.close();
        } catch (_) {}
        return true;
      default:
        return null;
    }
  }

  /// اعمال کانتکست فعالیت جاری و نمایش فوری پنجره از حالت مخفی (یا آوردن به جلو)
  Future<void> applyOpenPayload(Map<dynamic, dynamic> args) async {
    await (_initFuture ?? Future<void>.value());
    if (!mounted) return;

    final bool wasVisible = _isVisible;
    setState(() {
      _realm = AppRealmX.fromDb(args['realm'] as String?);
      _timeRecordId = args['timeRecordId'] as String?;
      _outcomeId = args['outcomeId'] as String?;
      _projectId = args['projectId'] as String?;
      final incomingTitle = args['taskTitle'] as String?;
      _taskTitle = (incomingTitle != null && incomingTitle.trim().isNotEmpty)
          ? incomingTitle
          : AppDefaults.untitledTaskTitle;
      _projectName = args['projectName'] as String?;
      _projectColorHex = args['projectColorHex'] as String?;
      _openedAt = DateTime.now();

      if (!wasVisible) {
        _contentController.clear();
        _attachedImagePaths.clear();
        _noteType = SessionNoteType.report;
        _isSaving = false;
      }
      _isVisible = true;
    });

    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();

    if (!widget.manageNativeWindow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _noteFocusNode.requestFocus();
      });
      return;
    }

    // پیش از نمایش پنجره مخفی، یک فریم با ظاهر و کانتکست جدید رندر شود
    await _waitForNextFrame(const Duration(milliseconds: 120));

    if (!wasVisible) {
      await windowManager.center();
      await widget.windowController.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
      unawaited(windowManager.setSkipTaskbar(false).catchError((_) {}));
    } else {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await widget.windowController.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _noteFocusNode.requestFocus();
      }
    });
  }

  Future<void> hideAndReset() async {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();

    if (widget.manageNativeWindow) {
      try {
        await windowManager.hide();
      } catch (_) {
        try {
          await widget.windowController.hide();
        } catch (_) {}
      }
      unawaited(windowManager.setSkipTaskbar(true).catchError((_) {}));
    }

    if (!mounted) return;
    setState(() {
      _isVisible = false;
      _isSaving = false;
      _noteType = SessionNoteType.report;
      _contentController.clear();
      _attachedImagePaths.clear();
    });

    if (widget.manageNativeWindow) {
      await _waitForNextFrame(const Duration(milliseconds: 120));
      try {
        const syncChannel = WindowMethodChannel(
          WorkNoteWindowCoordinator.syncChannelName,
          mode: ChannelMode.unidirectional,
        );
        await syncChannel.invokeMethod(
          WorkNoteWindowCoordinator.methodNoteWindowHidden,
        );
      } catch (_) {}
    }
  }

  @override
  void onWindowClose() {
    if (!_allowPermanentClose) {
      unawaited(hideAndReset());
    }
  }

  @override
  void dispose() {
    if (widget.manageNativeWindow) {
      windowManager.removeListener(this);
    }
    _noteFocusNode.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<String> _getMediaDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final mediaDir =
        Directory(p.join(supportDir.path, 'MabFocus', 'work_notes_media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir.path;
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final mediaDir = await _getMediaDir();
        final filename =
            'note_paste_${DateTime.now().millisecondsSinceEpoch}.png';
        final filePath = p.join(mediaDir, filename);
        await File(filePath).writeAsBytes(imageBytes);

        setState(() {
          _attachedImagePaths.add(filePath);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تصویر از کلیپ‌بورد الصاق شد.'),
              duration: Duration(seconds: 2),
              backgroundColor: AppColors.lifeGreen,
            ),
          );
        }
        return;
      }

      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        final validImageExtensions = [
          '.png',
          '.jpg',
          '.jpeg',
          '.webp',
          '.bmp',
          '.gif'
        ];
        int added = 0;
        for (final path in files) {
          final ext = p.extension(path).toLowerCase();
          if (validImageExtensions.contains(ext)) {
            _attachedImagePaths.add(path);
            added++;
          }
        }
        if (added > 0) {
          setState(() {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$added فایل تصویر از کلیپ‌بورد الصاق شد.'),
                duration: const Duration(seconds: 2),
                backgroundColor: AppColors.lifeGreen,
              ),
            );
          }
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'تصویری در کلیپ‌بورد یافت نشد. می‌توانید از دکمه انتخاب عکس استفاده کنید.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در الصاق از کلیپ‌بورد: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pickImageFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result != null && result.paths.isNotEmpty) {
        setState(() {
          for (final path in result.paths) {
            if (path != null && path.isNotEmpty) {
              _attachedImagePaths.add(path);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در انتخاب فایل: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _saveNote() async {
    final text = _contentController.text.trim();
    if (text.isEmpty && _attachedImagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً متن یادداشت یا حداقل یک تصویر وارد کنید.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final note = SessionNote(
        id: const Uuid().v4(),
        realm: _realm,
        noteType: _noteType,
        timeRecordId: _timeRecordId,
        outcomeId: _outcomeId,
        projectId: _projectId,
        content: text,
        imagePaths: List.from(_attachedImagePaths),
        createdAt: now,
      );

      await DatabaseService.instance.insertSessionNote(note);

      // اطلاع‌رسانی به پنجره اصلی جهت رفرش لیست
      if (widget.manageNativeWindow) {
        try {
          const syncChannel = WindowMethodChannel(
            WorkNoteWindowCoordinator.syncChannelName,
            mode: ChannelMode.unidirectional,
          );
          await syncChannel
              .invokeMethod(WorkNoteWindowCoordinator.methodNoteAdded);
        } catch (_) {}
      }

      await hideAndReset();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ذخیره یادداشت: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Color _parseHexOr(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final realmColor =
        _realm == AppRealm.life ? AppColors.lifeGreen : AppColors.workBlue;
    final timeStr =
        '${_openedAt.hour.toString().padLeft(2, '0')}:${_openedAt.minute.toString().padLeft(2, '0')}';
    final dateStr = JalaliDate.formatWithWeekDay(_openedAt);
    final projectColor = _parseHexOr(_projectColorHex, realmColor);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _pasteFromClipboard,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isSaving) {
            unawaited(hideAndReset());
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: realmColor.withAlpha(110), width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black87,
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (_) {
                        if (widget.manageNativeWindow) {
                          windowManager.startDragging();
                        }
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: realmColor.withAlpha(30),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.edit_note_rounded,
                                color: realmColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'یادداشت حین فعالیت (${_realm.labelFa})',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$dateStr — ساعت $timeStr',
                                    style: widget.useGoogleFonts
                                        ? GoogleFonts.jetBrainsMono(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          )
                                        : const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              tooltip: 'بستن',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed:
                                  _isSaving ? null : () => hideAndReset(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.link_rounded,
                                      size: 14, color: realmColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _taskTitle,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (_projectName != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: projectColor.withAlpha(40),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _projectName!,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: projectColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // نوع یادداشت
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: SessionNoteType.values.map((t) {
                                final isSelected = _noteType == t;
                                return ChoiceChip(
                                  avatar: Icon(t.icon,
                                      size: 13,
                                      color:
                                          isSelected ? Colors.white : t.color),
                                  label: Text(t.labelFa,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.textPrimary)),
                                  selected: isSelected,
                                  selectedColor: t.color,
                                  backgroundColor: AppColors.surfaceElevated,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) =>
                                      setState(() => _noteType = t),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),

                            TextField(
                              controller: _contentController,
                              focusNode: _noteFocusNode,
                              maxLines: 4,
                              minLines: 3,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white),
                              decoration: InputDecoration(
                                hintText:
                                    'برنامه، چالش، گزارش پیشرفت یا ایده لحظه‌ای را بنویسید...',
                                hintStyle: const TextStyle(
                                    fontSize: 12, color: AppColors.textMuted),
                                filled: true,
                                fillColor: AppColors.surfaceElevated,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: realmColor),
                                ),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                            ),
                            const SizedBox(height: 10),

                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    side: const BorderSide(
                                        color: AppColors.border),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                  ),
                                  icon: Icon(Icons.paste_rounded,
                                      size: 15, color: realmColor),
                                  label: const Text('الصاق تصویر (Ctrl+V)',
                                      style: TextStyle(fontSize: 11)),
                                  onPressed: _pasteFromClipboard,
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    side: const BorderSide(
                                        color: AppColors.border),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                  ),
                                  icon: const Icon(Icons.photo_library_outlined,
                                      size: 15, color: AppColors.textSecondary),
                                  label: const Text('انتخاب عکس',
                                      style: TextStyle(fontSize: 11)),
                                  onPressed: _pickImageFile,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (_attachedImagePaths.isNotEmpty)
                              SizedBox(
                                height: 72,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _attachedImagePaths.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (ctx, idx) {
                                    final path = _attachedImagePaths[idx];
                                    final file = File(path);
                                    return Stack(
                                      children: [
                                        Container(
                                          width: 72,
                                          height: 72,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: AppColors.border),
                                            color: Colors.black26,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: file.existsSync()
                                              ? Image.file(file,
                                                  fit: BoxFit.cover)
                                              : const Icon(
                                                  Icons.broken_image_rounded,
                                                  size: 24,
                                                  color: AppColors.textMuted),
                                        ),
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: InkWell(
                                            onTap: () {
                                              setState(() {
                                                _attachedImagePaths
                                                    .removeAt(idx);
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                color: Colors.black87,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                  Icons.close_rounded,
                                                  size: 12,
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isSaving ? null : () => hideAndReset(),
                          child: const Text('انصراف',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: realmColor,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check_rounded, size: 16),
                          label: const Text('ثبت یادداشت',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: _isSaving ? null : _saveNote,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
