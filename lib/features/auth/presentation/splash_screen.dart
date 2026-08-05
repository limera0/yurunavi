import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/routing_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../map/presentation/main_map_screen.dart';

/// 스플래시 위치 선확보 예산 (S0) — `getCurrentPosition()` 자체 타임아웃이자,
/// `_goToMain()` 직전 대기 상한이기도 하다. 이 시간을 넘기면 조용히 포기하고
/// 앱은 정상 진입한다(블로킹 금지).
const Duration kBootLocationBudget = Duration(seconds: 3);

/// 위치 선확보 순수 로직 — 위젯/Riverpod에 의존하지 않아 플랫폼 채널만
/// 목킹하면 단위 테스트가 가능하다(`test/splash_boot_location_test.dart`).
///
/// 1) `getLastKnownPosition()`을 즉시 시도한다 — 값이 있으면 [onIntermediate]로
///    즉시 통지해 확정값으로 채택할 수 있게 한다.
/// 2) 이어서 `getCurrentPosition()`을 [budget] 타임아웃으로 시도해, 성공하면
///    더 정확한 값으로 교체한다.
/// 실패/타임아웃/예외는 전부 무해하게 삼키고, 마지막으로 확보한 값(or null)을
/// 반환한다 — 호출부를 절대 블로킹하지 않는다.
Future<LatLng?> acquireBootLocation({
  Duration budget = kBootLocationBudget,
  void Function(LatLng loc)? onIntermediate,
}) async {
  LatLng? best;
  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      best = LatLng(last.latitude, last.longitude);
      onIntermediate?.call(best);
    }
  } catch (_) {} // 권한 미취득 등 — 무시하고 다음 단계로 진행

  try {
    final current = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: budget,
      ),
    );
    best = LatLng(current.latitude, current.longitude);
  } catch (_) {} // 타임아웃/서비스 꺼짐 등 — best(있다면 last-known)를 그대로 반환

  return best;
}

/// [future]를 [startedAt] 기준 남은 예산만큼만 기다린다("남은" = [budget] -
/// [now]() 시점까지 [startedAt]로부터 경과한 시간). 예산이 이미 소진됐으면
/// (remaining <= 0) [future]를 전혀 await하지 않고 즉시 null을 반환한다 —
/// [future] 자체는 백그라운드에서 계속 진행되며 취소되지 않는다. 예산이
/// 남아 있으면 그만큼만 기다리고, 그 안에 완료되지 않으면(TimeoutException)
/// 조용히 null을 반환한다.
///
/// [startedAt]은 "이 확보가 실제로 시작된 시각"이어야 한다 — 스플래시가
/// 여러 진입 경로(권한 이미 보유 vs 팝업 직후 허용)를 가지므로, 호출부는
/// 반드시 [future]를 만든 바로 그 지점에서 `now()`를 찍어 넘겨야 한다.
/// 고정된 함수-진입 시각을 재사용하면(2026-08-05 code-auditor 지적: 최초
/// 실행 경로에서 팝업 응답을 기다리는 동안 이미 예산이 소진된 것처럼
/// 계산돼, 방금 시작한 확보를 단 한 번도 기다리지 않고 즉시 진입해버리는
/// 죽은 코드가 된다) 이 함수의 "남은 예산만큼만 기다린다"는 계약이 깨진다.
///
/// 위젯/Riverpod에 의존하지 않는 순수 함수라 `test/splash_boot_location_test.dart`가
/// 직접 검증한다.
@visibleForTesting
Future<LatLng?> awaitWithinBudget(
  Future<LatLng?> future, {
  required DateTime startedAt,
  DateTime Function() now = DateTime.now,
  Duration budget = kBootLocationBudget,
}) async {
  final remaining = budget - now().difference(startedAt);
  if (remaining <= Duration.zero) return null;
  try {
    return await future.timeout(remaining, onTimeout: () => null);
  } catch (_) {
    return null;
  }
}

/// YuruNavi Splash Screen
/// - 로고 fade + scale 애니메이션
/// - 위치·알림 권한 OS 팝업 1회 요청 (미허용 시 skip, 2회차는 granted라 skip)
/// - 위치 권한이 이미 있으면(2회차 이후) 애니메이션과 병렬로 위치를 선확보해
///   `bootLocationProvider`에 채워 넣는다 — 콜드 스타트 시 지도가 폴백 좌표가
///   아니라 실제 위치로 열리게 하기 위함(S0). 추가 지연은 0이 원칙이며,
///   최악의 경우에도 `_goToMain()` 직전 대기는 [kBootLocationBudget]을 넘지 않는다.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
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
    // 위치 확보가 실제로 "시작된" 시각 — 두 진입 경로(권한 이미 보유 vs 팝업
    // 직후 허용) 각각 자기 자신이 확보를 시작하는 바로 그 지점에서 찍는다.
    // 함수 진입 시각(t=0)을 고정으로 재사용하면(2026-08-05 code-auditor
    // 지적) 최초 실행 경로에서 고정 지연(1.7초) + 팝업 응답 시간만으로 이미
    // "예산 소진"으로 계산돼, 막 시작한 확보를 단 한 번도 기다리지 않고
    // 바로 진입해버리는 죽은 코드가 된다 — awaitWithinBudget() 문서 참조.
    DateTime? locationStartedAt;

    // 이미 위치 권한이 있으면(2회차 이후 모든 실행이 여기 해당) 로고 애니메이션과
    // 완전히 병렬로 위치 확보를 시작한다 — 팝업을 앞당기는 게 아니라 확보
    // 시작 시점만 앞당긴다.
    Future<LatLng?>? locationFuture;
    if ((await Permission.location.status).isGranted) {
      locationStartedAt = DateTime.now();
      locationFuture = _acquireBootLocation();
    }

    await Future.delayed(const Duration(milliseconds: 200));
    await _ctrl.forward();
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    await _requestPermissions();
    if (!mounted) return;
    // 최초 실행 경로: 팝업에서 방금 허용됐으면 여기서 확보를 시작한다(이미
    // 위에서 시작한 경우는 건너뛴다) — 시작 시각도 지금 이 지점에서 찍는다.
    if (locationFuture == null && (await Permission.location.status).isGranted) {
      locationStartedAt = DateTime.now();
      locationFuture = _acquireBootLocation();
    }
    if (!mounted) return;
    await RoutingConfig.loadRemote(AppConfig.instance.naviBaseUrl);
    if (!mounted) return;

    // 확보가 진행 중이면 그 시작 시각 기준 남은 예산만큼만 기다린다 —
    // 애니메이션이 이미 대부분의 예산을 소모한 경로(권한 기보유)라면 통상
    // 추가 지연은 0, 최악의 경우에도 확보 시작으로부터 kBootLocationBudget을
    // 넘기지 않는다. 실패/타임아웃은 조용히 통과.
    if (locationFuture != null && locationStartedAt != null) {
      await awaitWithinBudget(locationFuture, startedAt: locationStartedAt);
    }
    if (!mounted) return;
    _goToMain();
  }

  /// [acquireBootLocation]을 호출해 결과를 `bootLocationProvider`에 채운다.
  /// 중간값(getLastKnownPosition)이 나오는 즉시 반영하고, 이후 더 정확한
  /// getCurrentPosition 결과가 나오면 교체한다.
  Future<LatLng?> _acquireBootLocation() => acquireBootLocation(
        onIntermediate: (loc) {
          if (mounted) ref.read(bootLocationProvider.notifier).set(loc);
        },
      ).then((loc) {
        if (loc != null && mounted) {
          ref.read(bootLocationProvider.notifier).set(loc);
        }
        return loc;
      });

  /// 위치·알림 권한을 OS 표준 팝업으로 1회씩 요청한다.
  /// 이미 granted면 팝업 없이 즉시 통과. 2회차 실행도 granted라 skip.
  Future<void> _requestPermissions() async {
    if (!(await Permission.location.status).isGranted) {
      await Permission.location.request();
    }
    if ((await Permission.location.status).isGranted) {
      // 첫 실행: 권한 denied 상태로 이미 닫힌(죽은) 스트림을 폐기 → 권한 있는 상태로 재생성.
      ref.invalidate(locationStreamProvider);
      ref.listenManual(locationStreamProvider, (_, _) {});
    }
    if (!mounted) return;
    if (!(await Permission.notification.status).isGranted) {
      await Permission.notification.request();
    }
  }
  void _goToMain() {
    // 스플래시 → 메인 전환 시점: 여기부터 앱 전역 상태바/내비바 색상 통일이
    // 적용되도록 신호를 켠다(loop/layout_fixes/PROGRESS.md 라운드2).
    ref.read(pastSplashProvider.notifier).markPastSplash();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => const MainMapScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
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
      ],
    );
  }
}
