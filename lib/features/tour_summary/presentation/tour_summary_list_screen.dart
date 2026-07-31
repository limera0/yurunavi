import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/tour_log.dart';
import '../providers/tour_log_providers.dart';
import '../tour_log_format.dart';
import 'tour_summary_detail_screen.dart';

class TourSummaryListScreen extends ConsumerWidget {
  const TourSummaryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(tourLogListProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('투어 기록'),
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) =>
            Center(child: Text('투어 기록을 불러오지 못했습니다\n$err', textAlign: TextAlign.center)),
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(child: Text('아직 저장된 투어가 없어요'));
          }
          final groups = groupTourLogsByDay(logs);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final entry = groups[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(
                      DateFormat('yyyy년 M월 d일').format(entry.key),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ...entry.value.map((log) => _TourLogCard(tourLog: log)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _TourLogCard extends ConsumerWidget {
  final TourLog tourLog;
  const _TourLogCard({required this.tourLog});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.background,
        title: Text('투어 기록 삭제', style: AppTextStyles.titleSM),
        content: Text(
          '이 투어 기록을 삭제할까요?\n삭제하면 되돌릴 수 없습니다.',
          style: AppTextStyles.bodyMD,
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.brandMoss),
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(tourLogListProvider.notifier).delete(tourLog.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final fromTo = '${tourLog.startAddress ?? '${tourLog.startLat.toStringAsFixed(4)}, ${tourLog.startLng.toStringAsFixed(4)}'}'
        ' → '
        '${tourLog.endAddress ?? '${tourLog.endLat.toStringAsFixed(4)}, ${tourLog.endLng.toStringAsFixed(4)}'}';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TourSummaryDetailScreen(tourLog: tourLog)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    formatTourDistanceKm(tourLog.distanceM),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatTourDuration(tourLog.durationS),
                    style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('HH:mm').format(tourLog.startedAt),
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _confirmDelete(context, ref),
                    child: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('평균 ${formatTourSpeedKmh(tourLog.avgSpeedKmh)}',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 12),
                  Text('최고 ${formatTourSpeedKmh(tourLog.maxSpeedKmh)}',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                fromTo,
                style: TextStyle(fontSize: 13, color: cs.onSurface),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
