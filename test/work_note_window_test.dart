import 'dart:async';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mab_focus/core/constants.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:mab_focus/ui/shared/work_note_standalone_window.dart';
import 'package:mab_focus/ui/shared/work_note_window_coordinator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('WorkNoteWindowCoordinator', () {
    late WorkNoteWindowCoordinator coordinator;

    setUp(() {
      coordinator = WorkNoteWindowCoordinator.instance;
      coordinator.resetForTest();
      coordinator.isDesktopOverride = true;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('mixin.one/desktop_multi_window/channels'),
        null,
      );
      coordinator.resetForTest();
    });

    void mockDesktopMultiWindowChannel() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('mixin.one/desktop_multi_window/channels'),
        (MethodCall call) async => null,
      );
    }

    Future<void> emitSyncEvent(String method, [dynamic arguments]) async {
      final bytes = const StandardMethodCodec().encodeMethodCall(
        MethodCall('methodCall', {
          'channel': WorkNoteWindowCoordinator.syncChannelName,
          'method': method,
          'arguments': arguments,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'mixin.one/desktop_multi_window/channels',
        bytes,
        (_) {},
      );
    }

    test('prewarms a single hidden host and waits for host_ready before open_note',
        () async {
      mockDesktopMultiWindowChannel();

      int createCount = 0;
      final List<WindowConfiguration> createdConfigs = [];
      final List<(String, String, dynamic)> invocations = [];

      coordinator.windowCreatorOverride = (config) async {
        createCount++;
        createdConfigs.add(config);
        return WindowController.fromWindowId('host-$createCount');
      };
      coordinator.invokeHostOverride = (controller, method, args) async {
        invocations.add((controller.windowId, method, args));
        return true;
      };

      // Concurrent prewarm + openWorkNote must only create ONE hidden window
      final prewarmFuture1 = coordinator.prewarm();
      final prewarmFuture2 = coordinator.prewarm();
      final openFuture = coordinator.openWorkNote({
        'type': 'work_note',
        'realm': 'work',
        'taskTitle': 'طراحی ماژول تست',
      });

      await prewarmFuture1;
      await prewarmFuture2;
      expect(createCount, 1);
      expect(createdConfigs.single.hiddenAtLaunch, isTrue);
      final launchArgs =
          jsonDecode(createdConfigs.single.arguments) as Map<String, dynamic>;
      expect(launchArgs['prewarm'], isTrue);

      // Should NOT invoke open_note before host_ready signal arrives
      expect(invocations, isEmpty);
      expect(coordinator.isHostReady, isFalse);

      // Simulate sub-window finishing setup & first frame -> emits host_ready
      await emitSyncEvent(
        WorkNoteWindowCoordinator.methodHostReady,
        {'windowId': 'host-1'},
      );

      final opened = await openFuture;
      expect(opened, isTrue);
      expect(coordinator.isHostReady, isTrue);
      expect(invocations.length, 1);
      expect(invocations.single.$1, 'host-1');
      expect(invocations.single.$2, WorkNoteWindowCoordinator.methodOpenNote);

      // Opening a second time reuses the exact same prewarmed host immediately
      final openedAgain = await coordinator.openWorkNote({
        'type': 'work_note',
        'realm': 'life',
        'taskTitle': 'استراحت کوتاه',
      });
      expect(openedAgain, isTrue);
      expect(createCount, 1);
      expect(invocations.length, 2);
      expect((invocations[1].$3 as Map)['realm'], 'life');
    });

    test('note_added event notifies registered listeners & shutdown disposes host',
        () async {
      mockDesktopMultiWindowChannel();

      int createCount = 0;
      final List<String> methods = [];

      coordinator.windowCreatorOverride = (config) async {
        createCount++;
        return WindowController.fromWindowId('host-$createCount');
      };
      coordinator.invokeHostOverride = (controller, method, args) async {
        methods.add(method);
        return true;
      };

      int noteAddedCalls = 0;
      coordinator.addOnNoteAddedListener(() => noteAddedCalls++);
      coordinator.ensureChannelRegistered();

      await emitSyncEvent(WorkNoteWindowCoordinator.methodNoteAdded);
      expect(noteAddedCalls, 1);

      await coordinator.prewarm();
      await emitSyncEvent(
        WorkNoteWindowCoordinator.methodHostReady,
        {'windowId': 'host-1'},
      );
      await coordinator.disposeHostWindow();

      expect(methods, contains(WorkNoteWindowCoordinator.methodShutdown));
      expect(coordinator.hasLiveHostWindow, isFalse);
    });

    test('recovers cleanly if existing host fails during invoke', () async {
      mockDesktopMultiWindowChannel();

      int createCount = 0;
      final List<(String, String)> invocations = [];

      coordinator.windowCreatorOverride = (config) async {
        createCount++;
        final id = 'host-$createCount';
        // Schedule host_ready right after creation completes
        scheduleMicrotask(() {
          emitSyncEvent(
            WorkNoteWindowCoordinator.methodHostReady,
            {'windowId': id},
          );
        });
        return WindowController.fromWindowId(id);
      };
      coordinator.invokeHostOverride = (controller, method, args) async {
        invocations.add((controller.windowId, method));
        if (controller.windowId == 'host-1' &&
            method == WorkNoteWindowCoordinator.methodOpenNote) {
          throw StateError('Stale sub-window');
        }
        return true;
      };

      final opened = await coordinator.openWorkNote({
        'type': 'work_note',
        'realm': 'work',
        'taskTitle': 'بازیابی پنجره',
      });

      expect(opened, isTrue);
      expect(createCount, 2);
      expect(invocations, [
        ('host-1', WorkNoteWindowCoordinator.methodOpenNote),
        ('host-2', WorkNoteWindowCoordinator.methodOpenNote),
      ]);
    });
  });

  group('WorkNoteStandaloneView prewarm & reuse lifecycle', () {
    Widget buildStandaloneHarness(GlobalKey<WorkNoteStandaloneViewState> key) {
      return MediaQuery(
        data: const MediaQueryData(size: Size(450, 560)),
        child: MaterialApp(
          locale: const Locale('fa', 'IR'),
          supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData.dark(useMaterial3: true).copyWith(
            scaffoldBackgroundColor: Colors.transparent,
          ),
          home: WorkNoteStandaloneView(
            key: key,
            windowController: WindowController.fromWindowId('test-host'),
            taskTitle: AppDefaults.untitledTaskTitle,
            startHidden: true,
            manageNativeWindow: false,
            useGoogleFonts: false,
          ),
        ),
      );
    }

    testWidgets(
        'updates task context on open, persists note to DB, clears draft & resets on reopen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(450, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = await tester.runAsync(() async {
        final database = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 5,
            singleInstance: false,
            onCreate: (db, v) => DatabaseService.instance.createSchemaV5(db, v),
          ),
        );
        DatabaseService.instance.setTestDatabase(database);
        return database;
      });
      addTearDown(() async {
        DatabaseService.instance.resetForTest();
        await tester.runAsync(() => db!.close());
      });

      final viewKey = GlobalKey<WorkNoteStandaloneViewState>();
      await tester.pumpWidget(buildStandaloneHarness(viewKey));
      await tester.pump();

      expect(viewKey.currentState!.isVisibleForTest, isFalse);

      // 1) Open for a Work task
      await tester.runAsync(() async {
        await viewKey.currentState!.applyOpenPayload({
          'realm': 'work',
          'timeRecordId': 'rec-work-1',
          'outcomeId': 'out-work-1',
          'projectId': 'proj-work-1',
          'taskTitle': 'بهینه‌سازی پنجره یادداشت',
          'projectName': 'Mab-Focus',
          'projectColorHex': '#3B82F6',
        });
      });
      await tester.pump();

      expect(viewKey.currentState!.isVisibleForTest, isTrue);
      expect(find.text('یادداشت حین فعالیت (کار)'), findsOneWidget);
      expect(find.text('بهینه‌سازی پنجره یادداشت'), findsOneWidget);
      expect(find.text('Mab-Focus'), findsOneWidget);

      // Enter note text and save
      await tester.enterText(
        find.byType(TextField),
        'تست ذخیره و پاکسازی خودکار بعد از ثبت',
      );
      await tester.pump();

      await tester.tap(find.text('ثبت یادداشت'));
      await tester.pump();
      await tester.runAsync(() async {
        for (int i = 0; i < 40; i++) {
          if (!viewKey.currentState!.isVisibleForTest) break;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pump();

      // Saved to DB with triple-linking & window hidden + draft cleared
      final notes = await tester.runAsync(
        () => DatabaseService.instance.getAllSessionNotes(),
      );
      expect(notes, hasLength(1));
      expect(notes!.single.realm, AppRealm.work);
      expect(notes.single.timeRecordId, 'rec-work-1');
      expect(notes.single.outcomeId, 'out-work-1');
      expect(notes.single.projectId, 'proj-work-1');
      expect(notes.single.content, 'تست ذخیره و پاکسازی خودکار بعد از ثبت');
      expect(viewKey.currentState!.isVisibleForTest, isFalse);

      // 2) Reopen for a Life task -> stale text must be completely cleared
      await tester.runAsync(() async {
        await viewKey.currentState!.applyOpenPayload({
          'realm': 'life',
          'timeRecordId': 'rec-life-2',
          'outcomeId': null,
          'projectId': null,
          'taskTitle': 'استراحت میان‌روز',
          'projectName': null,
          'projectColorHex': null,
        });
      });
      await tester.pump();

      expect(viewKey.currentState!.isVisibleForTest, isTrue);
      expect(viewKey.currentState!.currentRealmForTest, AppRealm.life);
      expect(find.text('یادداشت حین فعالیت (زندگی)'), findsOneWidget);
      expect(find.text('استراحت میان‌روز'), findsOneWidget);
      expect(
        find.text('تست ذخیره و پاکسازی خودکار بعد از ثبت'),
        findsNothing,
      );

      // Clicking Cancel hides and resets dirty text as well
      await tester.enterText(find.byType(TextField), 'متن ناتمام انصرافی');
      await tester.pump();
      await tester.tap(find.text('انصراف'));
      await tester.pump();
      expect(viewKey.currentState!.isVisibleForTest, isFalse);

      await tester.runAsync(() async {
        await viewKey.currentState!.applyOpenPayload({
          'realm': 'work',
          'taskTitle': 'کار بعدی',
        });
      });
      await tester.pump();
      expect(find.text('متن ناتمام انصرافی'), findsNothing);
    });
  });
}
