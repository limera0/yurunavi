import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
          // ── 일출(낮)/달(밤) 아이콘 + 시간 라벨 ──────────────────
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              children: [
                Icon(
                  isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  size: 18,
                  color: isNight ? sunsetColor : sunriseColor,
                ),
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
                  final handleY = (totalH * progress.clamp(0.0, 1.0)) - 8;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 6,
                        height: totalH,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: isNight ? const Color(0xFF1A237E) : const Color(0xFFFFF59D),
                        ),
                      ),
                      Positioned(
                        top: handleY.clamp(0.0, totalH - 24),
                        left: -9,  // 6px 바를 기준으로 24px 아이콘 센터 맞춤 (-9 = (6-24)/2)
                        child: Icon(
                          isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                          size: 24,
                          color: isNight ? const Color(0xFFFFF9C4) : const Color(0xFFFFB300),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── 일몰(낮)/해(밤) 아이콘 + 시간 라벨 ──────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                Text(
                  sunsetLabel,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    color: sunsetColor,
                  ),
                ),
                const SizedBox(height: 2),
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
  }
}
