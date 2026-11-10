import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'core/constants.dart';
import 'core/platform_helper.dart';
import 'models/pomodoro_state.dart';
import 'providers/app_state_provider.dart';
import 'services/music_player_service.dart';
import 'ui/app_shell.dart';
import 'ui/shared/work_note_standalone_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (PlatformHelper.isDesktop) {
    try {
      final windowController = await WindowController.fromCurrentEngine();
      if (windowController.arguments.isNotEmpty) {
        final Map<String, dynamic> data =
            jsonDecode(windowController.arguments);
        if (data['type'] == 'work_note') {
          runApp(WorkNoteStandaloneApp(
            windowController: windowController,
            realm: AppRealmX.fromDb(data['realm'] as String?),
            timeRecordId: data['timeRecordId'] as String?,
            outcomeId: data['outcomeId'] as String?,
            projectId: data['projectId'] as String?,
            taskTitle: data['taskTitle'] as String? ?? 'تسک بدون عنوان',
            projectName: data['projectName'] as String?,
            projectColorHex: data['projectColorHex'] as String?,
          ));
          return;
        }
      }
    } catch (_) {}
  }

  await PlatformHelper.initWindowManager();

  final appState = AppStateProvider();
  await appState.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        ChangeNotifierProvider<MusicPlayerService>.value(
            value: MusicPlayerService.instance),
      ],
      child: const MabFocusApp(),
    ),
  );
}

class MabFocusApp extends StatelessWidget {
  const MabFocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.select<AppStateProvider, RealmPalette>(
      (p) => p.activePalette,
    );
    final isLife = context.select<AppStateProvider, bool>(
      (p) => p.dashboardRealm == AppRealm.life,
    );
    final baseTextTheme =
        GoogleFonts.vazirmatnTextTheme(ThemeData.dark().textTheme);

    return MaterialApp(
      title: 'Mab-Focus v4.0',
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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: palette.background,
        colorScheme: ColorScheme.dark(
          primary: palette.accent,
          secondary: isLife ? AppColors.workBlue : AppColors.lifeGreen,
          surface: palette.surface,
          error: Colors.redAccent,
        ),
        textTheme: baseTextTheme.apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
        cardTheme: CardThemeData(
          color: palette.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.border, width: 1),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}
