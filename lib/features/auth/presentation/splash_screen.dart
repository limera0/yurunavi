import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_theme.dart';
import '../../map/presentation/main_map_screen.dart';

/// YuruNavi Splash Screen
/// - 로고 fade + scale 애니메이션
/// - Firebase Auth 상태 확인 후 라우팅 (현재는 MainMapScreen으로 직행)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeIn),
      ),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    await _ctrl.forward();
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    await _requestPermission();
    if (!mounted) return;
    _goToMain();
  }

  Future<void> _requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always) {
      return; // already granted
    }

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (!mounted) return;
    if (perm == LocationPermission.deniedForever) {
      await _showSettingsDialog(
        '위치 권한이 거부됨',
        '설정에서 위치 권한을 허용해 주세요.\n유루나비의 핵심 기능은 현재 위치에 의존합니다.',
        actionLabel: '설정 열기',
        onAction: Geolocator.openAppSettings,
      );
    } else if (perm == LocationPermission.denied) {
      await _showSettingsDialog(
        '위치 권한 필요',
        '유루나비는 현재 위치로 경로를 탐색합니다.\n권한 없이도 사용할 수 있지만 일부 기능이 제한됩니다.',
        actionLabel: '다시 허용',
        onAction: Geolocator.requestPermission,
      );
    }
  }

  Future<void> _showSettingsDialog(
    String title,
    String content, {
    required String actionLabel,
    required Future<dynamic> Function() onAction,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.location_on, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(title),
        ]),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('건너뛰기'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onAction();
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  void _goToMain() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) => const MainMapScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: _goToMain,
        child: Center(
          child: FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              child: _LogoWidget(),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 로고 이미지 ──────────────────────────────────────
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/yuru_circle.jpeg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  'YURU\nNAVI',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        // ── 태그라인 ─────────────────────────────────────────
        Text(
          '유루나비',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '이륜차를 위한 감성 내비게이션',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }
}
