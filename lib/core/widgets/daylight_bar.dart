import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 우측 세로 Daylight 인디케이터 — 메인 화면과 내비 화면 모두 이 위젯을 사용한다.
///
/// 낮(Brightness.light) : 흰 컨테이너, 태양(황금)→달(남색) 그라디언트, 주황 핸들
/// 밤/라이더(Brightness.dark): 어두운 컨테이너, 남색→하늘 그라디언트, 청색 핸들
class DaylightBar extends StatelessWidget {
  final double progress; // 0.0(BMNT) ~ 1.0(EENT)
  final String sunriseLabel;
  final String sunsetLabel;

  const DaylightBar({
    super.key,
    required this.progress,
    required this.sunriseLabel,
    required this.sunsetLabel,
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
    final isNight = cs.brightness == Brightness.dark;

    final containerBg = isNight
        ? cs.surface.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);
    final shadowColor = isNight
        ? Colors.black.withValues(alpha: 0.3)
        : AppColors.secondary.withValues(alpha: 0.12);
    final sunriseColor = isNight ? cs.onSurfaceVariant : AppColors.sunrise;
    final sunsetColor = isNight ? cs.tertiary : AppColors.sunset;
    final handleBorder = isNight ? cs.tertiary : AppColors.primary;
    final handleInner = isNight ? cs.surface : Colors.white;

    final gradient = isNight
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A237E), // 자정 남색
              Color(0xFF3949AB), // 새벽 남색
              Color(0xFF5C6BC0), // 여명 연남
              Color(0xFFFFD54F), // 일출 황금
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFD54F), // 일출 황금
              Color(0xFFFFB300), // 정오
              Color(0xFF90CAF9), // 황혼 파랑
              Color(0xFF1A237E), // 일몰 심야
            ],
            stops: [0.0, 0.45, 0.75, 1.0],
          );

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
                          gradient: gradient,
                        ),
                      ),
                      Positioned(
                        top: handleY.clamp(0.0, totalH - 16),
                        left: -5,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: handleInner,
                            shape: BoxShape.circle,
                            border: Border.all(color: handleBorder, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: handleBorder.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
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
