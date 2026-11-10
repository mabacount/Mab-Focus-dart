import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mab_focus/core/constants.dart';
import 'package:mab_focus/models/outcome_item.dart';
import 'package:mab_focus/models/pomodoro_state.dart';
import 'package:mab_focus/models/project_node.dart';
import 'package:mab_focus/models/time_record.dart';
import 'package:mab_focus/providers/app_state_provider.dart';
import 'package:mab_focus/services/database_service.dart';
import 'package:mab_focus/services/music_player_service.dart';
import 'package:mab_focus/ui/app_shell.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<(Database, AppStateProvider)> createSeededProvider() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 5,
        singleInstance: false,
        onCreate: (db, v) => DatabaseService.instance.createSchemaV5(db, v),
      ),
    );
    DatabaseService.instance.setTestDatabase(db);

    await DatabaseService.instance.insertProject(
      ProjectNode(
        id: 'p_work',
        realm: AppRealm.work,
        name: 'مهندسی نرم‌افزار',
        weeklyQuotaMinutes: 600,
      ),
    );
    await DatabaseService.instance.insertOutcome(
      OutcomeItem(
        id: 'o_work',
        realm: AppRealm.work,
        projectId: 'p_work',
        title: 'پیاده‌سازی موتور Flowmodoro',
      ),
    );
    await DatabaseService.instance.insertOutcome(
      OutcomeItem(
        id: 'o_life',
        realm: AppRealm.life,
        title: 'پیاده‌روی عصرگاهی',
      ),
    );
    await DatabaseService.instance.insertTimeRecord(
      TimeRecord(
        id: 'rec_open',
        realm: AppRealm.work,
        clockMode: ClockType.pomodoro,
        outcomeId: 'o_work',
        projectId: 'p_work',
        titleSnapshot: 'پیاده‌سازی موتور Flowmodoro',
        isUntitledDraft: false,
        startTime: DateTime.now().subtract(const Duration(minutes: 12)),
      ),
    );

    final provider = AppStateProvider(isTestMode: true);
    await provider.initialize();
    await provider.setWindowPosture(WindowPosture.dashboard);
    return (db, provider);
  }

  Widget buildHarness(AppStateProvider provider, Size surfaceSize) {
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

  testWidgets('Desktop dashboard switches Work <-> Life realms & shows recovery banner',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final result = await tester.runAsync(createSeededProvider);
    final (db, provider) = result!;
    addTearDown(() async {
      provider.dispose();
      DatabaseService.instance.resetForTest();
      await tester.runAsync(() => db.close());
    });

    await tester.pumpWidget(buildHarness(provider, const Size(1280, 800)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Mab-Focus v4.0'), findsOneWidget);
    expect(find.textContaining('بازیابی جلسه ناتمام'), findsOneWidget);
    expect(provider.dashboardRealm, AppRealm.work);
    expect(provider.activePalette.accent, RealmPalette.work.accent);

    // Switch dashboard realm to Life (Green)
    await tester.tap(find.text('زندگی').first);
    await tester.pump(const Duration(milliseconds: 200));

    expect(provider.dashboardRealm, AppRealm.life);
    expect(provider.activePalette.accent, RealmPalette.life.accent);

    // Navigate to Open Outcomes tab
    await tester.tap(find.textContaining('کارهای باز').first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('پیاده‌روی عصرگاهی'), findsOneWidget);
  });

  testWidgets('Narrow Android viewport renders NavigationBar with zero overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final result = await tester.runAsync(createSeededProvider);
    final (db, provider) = result!;
    addTearDown(() async {
      provider.dispose();
      DatabaseService.instance.resetForTest();
      await tester.runAsync(() => db.close());
    });

    await tester.pumpWidget(buildHarness(provider, const Size(390, 844)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('تقویم'), findsOneWidget);
    expect(find.text('کارها'), findsOneWidget);
    expect(find.text('یادداشت'), findsOneWidget);
    expect(find.text('بیشتر'), findsOneWidget);

    await tester.tap(find.text('کارها'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('پیاده‌سازی موتور Flowmodoro'), findsWidgets);

    await tester.tap(find.text('یادداشت'));
    await tester.pump(const Duration(milliseconds: 200));

    // Open More sheet and visit Studio, Capacity Thieves, Untitled Inbox, Settings
    for (final itemLabel in [
      'استودیوی پروژه‌های کار',
      'سند ظرفیت و سارقان زمان',
      'کارتابل نواقص (بدون عنوان)',
      'تنظیمات Flowmodoro و تقویم گوگل',
    ]) {
      await tester.tap(find.text('بیشتر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(itemLabel).last);
      await tester.pumpAndSettle();
    }
  });
}
