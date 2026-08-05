import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/safe_clamp.dart';

/// 우측 세로 Daylight 인디케이터 — 메인 화면과 내비 화면 모두 이 위젯을 사용한다.
///
/// isNightMode=false (낮): 상단=해 아이콘, 하단=달 아이콘
/// isNightMode=true  (밤): 상단=달 아이콘, 하단=해 아이콘
/// isNightMode=null  : 테마 밝기로 자동 결정 (기존 동작 유지)
class DaylightBar extends StatelessWidget {
  final double progress; // 0.0(구간 시작) ~ 1.0(구간 끝)
  final String sunriseLabel;
  final String sunsetLabel;
  final bool? isNightMode; // null=테마 자동, true=밤, false=낮

  // 가용 높이가 이 미만이면 아무것도 그리지 않는다. 축약형 크롬(상/하단 아이콘
  // 18px + 상하 패딩 10px씩 + 아이콘 사이 간격 8px×2, 라벨 없음) 상하 합만으로
  // 이미 72px이라 — 그보다 작으면 아이콘 두 개조차 겹치지 않고는 못 들어간다.
  // (RenderFlex overflow는 dart:core 예외는 아니지만 flutter test에서는
  // tester.takeException()에 잡히는 별개의 실패 원인이라 여기서도 막아야 한다.)
  static const double _kAbbrevMinH = 72;

  // 고정 크롬(상/하단 아이콘 18px + 시간 라벨 ~9px + 패딩·간격) 상하 합 ≈ 94px +
  // 게이지 최소 24px(핸들 아이콘 지름) = 118px. 이 미만이면 시간 라벨을 생략한
  // 축약형으로 렌더한다.
  static const double _kFullRenderMinH = 118;

  const DaylightBar({
    super.key,
    required this.progress,
    required this.sunriseLabel,
    required this.sunsetLabel,
    this.isNightMode,
  });

  factory DaylightBar.legacy({
    Key? key,
    required double progress,
    required String bmntLabel,
    required String eentLabel,
  }) =>
      DaylightBar(
        key: key,
        progress: progress,
        sunriseLabel: bmntLabel,
        sunsetLabel: eentLabel,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNight = isNightMode ?? (cs.brightness == Brightness.dark);

    final containerBg = isNight
        ? cs.surface.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);
    final shadowColor = isNight
        ? Colors.black.withValues(alpha: 0.3)
        : AppColors.secondary.withValues(alpha: 0.12);
    final sunriseColor = isNight ? cs.onSurfaceVariant : AppColors.sunrise;
    final sunsetColor = isNight ? cs.tertiary : AppColors.sunset;

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final availH = outerConstraints.maxHeight;
        // 가용 높이를 알 수 없거나(무한) 너무 작으면 아무것도 그리지 않는다.
        if (!availH.isFinite || availH < _kAbbrevMinH) {
          return const SizedBox.shrink();
        }
        final showLabels = availH >= _kFullRenderMinH;

        return Container(
          width: 38,
          decoration: BoxDecoration(
            color: containerBg,
            borderRadius: BorderRadius.circular(19),
            boxShadow: [
              BoxShadow(color: shadowColor, blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 일출(낮)/달(밤) 아이콘 (+ 축약형 아니면 시간 라벨) ──────
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    Icon(
                      isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                      size: 18,
                      color: isNight ? sunsetColor : sunriseColor,
                    ),
                    if (showLabels) ...[
                      const SizedBox(height: 2),
                      Text(
                        sunriseLabel,
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                          color: sunriseColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── 게이지 바 ────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final totalH = constraints.maxHeight;
                      // 크롬이 가용 높이를 다 잡아먹어 게이지 자리가 0 이하로
                      // 내려가는 경우(축약형에서도 발생 가능) — 아무것도 그리지 않는다.
                      if (!totalH.isFinite || totalH <= 0) {
                        return const SizedBox.shrink();
                      }
                      final handleY =
                          (totalH * progress.clamp(0.0, 1.0)) - 8;
                      // 24px 핸들 아이콘이 들어갈 자리가 없으면 바만 그린다.
                      final showHandle = totalH >= 24;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 6,
                            height: totalH,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: isNight
                                  ? const Color(0xFF1A237E)
                                  : const Color(0xFFFFF59D),
                            ),
                          ),
                          if (showHandle)
                            Positioned(
                              top: handleY.clampSafe(0.0, totalH - 24).toDouble(),
                              left: -9,  // 6px 바를 기준으로 24px 아이콘 센터 맞춤 (-9 = (6-24)/2)
                              child: Icon(
                                isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                                size: 24,
                                color: isNight
                                    ? const Color(0xFFFFF9C4)
                                    : const Color(0xFFFFB300),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── 일몰(낮)/해(밤) 아이콘 (+ 축약형 아니면 시간 라벨) ──────
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    if (showLabels) ...[
                      Text(
                        sunsetLabel,
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                          color: sunsetColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Icon(
                      isNight ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                      size: 18,
                      color: sunsetColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
