import 'package:flutter/material.dart';

import '../skin/skin_provider.dart';
import '../theme/app_theme.dart';
import 'slider_start_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Course Selection Sheet
// 와이어프레임: 카드 3개 → [Start your Engine 슬라이더]
// Shared between home (main_map_screen) and nav (nav_screen) — purely
// callback-driven, no hidden coupling to either screen's state.
// ─────────────────────────────────────────────────────────────────────────────

class CourseSheet extends StatelessWidget {
  final List<({double km, int mins, double windingScore})> routeMeta;
  final int selectedIdx;
  final ValueChanged<int> onSelect;
  final VoidCallback onStart;
  final VoidCallback onClose;

  /// 경유지 수 (0이면 "+ 경유지 추가" 텍스트 버튼, 1 이상이면 "경유지 N개 · 편집" 칩)
  final int waypointCount;

  /// 경유지 진입점 탭 콜백 (null이면 버튼 미표시)
  final VoidCallback? onWaypointEntryTap;

  /// 출발지 이름 (null이면 stops 요약 행 미표시)
  final String? originName;

  /// 목적지 이름 (null이면 stops 요약 행 미표시)
  final String? destinationName;

  const CourseSheet({
    super.key,
    required this.routeMeta,
    required this.selectedIdx,
    required this.onSelect,
    required this.onStart,
    required this.onClose,
    this.waypointCount = 0,
    this.onWaypointEntryTap,
    this.originName,
    this.destinationName,
  });

  @override
  Widget build(BuildContext context) {
    final courseLineColor = context.skin.colors.courseLineColor;
    final routes = [
      RouteInfo('시골길로\n느긋하게', courseLineColor[0]!),
      RouteInfo('지방도로\n여유롭게', courseLineColor[1]!),
      RouteInfo('국도로\n빠르게', courseLineColor[2]!),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 닫기 버튼 행 (우측)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onClose,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(0, 0, 14, 0),
                child: Icon(Icons.close_rounded,
                    size: 20, color: AppColors.textHint),
              ),
            ),
          ),

          // 출발·도착 요약 (originName / destinationName 있을 때만)
          if (originName != null || destinationName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
              child: Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(
                        color: Colors.blue, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      originName ?? '현재 위치',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      waypointCount > 0 ? '· 경유 $waypointCount개 ·' : '→',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textHint),
                    ),
                  ),
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: Colors.red.shade400, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      destinationName ?? '목적지',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // 경유지 진입점 (경유지 있으면 칩, 없으면 텍스트 버튼)
          if (onWaypointEntryTap != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: waypointCount > 0
                    ? ActionChip(
                        avatar: const Icon(Icons.route, size: 16),
                        label: Text('경유지 $waypointCount개 · 편집'),
                        onPressed: onWaypointEntryTap,
                      )
                    : TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('경유지 추가'),
                        onPressed: onWaypointEntryTap,
                      ),
              ),
            ),

          // 3가지 경로 카드
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Row(
              children: List.generate(routes.length, (i) {
                final r = routes[i];
                final hasMeta = routeMeta.length > i;
                final distKm = hasMeta ? routeMeta[i].km : 0.0;
                final mins = hasMeta ? routeMeta[i].mins : 0;
                final ws = hasMeta ? routeMeta[i].windingScore : 0.0;
                final distStr = hasMeta ? '${distKm.toStringAsFixed(0)}km' : '---';
                final durStr = hasMeta ? _durFromMins(mins) : '---';
                // best fun score among loaded routes
                final bestWs = routeMeta.isEmpty ? 0.0
                    : routeMeta.map((m) => m.windingScore).reduce((a, b) => a > b ? a : b);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 5,
                      right: i == 2 ? 0 : 5,
                    ),
                    child: RouteCard(
                      info: r,
                      distStr: distStr,
                      duration: durStr,
                      windingScore: ws,
                      isBestFun: hasMeta && ws >= bestWs && ws > 0,
                      isSelected: selectedIdx == i,
                      onTap: () => onSelect(i),
                    ),
                  ),
                );
              }),
            ),
          ),

          // Start your Engine 슬라이더
          SliderStartButton(onSlideComplete: onStart),
        ],
      ),
    );
  }

  String _durFromMins(int m) {
    final h = m ~/ 60;
    final min = m % 60;
    return h > 0 ? '$h시간 $min분' : '$min분';
  }
}

class RouteInfo {
  final String label;
  final Color color;
  const RouteInfo(this.label, this.color);
}

class RouteCard extends StatelessWidget {
  final RouteInfo info;
  final String distStr;
  final String duration;
  final double windingScore;
  final bool isBestFun;
  final bool isSelected;
  final VoidCallback onTap;

  const RouteCard({
    super.key,
    required this.info,
    required this.distStr,
    required this.duration,
    this.windingScore = 0.0,
    this.isBestFun = false,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = info.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.09) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.textHint.withValues(alpha: 0.28),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              info.label,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelMD.copyWith(
                color: isSelected ? color : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              distStr,
              style: AppTextStyles.titleSM.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            Text(
              duration,
              style: AppTextStyles.labelSM.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
            if (windingScore > 0)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isBestFun
                        ? info.color.withValues(alpha: 0.15)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isBestFun
                        ? '★ 재미 ${windingScore.toStringAsFixed(0)}'
                        : '재미 ${windingScore.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: isBestFun ? FontWeight.w700 : FontWeight.w400,
                      color: isBestFun ? info.color : AppColors.textHint,
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
