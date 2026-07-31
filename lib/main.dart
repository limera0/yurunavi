import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/crash_reporting.dart';
import 'core/logging/file_logger.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/splash_screen.dart';
import 'firebase_options.dart';
import 'providers/app_providers.dart';
import 'services/tour_recovery_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.init(const ProdConfig());
  // 프로세스 강제종료(태스크 스와이프/OEM 배터리 매니저/OOM)로 인해 요약이
  // 저장되지 못한 고아 투어 트랙을 백그라운드에서 복구한다 — 앱 시작을
  // 지연시키면 안 되므로 await 없이 fire-and-forget으로 호출한다.
  unawaited(TourRecoveryService().recoverOrphans());
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
    final pastSplash = ref.watch(pastSplashProvider);
    if (pastSplash) {
      // Post-splash: every screen (home/map, course sheet, route option
      // sheet, ...) shares one unified status/navigation bar color —
      // loop/layout_fixes/PROGRESS.md 라운드2. Re-applied on every rebuild
      // so it survives any reason YuruNaviApp re-renders.
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: kSystemBarColor,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: kSystemBarColor,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ));
    } else {
      // Splash screen only — status bar stays transparent, but nav bar
      // still needs to match the splash background (loop/layout_fixes/
      // PROGRESS.md 라운드1) instead of the OS default black.
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ));
    }

    return MaterialApp(
      title: 'YuruNavi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
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
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}
