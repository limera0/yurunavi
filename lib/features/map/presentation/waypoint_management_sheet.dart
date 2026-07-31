import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_ctrl_btn.dart';
import '../../../services/routing_service.dart';
import '../providers/map_providers.dart';

/// 경유지 관리 바텀 시트.
///
/// [DraggableScrollableSheet]로 감싸 초기 60% / 최대 90% / 최소 40% 로 표시.
/// stops 배열을 [ReorderableListView]로 나열하고, 순서 변경 / 경유지 삭제 후
/// [RoutingService.fetchRoutes]로 즉시 경로를 재계산한다.
/// 출발지·도착지 행의 `+` 버튼은 시트를 닫고 지도에서 위치를 고르게 한 뒤,
/// 선택이 확정되면(4번 POI 카드) 이 시트를 다시 열어 갱신된 목록을 보여준다.
class WaypointManagementSheet extends ConsumerStatefulWidget {
  const WaypointManagementSheet({super.key});

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
          onInsertAtStart: () {
            ref
                .read(mapInteractionProvider.notifier)
                .setPendingWaypointInsert(WaypointInsertPosition.start);
            Navigator.of(context).pop();
          },
          onInsertAtEnd: () {
            ref
                .read(mapInteractionProvider.notifier)
                .setPendingWaypointInsert(WaypointInsertPosition.end);
            Navigator.of(context).pop();
          },
        );
      },
    );
  }
}

// ── 시트 본문 (별도 위젯으로 분리해 ref.watch 최소화) ─────────────────────────

class _SheetBody extends ConsumerWidget {
  final ScrollController scrollController;
  final bool isRecalculating;
  final String Function(int idx, int total) stopLabel;
  final void Function(int oldIdx, int newIdx) onReorder;
  final void Function(int waypointIdx) onRemove;
  final VoidCallback onInsertAtStart;
  final VoidCallback onInsertAtEnd;

  const _SheetBody({
    required this.scrollController,
    required this.isRecalculating,
    required this.stopLabel,
    required this.onReorder,
    required this.onRemove,
    required this.onInsertAtStart,
    required this.onInsertAtEnd,
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
                            title: Text(
                              stopLabel(i, total),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: (i == 0 || i == total - 1)
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // 경유지(출발지/도착지 아님)만 삭제 버튼 표시.
                            // stops.length < 2이면 삭제 버튼 모두 비활성화.
                            // 출발지/도착지 행에는 대신 지도기반 추가 `+` 버튼.
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (i > 0 && i < total - 1)
                                  _RemoveBadge(
                                    enabled: !(total < 2 || isRecalculating),
                                    // waypoints 기준 0-based idx = stops idx - 1
                                    onPressed: () => onRemove(i - 1),
                                  ),
                                if (i == 0)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: MapCtrlBtn(
                                      icon: Icons.add,
                                      onTap: onInsertAtStart,
                                      size: 32,
                                    ),
                                  ),
                                if (i == total - 1 && total > 1)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: MapCtrlBtn(
                                      icon: Icons.add,
                                      onTap: onInsertAtEnd,
                                      size: 32,
                                    ),
                                  ),
                                // 드래그 핸들 (ReorderableListView가 자동 처리)
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Icon(
                                    Icons.unfold_more,
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
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

/// 중간 경유지 삭제 버튼 — 원형 배지 스타일 (⊖).
class _RemoveBadge extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _RemoveBadge({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: enabled
            ? Colors.red.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.08),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: const Icon(Icons.remove_circle_outline),
        color: enabled ? Colors.red[400] : Colors.grey[300],
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}
