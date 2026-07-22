import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/routing_service.dart';
import '../providers/map_providers.dart';

/// 경유지 관리 바텀 시트.
///
/// [DraggableScrollableSheet]로 감싸 초기 60% / 최대 90% / 최소 40% 로 표시.
/// stops 배열을 [ReorderableListView]로 나열하고, 순서 변경 / 경유지 삭제 후
/// [RoutingService.fetchRoutes]로 즉시 경로를 재계산한다.
class WaypointManagementSheet extends ConsumerStatefulWidget {
  /// "＋ 경유지 추가" 버튼 탭 시 호출되는 콜백 (시트를 닫고 지도로 복귀).
  final VoidCallback? onAddWaypoint;

  const WaypointManagementSheet({super.key, this.onAddWaypoint});

  @override
  ConsumerState<WaypointManagementSheet> createState() =>
      _WaypointManagementSheetState();
}

class _WaypointManagementSheetState
    extends ConsumerState<WaypointManagementSheet> {
  bool _isRecalculating = false;

  // ── 경로 재계산 ────────────────────────────────────────────────────────────

  Future<void> _recalculate() async {
    final st = ref.read(mapInteractionProvider);
    final origin = st.origin;
    final dest = st.destination;
    if (origin == null || dest == null) return;

    setState(() => _isRecalculating = true);
    try {
      ref.read(mapInteractionProvider.notifier).setLoading(true);
      final routes = await RoutingService.fetchRoutes(
        origin: origin,
        destination: dest,
        waypoints: st.waypoints,
      );
      if (!mounted) return;
      final notifier = ref.read(mapInteractionProvider.notifier);
      notifier.setAllRoutes(routes.map((r) => r.points).toList());
      final idx = ref.read(mapInteractionProvider).selectedRouteIdx;
      final selIdx = idx.clamp(0, routes.length - 1);
      notifier.setRoutePolyline(routes[selIdx].points);
    } catch (_) {
      // 실패 시 무시 — 현재 경로 유지
    } finally {
      if (mounted) {
        setState(() => _isRecalculating = false);
        ref.read(mapInteractionProvider.notifier).setLoading(false);
      }
    }
  }

  // ── 아이콘 색상 헬퍼 ────────────────────────────────────────────────────────

  Color _iconColor(int idx, int total) {
    if (idx == 0) return AppColors.primary;
    if (idx == total - 1) return Colors.red;
    return Colors.grey;
  }

  // ── 장소명 표시 헬퍼 ────────────────────────────────────────────────────────

  String _stopLabel(int idx, int total) {
    final stops = ref.read(mapInteractionProvider).stops;
    if (stops.isEmpty || idx >= stops.length) return '위치 ${idx + 1}';
    final stop = stops[idx];
    if (idx == 0 && stop.isCurrentLocation) return '현재 위치';
    return stop.name ?? '위치 ${idx + 1}';
  }

  // ── 빌드 ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return _SheetBody(
          scrollController: scrollController,
          isRecalculating: _isRecalculating,
          iconColor: _iconColor,
          stopLabel: _stopLabel,
          onReorder: (oldIdx, newIdx) {
            ref
                .read(mapInteractionProvider.notifier)
                .reorderStop(oldIdx, newIdx);
            _recalculate();
          },
          onRemove: (waypointIdx) {
            ref
                .read(mapInteractionProvider.notifier)
                .removeWaypoint(waypointIdx);
            _recalculate();
          },
          onAddWaypoint: widget.onAddWaypoint,
        );
      },
    );
  }
}

// ── 시트 본문 (별도 위젯으로 분리해 ref.watch 최소화) ─────────────────────────

class _SheetBody extends ConsumerWidget {
  final ScrollController scrollController;
  final bool isRecalculating;
  final Color Function(int idx, int total) iconColor;
  final String Function(int idx, int total) stopLabel;
  final void Function(int oldIdx, int newIdx) onReorder;
  final void Function(int waypointIdx) onRemove;
  final VoidCallback? onAddWaypoint;

  const _SheetBody({
    required this.scrollController,
    required this.isRecalculating,
    required this.iconColor,
    required this.stopLabel,
    required this.onReorder,
    required this.onRemove,
    this.onAddWaypoint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(mapInteractionProvider).stops;
    final total = stops.length;

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Column(
        children: [
          // ── 핸들 바 ───────────────────────────────────────────────────────
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // ── 재계산 진행 표시기 ─────────────────────────────────────────────
          if (isRecalculating)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            )
          else
            const SizedBox(height: 2),

          // ── 헤더 ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '경유지 관리',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),

          // ── 리스트 ────────────────────────────────────────────────────────
          Expanded(
            child: IgnorePointer(
              ignoring: isRecalculating,
              child: total == 0
                  ? const Center(child: Text('경유지가 없습니다'))
                  : ReorderableListView(
                      scrollController: scrollController,
                      physics: const NeverScrollableScrollPhysics(),
                      // onReorderItem gives the gap-corrected final index.
                      // reorderStop expects the raw onReorder-style index
                      // (it does its own gap correction internally), so we
                      // un-correct here: add 1 back when moving downward.
                      onReorderItem: isRecalculating
                          ? (_, _) {}
                          : (oldIdx, newIdx) => onReorder(
                                oldIdx,
                                newIdx >= oldIdx ? newIdx + 1 : newIdx,
                              ),
                      children: [
                        for (int i = 0; i < total; i++)
                          ListTile(
                            key: ValueKey(i),
                            leading: Icon(
                              Icons.circle,
                              size: 14,
                              color: iconColor(i, total),
                            ),
                            title: Text(
                              stopLabel(i, total),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // 경유지(출발지/도착지 아님)만 삭제 버튼 표시.
                            // stops.length < 2이면 삭제 버튼 모두 비활성화.
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (i > 0 && i < total - 1)
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline),
                                    color: total < 2
                                        ? Colors.grey[300]
                                        : Colors.grey[600],
                                    onPressed: (total < 2 || isRecalculating)
                                        ? null
                                        // waypoints 기준 0-based idx = stops idx - 1
                                        : () => onRemove(i - 1),
                                  ),
                                // 드래그 핸들 (ReorderableListView가 자동 처리)
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Icon(
                                    Icons.drag_handle,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),

          // ── 경유지 추가 버튼 ───────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              top: 4,
            ),
            child: TextButton.icon(
              onPressed: onAddWaypoint,
              icon: const Icon(Icons.add),
              label: const Text('경유지 추가'),
            ),
          ),
        ],
      ),
    );
  }
}
