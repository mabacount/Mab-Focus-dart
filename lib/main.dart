import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'core/constants.dart';
import 'core/platform_helper.dart';
import 'providers/app_state_provider.dart';
import 'services/music_player_service.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    final baseTextTheme =
        GoogleFonts.vazirmatnTextTheme(ThemeData.dark().textTheme);

    return MaterialApp(
      title: 'Mab-Focus v3.0',
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
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.focus,
          secondary: AppColors.breakTime,
          surface: AppColors.surface,
          error: Colors.redAccent,
        ),
        textTheme: baseTextTheme.apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}
