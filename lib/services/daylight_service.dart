import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sunrise_sunset_calc/sunrise_sunset_calc.dart';

/// 낮/밤 사이클 상태 — DaylightBar가 표시에 사용한다.
class DaylightCycleState {
  /// true=낮(일출~일몰), false=밤(일몰~익일일출)
  final bool isDay;
  /// 현재 구간 내 진행도 0.0~1.0
  final double progress;
  /// 게이지 상단 시각 (낮=일출, 밤=일몰)
  final DateTime topTime;
  /// 게이지 하단 시각 (낮=일몰, 밤=익일일출)
  final DateTime bottomTime;

  const DaylightCycleState({
    required this.isDay,
    required this.progress,
    required this.topTime,
    required this.bottomTime,
  });
}

/// 일출/일몰 계산 서비스.
///
/// 우선순위:
/// 1. api.sunrise-sunset.org 의 sunrise/sunset (UTC→KST) — (위치1dp+날짜) 기준 하루 1회 캐시
/// 2. sunrise_sunset_calc 패키지 로컬 계산 (오프라인 fallback)
/// 내부 record 필드명은 bmnt/eent를 유지하지만 실제로는 일출/일몰 시각을 담는다.
class DaylightService {
  // ── API 결과 인메모리 캐시 (앱 생명주기 동안 유지) ───────────────────────────
  static final Map<String, ({DateTime bmnt, DateTime eent})> _apiCache = {};

  static String _cacheKey(double lat, double lng, DateTime date) {
    final d = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '${lat.toStringAsFixed(1)},${lng.toStringAsFixed(1)},$d';
  }

  /// sunrise-sunset.org API에서 sunrise/sunset 를 가져온다.
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

      // API 반환 형식: ISO 8601 UTC (e.g. "2026-06-05T20:10:31+00:00")
      // sunrise/sunset 키 사용 (0단계 curl로 존재 확인됨)
      final sRaw = results['sunrise'];
      final eRaw = results['sunset'];
      if (sRaw == null || eRaw == null) {
        debugPrint('[daylight] api missing sunrise/sunset keys, fallback to local');
        return null;
      }
      final bmntUtc = DateTime.parse(sRaw as String);
      final eentUtc = DateTime.parse(eRaw as String);

      // toLocal()로 기기 로컬시각(KST)으로 변환 → epoch 비교 정상화
      final bmnt = bmntUtc.toLocal();
      final eent = eentUtc.toLocal();
      final r = (bmnt: bmnt, eent: eent);
      _apiCache[key] = r;
      debugPrint('[daylight] path=api bmnt=$bmnt eent=$eent isUtc=${bmnt.isUtc}');
      dev.log('DaylightService API fetch OK: BMNT=$bmnt, EENT=$eent',
          name: 'DaylightService');
      return r;
    } catch (e) {
      dev.log('DaylightService API 실패: $e — 로컬 계산 사용', name: 'DaylightService');
      debugPrint('YNAV_DAYLIGHT_ERR error=$e');
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
    try {
      final utcOffset = date.timeZoneOffset;
      final result = getSunriseSunset(lat, lng, utcOffset, date);
      final sunrise = result.sunrise;
      final sunset = result.sunset;
      if (!_isFiniteDateTime(sunrise) || !_isFiniteDateTime(sunset)) {
        return _fallback(date);
      }
      // 패키지는 UTC-tagged에 LOCAL clock값을 저장(isUtc=true, hour=KST시각).
      // DateTime(...)으로 local-tagged 재포장 → epoch 비교 정상화.
      final bmnt = DateTime(date.year, date.month, date.day,
          sunrise.hour, sunrise.minute, sunrise.second);
      final eent = DateTime(date.year, date.month, date.day,
          sunset.hour, sunset.minute, sunset.second);
      debugPrint('[daylight] path=local bmnt=$bmnt eent=$eent isUtc=${bmnt.isUtc}');
      return (bmnt: bmnt, eent: eent);
    } catch (_) {
      return _fallback(date);
    }
  }

  static ({DateTime bmnt, DateTime eent}) _fallback(DateTime date) {
    // 일출/일몰 근사 (API·로컬 계산 모두 실패 시만 사용)
    final base = DateTime(date.year, date.month, date.day);
    return (
      bmnt: base.add(const Duration(hours: 5, minutes: 30)),
      eent: base.add(const Duration(hours: 19, minutes: 30)),
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
  /// 낮 (일출~일몰): progress = (now-일출)/(일몰-일출), topTime=일출, bottomTime=일몰
  /// 밤 (일몰~익일일출): progress = (now-일몰)/(next일출-일몰), topTime=일몰, bottomTime=next일출
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
      // 밤: EENT → 익일BMNT. ±24h 근사 대신 실제 전일 일몰/익일 일출을 사용해
      // 자정 전후 연속성과 일출 직전 구간을 정확히 계산한다.
      final DateTime eent;
      final DateTime nextBmnt;
      if (now.isBefore(today.bmnt)) {
        // 자정~오늘 일출 전: 어제 일몰 ~ 오늘 일출
        final yesterday = calculate(
          lat: lat,
          lng: lng,
          date: now.subtract(const Duration(days: 1)),
        );
        eent = yesterday.eent;
        nextBmnt = today.bmnt;
      } else {
        // 오늘 일몰 이후: 오늘 일몰 ~ 내일 일출
        final tomorrow = calculate(
          lat: lat,
          lng: lng,
          date: now.add(const Duration(days: 1)),
        );
        eent = today.eent;
        nextBmnt = tomorrow.bmnt;
      }
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
