import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/crash_reporting.dart';
import 'core/logging/file_logger.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/splash_screen.dart';
import 'features/map/providers/map_providers.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initCrashReporting(DefaultFirebaseOptions.currentPlatform);
  await FileLogger.init();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ProviderScope(child: YuruNaviApp()));
}

class YuruNaviApp extends ConsumerWidget {
  const YuruNaviApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riderMode = ref.watch(riderModeProvider);
    final isNight = ref.watch(isNightProvider);
    final theme = riderMode
        ? AppTheme.rider
        : (isNight ? AppTheme.night : AppTheme.light);
    final isDark = riderMode || isNight;

    // Status bar brightness flips with theme.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp(
      title: 'YuruNavi',
      debugShowCheckedModeBanner: false,
      theme: theme,
      // 다국어 지원: 한국어(기본) + 일본어. ARB는 lib/l10n/, flutter gen-l10n 으로 생성.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko'),
        Locale('ja'),
      ],
      locale: const Locale('ko'),
      home: const SplashScreen(),
    );
  }
}
