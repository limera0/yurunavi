import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/splash_screen.dart';
import 'features/map/providers/map_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const SplashScreen(),
    );
  }
}
