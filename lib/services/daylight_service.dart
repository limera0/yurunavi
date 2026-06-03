import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;
import 'package:sunrise_sunset_calc/sunrise_sunset_calc.dart';

/// 낮/밤 사이클 상태 — DaylightBar가 표시에 사용한다.
class DaylightCycleState {
  /// true=낮(BMNT~EENT), false=밤(EENT~익일BMNT)
  final bool isDay;
  /// 현재 구간 내 진행도 0.0~1.0
  final double progress;
  /// 게이지 상단 시각 (낮=BMNT, 밤=EENT)
  final DateTime topTime;
  /// 게이지 하단 시각 (낮=EENT, 밤=익일BMNT)
  final DateTime bottomTime;

  const DaylightCycleState({
    required this.isDay,
    required this.progress,
    required this.topTime,
    required this.bottomTime,
  });
}

/// BMNT/EENT 계산 서비스.
///
/// 우선순위:
/// 1. api.sunrise-sunset.org 의 nautical_twilight (UTC→KST) — (위치1dp+날짜) 기준 하루 1회 캐시
/// 2. sunrise_sunset_calc 패키지 로컬 계산 (오프라인 fallback)
class DaylightService {
  // ── API 결과 인메모리 캐시 (앱 생명주기 동안 유지) ───────────────────────────
  static final Map<String, ({DateTime bmnt, DateTime eent})> _apiCache = {};

  static String _cacheKey(double lat, double lng, DateTime date) {
    final d = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '${lat.toStringAsFixed(1)},${lng.toStringAsFixed(1)},$d';
  }

  /// sunrise-sunset.org API에서 nautical twilight 를 가져온다.
  /// 성공 시 캐시 저장 후 반환. 실패 시 null.
  static Future<({DateTime bmnt, DateTime eent})?> fetchRemote(
    double lat,
    double lng,
    DateTime date,
  ) async {
    final key = _cacheKey(lat, lng, date);
    if (_apiCache.containsKey(key)) return _apiCache[key];

    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      'https://api.sunrise-sunset.org/json?lat=${lat.toStringAsFixed(4)}&lng=${lng.toStringAsFixed(4)}&date=$dateStr&formatted=0',
    );

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final results = body['results'] as Map<String, dynamic>;

      // API 반환 형식: ISO 8601 UTC (e.g. "2024-06-03T20:17:00+00:00")
      // nautical_twilight_begin = BMNT, nautical_twilight_end = EENT
      final bmntUtc = DateTime.parse(results['nautical_twilight_begin'] as String);
      final eentUtc = DateTime.parse(results['nautical_twilight_end'] as String);

      // UTC → KST (+9h): add 9 h; do NOT call toLocal() — bmntUtc is tagged UTC
      // and toLocal() would apply the device tz offset again (double-convert on KST devices)
      const kst = Duration(hours: 9);
      final r = (bmnt: bmntUtc.add(kst), eent: eentUtc.add(kst));
      _apiCache[key] = r;
      dev.log('DaylightService API fetch OK: BMNT=${r.bmnt}, EENT=${r.eent}',
          name: 'DaylightService');
      return r;
    } catch (e) {
      dev.log('DaylightService API 실패: $e — 로컬 계산 사용', name: 'DaylightService');
      return null;
    }
  }

  /// BMNT/EENT를 동기 반환한다.
  /// API 캐시가 있으면 사용, 없으면 로컬 sunrise_sunset_calc 기반 추정.
  static ({DateTime bmnt, DateTime eent}) calculate({
    required double lat,
    required double lng,
    required DateTime date,
  }) {
    final key = _cacheKey(lat, lng, date);
    if (_apiCache.containsKey(key)) return _apiCache[key]!;
    return _localCalc(lat, lng, date);
  }

  static ({DateTime bmnt, DateTime eent}) _localCalc(
      double lat, double lng, DateTime date) {
    const civilOffset = Duration(minutes: 30);
    try {
      final utcOffset = date.timeZoneOffset;
      final result = getSunriseSunset(lat, lng, utcOffset, date);
      final sunrise = result.sunrise;
      final sunset = result.sunset;
      if (!_isFiniteDateTime(sunrise) || !_isFiniteDateTime(sunset)) {
        return _fallback(date);
      }
      return (
        bmnt: sunrise.subtract(civilOffset),
        eent: sunset.add(civilOffset),
      );
    } catch (_) {
      return _fallback(date);
    }
  }

  static ({DateTime bmnt, DateTime eent}) _fallback(DateTime date) {
    final base = DateTime(date.year, date.month, date.day);
    return (
      bmnt: base.add(const Duration(hours: 6)),
      eent: base.add(const Duration(hours: 20)),
    );
  }

  static bool _isFiniteDateTime(DateTime d) {
    try {
      return d.year > 1 && d.year < 9999;
    } catch (_) {
      return false;
    }
  }

  /// 낮/밤 사이클 상태 계산.
  ///
  /// 낮 (BMNT~EENT): progress = (now-BMNT)/(EENT-BMNT), topTime=BMNT, bottomTime=EENT
  /// 밤 (EENT~익일BMNT): progress = (now-EENT)/(nextBMNT-EENT), topTime=EENT, bottomTime=nextBMNT
  static DaylightCycleState cycleState({
    required double lat,
    required double lng,
    required DateTime now,
  }) {
    final today = calculate(lat: lat, lng: lng, date: now);
    final bool isDay = now.isAfter(today.bmnt) && now.isBefore(today.eent);

    if (isDay) {
      final total = today.eent.difference(today.bmnt).inSeconds.toDouble();
      final elapsed = now.difference(today.bmnt).inSeconds.toDouble();
      final progress = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.5;
      return DaylightCycleState(
        isDay: true,
        progress: progress,
        topTime: today.bmnt,
        bottomTime: today.eent,
      );
    } else {
      // 밤: EENT → 익일BMNT
      final eent = now.isBefore(today.bmnt) ? today.eent.subtract(const Duration(hours: 24)) : today.eent;
      // 익일 BMNT ≈ 오늘 BMNT + 24h (±30분 오차 허용)
      final nextBmnt = today.bmnt.add(const Duration(hours: 24));
      final total = nextBmnt.difference(eent).inSeconds.toDouble();
      final elapsed = now.difference(eent).inSeconds.toDouble();
      final progress = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.5;
      return DaylightCycleState(
        isDay: false,
        progress: progress,
        topTime: eent,
        bottomTime: nextBmnt,
      );
    }
  }

  static bool isDaytime({
    required double lat,
    required double lng,
    required DateTime now,
  }) {
    try {
      final r = calculate(lat: lat, lng: lng, date: now);
      return now.isAfter(r.bmnt) && now.isBefore(r.eent);
    } catch (_) {
      return true;
    }
  }

  static double daylightProgress({
    required double lat,
    required double lng,
    required DateTime now,
  }) {
    try {
      return cycleState(lat: lat, lng: lng, now: now).progress;
    } catch (_) {
      return 0.5;
    }
  }
}
