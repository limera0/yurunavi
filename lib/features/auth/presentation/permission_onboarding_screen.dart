import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../../map/presentation/main_map_screen.dart';

/// 첫 실행 권한 온보딩 (네이버지도·카카오내비 패턴)
/// 위치 / 알림 / 배터리 최적화 제외 / 다른 앱 위에 표시(선택) 를 항목별로 안내한다.
/// 전부 충족되면 자동 통과, 일부 거부해도 계속하기로 진행할 수 있다.
class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key});

  @override
  State<PermissionOnboardingScreen> createState() => _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen> {
  bool _loading = true;
  late List<_PermItem> _items;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
    _refreshStatuses();
  }

  List<_PermItem> _buildItems() => [
    _PermItem(
      icon: Icons.location_on_rounded,
      title: '위치 (필수)',
      desc: '현재 위치로 경로를 탐색합니다.',
      required: true,
      request: () async {
        final s = await Permission.location.request();
        return s.isGranted;
      },
      check: () async => (await Permission.location.status).isGranted,
    ),
    _PermItem(
      icon: Icons.notifications_rounded,
      title: '알림',
      desc: '주행 중 "유루나비 주행 중" 알림으로 GPS 절전을 방지합니다.',
      required: false,
      request: () async {
        final s = await Permission.notification.request();
        return s.isGranted;
      },
      check: () async => (await Permission.notification.status).isGranted,
    ),
    _PermItem(
      icon: Icons.battery_charging_full_rounded,
      title: '배터리 최적화 제외',
      desc: '5초 이상 절전으로 인한 GPS 끊김을 방지합니다.',
      required: false,
      request: () async {
        if (!Platform.isAndroid) return true;
        final s = await Permission.ignoreBatteryOptimizations.request();
        return s.isGranted;
      },
      check: () async {
        if (!Platform.isAndroid) return true;
        return (await Permission.ignoreBatteryOptimizations.status).isGranted;
      },
    ),
    _PermItem(
      icon: Icons.layers_rounded,
      title: '다른 앱 위에 표시 (선택)',
      desc: '주행 중 오버레이 HUD 기능에 사용됩니다.',
      required: false,
      request: () async {
        if (!Platform.isAndroid) return true;
        final s = await Permission.systemAlertWindow.request();
        return s.isGranted;
      },
      check: () async {
        if (!Platform.isAndroid) return true;
        return (await Permission.systemAlertWindow.status).isGranted;
      },
    ),
  ];

  Future<void> _refreshStatuses() async {
    setState(() => _loading = true);
    for (final item in _items) {
      item.granted = await item.check();
    }
    setState(() => _loading = false);

    // 필수 권한 포함 전부 충족 시 자동 통과
    final allGranted = _items.every((e) => e.granted);
    if (allGranted && mounted) _proceed();
  }

  void _proceed() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => const MainMapScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut), child: child),
      ),
    );
  }

  Future<void> _requestItem(_PermItem item) async {
    final granted = await item.request();
    if (!mounted) return;
    setState(() => item.granted = granted);
    if (!granted && item.required) {
      // 필수 권한이 영구 거부된 경우 설정으로 안내
      final status = await Permission.location.status;
      if (status.isPermanentlyDenied && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.location_off_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text('위치 권한 필요'),
            ]),
            content: const Text('설정에서 위치 권한을 허용해 주세요.\n유루나비의 핵심 기능은 현재 위치에 의존합니다.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('나중에')),
              ElevatedButton(
                onPressed: () async { Navigator.pop(ctx); await openAppSettings(); },
                child: const Text('설정 열기'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 36),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(alpha: 0.12),
                          ),
                          child: const Icon(Icons.shield_rounded, color: AppColors.primary, size: 28),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '권한 설정',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '유루나비가 원활하게 동작하려면\n아래 권한이 필요합니다.',
                          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _PermissionCard(
                        item: _items[i],
                        onRequest: () => _requestItem(_items[i]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _proceed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(
                          _items.where((e) => e.required && !e.granted).isNotEmpty
                              ? '위치 권한 없이 계속'
                              : '시작하기',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PermItem {
  final IconData icon;
  final String title;
  final String desc;
  final bool required;
  final Future<bool> Function() request;
  final Future<bool> Function() check;
  bool granted = false;

  _PermItem({
    required this.icon,
    required this.title,
    required this.desc,
    required this.required,
    required this.request,
    required this.check,
  });
}

class _PermissionCard extends StatelessWidget {
  final _PermItem item;
  final VoidCallback onRequest;
  const _PermissionCard({required this.item, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.granted
              ? AppColors.success.withValues(alpha: 0.4)
              : (item.required ? AppColors.primary.withValues(alpha: 0.3) : Colors.transparent),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.granted
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.primary.withValues(alpha: 0.1),
            ),
            child: Icon(
              item.icon,
              size: 20,
              color: item.granted ? AppColors.success : AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(item.desc,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          item.granted
              ? const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24)
              : TextButton(
                  onPressed: onRequest,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('허용',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ),
        ],
      ),
    );
  }
}
