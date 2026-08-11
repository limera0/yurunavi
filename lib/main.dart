import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/crash_reporting.dart';
import 'core/logging/file_logger.dart';
import 'core/logging/native_log_bridge.dart';
import 'core/memory/gpu_mem_sampler.dart';
import 'core/memory/memory_pressure_observer.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/splash_screen.dart';
import 'firebase_options.dart';
import 'providers/app_providers.dart';
import 'services/route_share_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter 기본 imageCache 상한(1000장/100MB)은 저사양 기기(RAM 3.7GB급)엔
  // 과도하다 — 유루나비는 Image.asset/SvgPicture.asset/NetworkImage를 7곳
  // (profile_screen ×3, splash_screen ×1, slider_start_button ×1, nav_screen
  // ×2)에서만 쓰고, 지도 타일/POI 아이콘은 MapLibre 네이티브 텍스처 풀을
  // 거쳐 이 캐시와 무관하다. 실사용 7곳보다 여유를 둔 40장(기본 대비 25배
  // 축소), 20MB(기본 대비 5배 축소)로 낮춘다.
  PaintingBinding.instance.imageCache.maximumSize = 40;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 << 20; // 20MB
  // OS 메모리 압박(didHaveMemoryPressure)과 백그라운드 진입 시 imageCache를
  // 비운다 — Organic Maps의 MemoryWarning()/EnterBackground() 대응.
  MemoryPressureObserver.init();
  AppConfig.init(const ProdConfig());
  // 프로세스 강제종료(태스크 스와이프/OEM 배터리 매니저/OOM)로 인해 요약이
  // 저장되지 못한 고아 투어 트랙 복구는 S15("이어서 안내하기")부터 스플래시
  // 화면(`splash_screen.dart`)으로 옮겨졌다 — 재개 프롬프트가 이 복구의
  // 완료를 기다려야 하므로 여기서 fire-and-forget으로 먼저 실행하면 경합이
  // 생긴다.
  await initCrashReporting(DefaultFirebaseOptions.currentPlatform);
  await FileLogger.init();
  // _sink가 준비된 뒤에만 구독 시작 — writeRaw()가 _sink에 직접 쓰기 때문.
  NativeLogBridge.start();
  // FileLogger.init() 이후에만 시작 — debugPrint 가로채기가 준비돼 있어야
  // YNAV_GPUMEM 줄이 파일에 기록된다.
  GpuMemSampler.start();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  // 릴리스에서만: build()가 던지면 기본 ErrorWidget이 회색/흰 박스를 그려
  // "백화"로 보인다 — 서브트리를 대신 투명하게 비워 눈에 띄지 않게 한다.
  // Crashlytics 보고(FlutterError.onError)는 이 위젯 교체와 무관하게 그대로
  // 동작한다. 디버그 빌드는 개발 중 에러를 숨기면 안 되므로 기본 빨간 박스를 유지.
  if (kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) => const SizedBox.shrink();
  }
  runApp(const ProviderScope(child: YuruNaviApp()));
}

class YuruNaviApp extends ConsumerStatefulWidget {
  const YuruNaviApp({super.key});

  @override
  ConsumerState<YuruNaviApp> createState() => _YuruNaviAppState();
}

class _YuruNaviAppState extends ConsumerState<YuruNaviApp> {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();

    // 앱 종료 상태에서 딥링크로 시작된 경우
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (_) {}

    // 앱 실행 중 수신
    _linkSub = appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (_) {},
    );
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'yurunavi' || uri.host != 'route') return;
    final route = RouteShareService.decodeRoute(uri.toString());
    if (route == null) return;
    if (!mounted) return;
    ref.read(pendingDeepLinkRouteProvider.notifier).state = route;
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
