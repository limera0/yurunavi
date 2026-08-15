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
  final List<({double km, int mins})> routeMeta;
  final int selectedIdx;
  final ValueChanged<int> onSelect;
  final VoidCallback onStart;
  final VoidCallback onClose;

  /// 경유지 수 (0이면 회색 "경유지" 텍스트, 1개면 지명, 2개 이상이면 "경유지 N곳")
  final int waypointCount;

  /// 경유지 지명 목록 (`waypointCount == 1`일 때 첫 항목을 표시)
  final List<String?> waypointNames;

  /// 경유지 진입점 탭 콜백 (null이면 탭 비활성)
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
    this.waypointNames = const [],
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

          // 출발 >> 경유지 >> 도착 요약 (originName / destinationName 있을 때만)
          if (originName != null || destinationName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onWaypointEntryTap,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        originName ?? '현재 위치',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '>>',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHint),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: onWaypointEntryTap,
                      behavior: HitTestBehavior.opaque,
                      child: _WaypointSummarySegment(
                        count: waypointCount,
                        names: waypointNames,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '>>',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHint),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: onWaypointEntryTap,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        destinationName ?? '목적지',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
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
                final distStr = hasMeta ? '${distKm.toStringAsFixed(0)}km' : '---';
                final durStr = hasMeta ? _durFromMins(mins) : '---';
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

/// 코스 요약 행 가운데 세그먼트 — 경유지 0개면 회색 "경유지" 텍스트, 1개면
/// 지명, 2개 이상이면 "경유지 N곳". 전체가 [CourseSheet]에서 탭 가능하게
/// 감싸져 `onWaypointEntryTap`으로 연결된다.
class _WaypointSummarySegment extends StatelessWidget {
  final int count;
  final List<String?> names;

  const _WaypointSummarySegment({required this.count, required this.names});

  @override
  Widget build(BuildContext context) {
    final String text;
    final bool isPlaceholder;
    if (count <= 0) {
      text = '경유지';
      isPlaceholder = true;
    } else if (count == 1) {
      text = names.isNotEmpty ? (names.first ?? '경유지') : '경유지';
      isPlaceholder = false;
    } else {
      text = '경유지 $count곳';
      isPlaceholder = false;
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: isPlaceholder ? AppColors.textHint : AppColors.textSecondary,
        fontWeight: isPlaceholder ? FontWeight.w400 : FontWeight.w600,
      ),
    );
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
  final bool isSelected;
  final VoidCallback onTap;

  const RouteCard({
    super.key,
    required this.info,
    required this.distStr,
    required this.duration,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.14)
              : color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.textHint.withValues(alpha: 0.22),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.24),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.20 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                info.label,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelMD.copyWith(
                  fontSize: 13,
                  color: isSelected ? color : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              distStr,
              style: AppTextStyles.titleSM.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              duration,
              style: AppTextStyles.labelSM.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
