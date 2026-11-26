@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mab_focus/core/constants.dart';
import 'package:mab_focus/main.dart';
import 'package:mab_focus/models/outcome_item.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/models/project_node.dart';
import 'package:mab_focus/models/scheduled_block.dart';
import 'package:mab_focus/models/session_note.dart';
import 'package:mab_focus/models/time_record.dart';
import 'package:mab_focus/providers/app_state_provider.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:mab_focus/services/music_player_service.dart';
import 'package:mab_focus/ui/app_shell.dart';
import 'package:mab_focus/ui/shared/work_note_window_coordinator.dart';
import 'package:mab_focus/ui/widget_mode/floating_widget_view.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeFilePicker extends FilePicker {
  final String outputDir;
  final void Function(String path) onSaved;

  _FakeFilePicker({required this.outputDir, required this.onSaved});

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    final safeName =
        (fileName != null && fileName.trim().isNotEmpty) ? fileName.trim() : 'export.xlsx';
    final path = p.join(outputDir, safeName);
    if (bytes != null) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    onSaved(path);
    return path;
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    return outputDir;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return null;
  }
}

class E2eTestHarness {
  final Directory tempDir;
  final String dbPath;
  Database db;
  AppStateProvider provider;

  final List<MethodCall> windowManagerCalls = <MethodCall>[];
  final List<String> missingPluginWarnings = <String>[];

  Rect mockWindowBounds;
  Size mockMinimumSize;
  bool mockResizable;
  bool mockMovable;
  bool mockFullScreen;
  bool mockAlwaysOnTop;
  bool mockPreventClose;
  bool mockVisible;
  Size primaryDisplaySize;
  Size primaryVisibleSize;
  String? lastSavedFilePath;

  final FilePicker? _previousFilePicker;
  bool _disposed = false;
  int _seedCounter = 0;

  static final Set<String> _knownAudioEventChannels = <String>{};

  static const List<String> _mockedChannels = <String>[
    'window_manager',
    'dev.leanflutter.plugins/screen_retriever',
    'dev.leanflutter.plugins/screen_retriever_event',
    'com.mabfocus.app/virtual_desktop',
    'mixin.one/desktop_multi_window',
    'mixin.one/desktop_multi_window/channels',
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers.global/events',
    'xyz.luan/audioplayers',
    'pasteboard',
    'dev.fluttercommunity.plus/share',
    'plugins.flutter.io/url_launcher',
    'plugins.flutter.io/shared_preferences',
    'plugins.flutter.io/path_provider',
  ];

  E2eTestHarness._({
    required this.tempDir,
    required this.dbPath,
    required this.db,
    required this.provider,
    required this.mockWindowBounds,
    required this.mockMinimumSize,
    required this.mockResizable,
    required this.mockMovable,
    required this.mockFullScreen,
    required this.mockAlwaysOnTop,
    required this.mockPreventClose,
    required this.mockVisible,
    required this.primaryDisplaySize,
    required this.primaryVisibleSize,
    required FilePicker? previousFilePicker,
  }) : _previousFilePicker = previousFilePicker;

  static Future<E2eTestHarness> create({
    Future<void> Function(Database db)? seedDb,
    Size primaryDisplaySize = const Size(1920, 1080),
    Size? primaryVisibleSize,
    Rect initialWindowBounds = const Rect.fromLTWH(100, 100, 1220, 800),
    bool initializeProvider = true,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    GoogleFonts.config.allowRuntimeFetching = false;

    final tempDir = await Directory.systemTemp.createTemp('mab_e2e_');
    final dbPath = p.join(tempDir.path, 'mab_focus_e2e.db');

    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        singleInstance: false,
        onCreate: (db, v) => DatabaseService.instance.createSchemaV5(db, v),
      ),
    );
    DatabaseService.instance.setTestDatabase(db);

    await DatabaseService.instance.setSetting(
      AppDefaults.settingKeyTxtPath,
      p.join(tempDir.path, 'e2e_worklog.txt'),
    );

    if (seedDb != null) {
      await seedDb(db);
    }

    FilePicker? previousPicker;
    try {
      previousPicker = FilePicker.platform;
    } catch (_) {
      previousPicker = null;
    }

    final provider = AppStateProvider(isTestMode: true);
    final harness = E2eTestHarness._(
      tempDir: tempDir,
      dbPath: dbPath,
      db: db,
      provider: provider,
      mockWindowBounds: initialWindowBounds,
      mockMinimumSize: const Size(360, 480),
      mockResizable: true,
      mockMovable: true,
      mockFullScreen: false,
      mockAlwaysOnTop: false,
      mockPreventClose: false,
      mockVisible: true,
      primaryDisplaySize: primaryDisplaySize,
      primaryVisibleSize: primaryVisibleSize ??
          Size(primaryDisplaySize.width, primaryDisplaySize.height - 40),
      previousFilePicker: previousPicker,
    );

    FilePicker.platform = _FakeFilePicker(
      outputDir: tempDir.path,
      onSaved: (path) => harness.lastSavedFilePath = path,
    );

    WorkNoteWindowCoordinator.instance.resetForTest();
    WorkNoteWindowCoordinator.instance.isDesktopOverride = false;

    harness._installChannelMocks();

    if (initializeProvider) {
      await provider.initialize();
    }

    return harness;
  }

  static Future<E2eTestHarness> createForTest(
    WidgetTester tester, {
    Future<void> Function(Database db)? seedDb,
    Size primaryDisplaySize = const Size(1920, 1080),
    Size? primaryVisibleSize,
    Rect initialWindowBounds = const Rect.fromLTWH(100, 100, 1220, 800),
    bool initializeProvider = true,
  }) async {
    final harness = await tester.runAsync(
      () => create(
        seedDb: seedDb,
        primaryDisplaySize: primaryDisplaySize,
        primaryVisibleSize: primaryVisibleSize,
        initialWindowBounds: initialWindowBounds,
        initializeProvider: initializeProvider,
      ),
    );
    return harness!;
  }

  void _installChannelMocks() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (MethodCall call) async {
        windowManagerCalls.add(call);
        final Map<Object?, Object?> args = call.arguments is Map
            ? call.arguments as Map<Object?, Object?>
            : const {};

        switch (call.method) {
          case 'ensureInitialized':
          case 'waitUntilReadyToShow':
          case 'setAsFrameless':
          case 'setTitleBarStyle':
          case 'setBackgroundColor':
          case 'setHasShadow':
          case 'focus':
          case 'blur':
          case 'close':
          case 'destroy':
          case 'startDragging':
          case 'setSkipTaskbar':
          case 'setTitle':
          case 'minimize':
          case 'restore':
          case 'maximize':
          case 'unmaximize':
          case 'setMaximumSize':
            return null;
          case 'show':
            mockVisible = true;
            return null;
          case 'hide':
            mockVisible = false;
            return null;
          case 'setBounds':
            final x = (args['x'] as num?)?.toDouble() ?? mockWindowBounds.left;
            final y = (args['y'] as num?)?.toDouble() ?? mockWindowBounds.top;
            final w =
                (args['width'] as num?)?.toDouble() ?? mockWindowBounds.width;
            final h =
                (args['height'] as num?)?.toDouble() ?? mockWindowBounds.height;
            mockWindowBounds = Rect.fromLTWH(x, y, w, h);
            return null;
          case 'getBounds':
            return <String, double>{
              'x': mockWindowBounds.left,
              'y': mockWindowBounds.top,
              'width': mockWindowBounds.width,
              'height': mockWindowBounds.height,
            };
          case 'setMinimumSize':
            final w = (args['width'] as num?)?.toDouble();
            final h = (args['height'] as num?)?.toDouble();
            if (w != null && h != null) {
              mockMinimumSize = Size(w, h);
            }
            return null;
          case 'setResizable':
            mockResizable = args['isResizable'] as bool? ?? mockResizable;
            return null;
          case 'setMovable':
            mockMovable = args['isMovable'] as bool? ?? mockMovable;
            return null;
          case 'setFullScreen':
            mockFullScreen = args['isFullScreen'] as bool? ?? mockFullScreen;
            return null;
          case 'setAlwaysOnTop':
            mockAlwaysOnTop =
                args['isAlwaysOnTop'] as bool? ?? mockAlwaysOnTop;
            return null;
          case 'setPreventClose':
            mockPreventClose =
                args['isPreventClose'] as bool? ?? mockPreventClose;
            return null;
          case 'isPreventClose':
            return mockPreventClose;
          case 'isFullScreen':
            return mockFullScreen;
          case 'isResizable':
            return mockResizable;
          case 'isMovable':
            return mockMovable;
          case 'isAlwaysOnTop':
            return mockAlwaysOnTop;
          case 'isVisible':
            return mockVisible;
          case 'isFocused':
          case 'isMinimizable':
          case 'isClosable':
          case 'isMaximizable':
          case 'isVisibleOnAllWorkspaces':
          case 'hasShadow':
          case 'grabKeyboard':
          case 'ungrabKeyboard':
          case 'startResizing':
            return true;
          case 'isMaximized':
          case 'isMinimized':
          case 'isDockable':
          case 'isAlwaysOnBottom':
          case 'isSkipTaskbar':
            return false;
          case 'isDocked':
            return null;
          case 'getId':
            return 1;
          case 'getTitleBarHeight':
            return 32;
          case 'getOpacity':
            return 1.0;
          case 'getTitle':
            return 'Mab-Focus';
          default:
            return null;
        }
      },
    );

    Map<String, dynamic> displayPayload() => <String, dynamic>{
          'id': 'display-1',
          'name': 'Primary',
          'size': <String, double>{
            'width': primaryDisplaySize.width,
            'height': primaryDisplaySize.height,
          },
          'visiblePosition': <String, double>{'dx': 0.0, 'dy': 0.0},
          'visibleSize': <String, double>{
            'width': primaryVisibleSize.width,
            'height': primaryVisibleSize.height,
          },
          'scaleFactor': 1.0,
        };

    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
      (MethodCall call) async {
        switch (call.method) {
          case 'getPrimaryDisplay':
            return displayPayload();
          case 'getAllDisplays':
            return <String, dynamic>{
              'displays': <Map<String, dynamic>>[displayPayload()],
            };
          case 'getCursorScreenPoint':
            return <String, double>{'dx': 500.0, 'dy': 500.0};
          default:
            return null;
        }
      },
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.leanflutter.plugins/screen_retriever_event'),
      (MethodCall call) async => null,
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('com.mabfocus.app/virtual_desktop'),
      (MethodCall call) async => null,
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('mixin.one/desktop_multi_window'),
      (MethodCall call) async {
        switch (call.method) {
          case 'createWindow':
            return 'test-subwindow-1';
          case 'getWindowDefinition':
            return <String, dynamic>{'windowId': '0', 'arguments': ''};
          case 'getAllWindows':
            return <dynamic>[];
          default:
            return null;
        }
      },
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('mixin.one/desktop_multi_window/channels'),
      (MethodCall call) async => null,
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall call) async => null,
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global/events'),
      (MethodCall call) async => null,
    );

    for (final eventChannelName in _knownAudioEventChannels) {
      messenger.setMockMethodCallHandler(
        MethodChannel(eventChannelName),
        (MethodCall call) async => null,
      );
    }

    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall call) async {
        if (call.method == 'create' && call.arguments is Map) {
          final args = call.arguments as Map<Object?, Object?>;
          final playerId = args['playerId'] as String?;
          if (playerId != null && playerId.isNotEmpty) {
            final eventChannelName = 'xyz.luan/audioplayers/events/$playerId';
            _knownAudioEventChannels.add(eventChannelName);
            messenger.setMockMethodCallHandler(
              MethodChannel(eventChannelName),
              (MethodCall eventCall) async => null,
            );
          }
        }
        return null;
      },
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('pasteboard'),
      (MethodCall call) async {
        switch (call.method) {
          case 'files':
            return <String>[];
          default:
            return null;
        }
      },
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (MethodCall call) async => '',
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (MethodCall call) async {
        switch (call.method) {
          case 'canLaunch':
          case 'launch':
            return true;
          default:
            return null;
        }
      },
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall call) async {
        switch (call.method) {
          case 'getAll':
            return <String, Object>{};
          case 'clear':
          case 'remove':
            return true;
          default:
            return true;
        }
      },
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tempDir.path,
    );

    _installOfflineFontAssetsMock(messenger);
  }

  static ByteData? _cachedFallbackTtfBytes;
  static ByteData? _cachedAssetManifestBin;

  static ByteData _getFallbackTtfBytes() {
    if (_cachedFallbackTtfBytes != null) return _cachedFallbackTtfBytes!;
    for (final candidate in <String>[
      r'C:\Windows\Fonts\arial.ttf',
      r'C:\Windows\Fonts\tahoma.ttf',
      r'C:\Dev\flutter\bin\cache\artifacts\material_fonts\Roboto-Regular.ttf',
    ]) {
      final f = File(candidate);
      if (f.existsSync()) {
        final bytes = f.readAsBytesSync();
        _cachedFallbackTtfBytes = ByteData.sublistView(bytes);
        return _cachedFallbackTtfBytes!;
      }
    }
    _cachedFallbackTtfBytes = ByteData(0);
    return _cachedFallbackTtfBytes!;
  }

  static ByteData _getAssetManifestBin() {
    if (_cachedAssetManifestBin != null) return _cachedAssetManifestBin!;
    const families = <String>['Vazirmatn', 'JetBrainsMono'];
    const parts = <String>[
      'Thin',
      'ThinItalic',
      'ExtraLight',
      'ExtraLightItalic',
      'Light',
      'LightItalic',
      'Regular',
      'Italic',
      'Medium',
      'MediumItalic',
      'SemiBold',
      'SemiBoldItalic',
      'Bold',
      'BoldItalic',
      'ExtraBold',
      'ExtraBoldItalic',
      'Black',
      'BlackItalic',
    ];
    final manifest = <String, List<Map<String, Object>>>{};
    for (final family in families) {
      for (final part in parts) {
        final key = 'assets/e2e_fonts/$family-$part.ttf';
        manifest[key] = <Map<String, Object>>[
          <String, Object>{'asset': key},
        ];
      }
    }
    manifest['assets/audio/nature_waterfall.wav'] = <Map<String, Object>>[
      <String, Object>{'asset': 'assets/audio/nature_waterfall.wav'},
    ];
    _cachedAssetManifestBin = const StandardMessageCodec().encodeMessage(manifest)!;
    return _cachedAssetManifestBin!;
  }

  void _installOfflineFontAssetsMock(TestDefaultBinaryMessenger messenger) {
    rootBundle.evict('AssetManifest.bin');
    messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
      if (message == null) return null;
      final key = utf8.decode(message.buffer.asUint8List(
        message.offsetInBytes,
        message.lengthInBytes,
      ));
      if (key == 'AssetManifest.bin') {
        return _getAssetManifestBin();
      }
      if (key.startsWith('assets/e2e_fonts/') && key.endsWith('.ttf')) {
        return _getFallbackTtfBytes();
      }
      final localFile = File(key);
      if (localFile.existsSync()) {
        return ByteData.sublistView(localFile.readAsBytesSync());
      }
      return null;
    });
  }

  /// Simulates closing the application and reopening it on the exact same
  /// persisted SQLite file. Must be called inside `tester.runAsync(...)` when
  /// executing inside a `testWidgets` test.
  Future<void> simulateRestart({
    Future<void> Function(Database db)? beforeReopen,
  }) async {
    provider.dispose();
    DatabaseService.instance.resetForTest();
    await db.close();

    db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        singleInstance: false,
        onCreate: (db, v) => DatabaseService.instance.createSchemaV5(db, v),
      ),
    );
    DatabaseService.instance.setTestDatabase(db);

    if (beforeReopen != null) {
      await beforeReopen(db);
    }

    provider = AppStateProvider(isTestMode: true);
    await provider.initialize();
  }

  Widget buildApp({
    bool useMabFocusApp = true,
    Size surfaceSize = const Size(1280, 800),
  }) {
    if (useMabFocusApp) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: provider),
          ChangeNotifierProvider<MusicPlayerService>.value(
            value: MusicPlayerService.instance,
          ),
        ],
        child: const MabFocusApp(),
      );
    }

    return MediaQuery(
      data: MediaQueryData(size: surfaceSize),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: provider),
          ChangeNotifierProvider<MusicPlayerService>.value(
            value: MusicPlayerService.instance,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('fa', 'IR'),
          supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData.dark(useMaterial3: true),
          home: const AppShell(),
        ),
      ),
    );
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    Size surfaceSize = const Size(1280, 800),
    bool useMabFocusApp = true,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surfaceSize;
    await tester.binding.setSurfaceSize(surfaceSize);
    await tester.pumpWidget(
      buildApp(useMabFocusApp: useMabFocusApp, surfaceSize: surfaceSize),
    );
    await pumpBounded(tester, const Duration(milliseconds: 120));
  }

  Future<void> pumpBounded(
    WidgetTester tester, [
    Duration step = const Duration(milliseconds: 250),
  ]) async {
    await tester.pump();
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(step);
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() predicate, {
    int maxSteps = 60,
  }) async {
    for (int i = 0; i < maxSteps; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (predicate()) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> navigateToTab(WidgetTester tester, int tabIndex) async {
    final hasRail = find.byType(NavigationRail).evaluate().isNotEmpty;
    if (hasRail) {
      final railIcons = <List<IconData>>[
        <IconData>[Icons.calendar_month_outlined, Icons.calendar_month_rounded],
        <IconData>[Icons.checklist_rounded, Icons.fact_check_rounded],
        <IconData>[Icons.assignment_outlined, Icons.assignment_rounded],
        <IconData>[Icons.account_tree_outlined, Icons.account_tree_rounded],
        <IconData>[Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded],
        <IconData>[Icons.inbox_outlined, Icons.inbox_rounded],
        <IconData>[Icons.settings_outlined, Icons.settings_rounded],
      ];
      final icons = railIcons[tabIndex];
      final candidates = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byWidgetPredicate(
          (w) => w is Icon && (w.icon == icons[0] || w.icon == icons[1]),
        ),
      );
      await tester.tap(candidates.first);
      await pumpBounded(tester, const Duration(milliseconds: 200));
      return;
    }

    if (tabIndex <= 2) {
      const mobileLabels = <String>['تقویم', 'کارها', 'یادداشت'];
      await tester.tap(find.text(mobileLabels[tabIndex]).first);
      await pumpBounded(tester, const Duration(milliseconds: 200));
      return;
    }

    await tester.tap(find.text('بیشتر').first);
    await pumpBounded(tester, const Duration(milliseconds: 250));
    final moreLabels = <int, String>{
      3: provider.dashboardRealm == AppRealm.life
          ? 'استودیوی پروژه‌های زندگی'
          : 'استودیوی پروژه‌های کار',
      4: 'سند ظرفیت و سارقان زمان',
      5: 'کارتابل نواقص (بدون عنوان)',
      6: 'تنظیمات Flowmodoro و تقویم گوگل',
    };
    await tester.tap(find.text(moreLabels[tabIndex]!).last);
    await pumpBounded(tester, const Duration(milliseconds: 250));
  }

  Future<void> hoverFloatingWidget(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    final circleFinder = find.descendant(
      of: find.byType(FloatingWidgetView),
      matching: find.byType(CustomPaint),
    );
    await gesture.moveTo(tester.getCenter(circleFinder.first));
    await pumpBounded(tester, const Duration(milliseconds: 300));
  }

  String _nextId(String prefix) {
    _seedCounter++;
    return '${prefix}_$_seedCounter';
  }

  Future<ProjectNode> seedProject({
    String? id,
    AppRealm realm = AppRealm.work,
    required String name,
    String? parentId,
    String status = 'active',
    String colorHex = '#3B82F6',
    int dailyQuotaMinutes = 0,
    int weeklyQuotaMinutes = 0,
    int monthlyQuotaMinutes = 0,
    double hourlyRate = 0.0,
    bool refresh = true,
  }) async {
    final project = ProjectNode(
      id: id ?? _nextId('proj'),
      realm: realm,
      name: name,
      parentId: parentId,
      status: status,
      colorHex: colorHex,
      dailyQuotaMinutes: dailyQuotaMinutes,
      weeklyQuotaMinutes: weeklyQuotaMinutes,
      monthlyQuotaMinutes: monthlyQuotaMinutes,
      hourlyRate: hourlyRate,
      createdAt: DateTime.now(),
    );
    await DatabaseService.instance.insertProject(project);
    if (refresh) {
      await provider.refreshAllData();
    }
    return project;
  }

  Future<OutcomeItem> seedOutcome({
    String? id,
    AppRealm realm = AppRealm.work,
    String? projectId,
    required String title,
    String description = '',
    bool isCompleted = false,
    DateTime? createdAt,
    DateTime? completedAt,
    bool refresh = true,
  }) async {
    final outcome = OutcomeItem(
      id: id ?? _nextId('out'),
      realm: realm,
      projectId: projectId,
      title: title,
      description: description,
      isCompleted: isCompleted,
      createdAt: createdAt ?? DateTime.now(),
      completedAt:
          completedAt ?? (isCompleted ? DateTime.now() : null),
    );
    await DatabaseService.instance.insertOutcome(outcome);
    if (refresh) {
      await provider.refreshAllData();
    }
    return outcome;
  }

  Future<TimeRecord> seedTimeRecord({
    String? id,
    AppRealm realm = AppRealm.work,
    ClockType clockMode = ClockType.pomodoro,
    String? outcomeId,
    String? projectId,
    required String titleSnapshot,
    bool isUntitledDraft = false,
    List<String> tagIds = const [],
    required DateTime startTime,
    DateTime? endTime,
    int? durationSeconds,
    int overtimeSeconds = 0,
    int earnedBreakSeconds = 0,
    bool isEdited = false,
    bool refresh = true,
  }) async {
    final computedDuration = durationSeconds ??
        (endTime != null ? endTime.difference(startTime).inSeconds : 0);
    final record = TimeRecord(
      id: id ?? _nextId('rec'),
      realm: realm,
      clockMode: clockMode,
      outcomeId: outcomeId,
      projectId: projectId,
      titleSnapshot: titleSnapshot,
      isUntitledDraft: isUntitledDraft,
      tagIds: tagIds,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: computedDuration,
      overtimeSeconds: overtimeSeconds,
      earnedBreakSeconds: earnedBreakSeconds,
      isEdited: isEdited,
    );
    await DatabaseService.instance.insertTimeRecord(record);
    if (refresh) {
      await provider.refreshAllData();
    }
    return record;
  }

  Future<SessionNote> seedSessionNote({
    String? id,
    AppRealm realm = AppRealm.work,
    SessionNoteType noteType = SessionNoteType.report,
    String? timeRecordId,
    String? outcomeId,
    String? projectId,
    required String content,
    DateTime? createdAt,
    bool refresh = true,
  }) async {
    final note = SessionNote(
      id: id ?? _nextId('note'),
      realm: realm,
      noteType: noteType,
      timeRecordId: timeRecordId,
      outcomeId: outcomeId,
      projectId: projectId,
      content: content,
      createdAt: createdAt ?? DateTime.now(),
    );
    await DatabaseService.instance.insertSessionNote(note);
    if (refresh) {
      await provider.refreshAllData();
    }
    return note;
  }

  Future<ScheduledBlock> seedScheduledBlock({
    String? id,
    AppRealm realm = AppRealm.work,
    String? projectId,
    String? outcomeId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    bool refresh = true,
  }) async {
    final block = ScheduledBlock(
      id: id ?? _nextId('blk'),
      realm: realm,
      projectId: projectId,
      outcomeId: outcomeId,
      title: title,
      startTime: startTime,
      endTime: endTime,
    );
    await DatabaseService.instance.insertScheduledBlock(block);
    if (refresh) {
      await provider.refreshAllData();
    }
    return block;
  }

  Future<void> dispose([WidgetTester? tester]) async {
    if (_disposed) return;
    _disposed = true;

    if (tester != null) {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.binding.setSurfaceSize(null);
        await tester.runAsync(_disposeAsync);
      }
      return;
    }

    await _disposeAsync();
  }

  Future<void> _disposeAsync() async {
    provider.dispose();
    WorkNoteWindowCoordinator.instance.resetForTest();
    DatabaseService.instance.resetForTest();
    await db.close();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in _mockedChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
    messenger.setMockMessageHandler('flutter/assets', null);
    rootBundle.evict('AssetManifest.bin');

    if (_previousFilePicker != null) {
      FilePicker.platform = _previousFilePicker;
    }

    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
