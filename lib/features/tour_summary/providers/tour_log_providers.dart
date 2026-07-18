import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/tour_log.dart';
import '../../../services/tour_log_service.dart';

final tourLogServiceProvider = Provider((_) => TourLogService());

final tourLogListProvider =
    AsyncNotifierProvider<TourLogListNotifier, List<TourLog>>(
        TourLogListNotifier.new);

class TourLogListNotifier extends AsyncNotifier<List<TourLog>> {
  @override
  Future<List<TourLog>> build() => ref.read(tourLogServiceProvider).loadAll();

  Future<void> delete(String id) async {
    await ref.read(tourLogServiceProvider).delete(id);
    ref.invalidateSelf();
  }

  /// 투어 메모를 수정한다. 메모 입력 UI는 이후 서브태스크에서 추가될 예정이라
  /// 아직 이 메서드를 호출하는 곳은 없지만, 이 notifier에 자연스럽게 속하는
  /// 로직이라 미리 구현해 둔다.
  Future<void> updateMemo(String id, String? memo) async {
    final current = state.value ?? await future;
    final idx = current.indexWhere((log) => log.id == id);
    if (idx == -1) return;
    final updated = current[idx].copyWith(memo: memo);
    await ref.read(tourLogServiceProvider).update(updated);
    ref.invalidateSelf();
  }
}
