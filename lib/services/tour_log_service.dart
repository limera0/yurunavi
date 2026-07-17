import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tour_log.dart';

/// 완료된 주행 이력(투어 요약) 로컬 저장소 (SharedPreferences 기반).
///
/// GPS 트랙 원본은 여기서 다루지 않는다 — [TourLog.trackFilePath]가 가리키는
/// 별도의 .jsonl 파일에 저장된다(다른 서브태스크에서 작성됨).
class TourLogService {
  static const _key = 'tour_logs_v1';

  Future<List<TourLog>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final logs = <TourLog>[];
    for (final s in raw) {
      try {
        logs.add(TourLog.fromJsonString(s));
      } catch (_) {
        // 손상된 항목 하나가 전체 목록을 깨뜨리지 않도록 건너뛴다.
      }
    }
    logs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return logs;
  }

  Future<void> add(TourLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    // 주행 이력은 사용자가 명시적으로 삭제하기 전까지 무제한 보존한다
    // (즐겨찾기/최근 경로와 달리 개수를 잘라내지 않는다).
    raw.add(log.toJsonString());
    await prefs.setStringList(_key, raw);
  }

  Future<void> update(TourLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final updated = <String>[];
    for (final s in raw) {
      try {
        final existing = TourLog.fromJsonString(s);
        updated.add(existing.id == log.id ? log.toJsonString() : s);
      } catch (_) {
        updated.add(s);
      }
    }
    await prefs.setStringList(_key, updated);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];

    String? trackFilePath;
    final kept = <String>[];
    for (final s in raw) {
      try {
        final existing = TourLog.fromJsonString(s);
        if (existing.id == id) {
          trackFilePath = existing.trackFilePath;
          continue;
        }
        kept.add(s);
      } catch (_) {
        kept.add(s);
      }
    }

    if (trackFilePath != null) {
      try {
        await File(trackFilePath).delete();
      } catch (_) {
        // 파일이 이미 없거나 삭제 실패해도 인덱스 삭제는 계속 진행한다.
      }
    }

    await prefs.setStringList(_key, kept);
  }
}
