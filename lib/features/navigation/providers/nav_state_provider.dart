import 'dart:async';
import 'dart:math' show sin, cos, sqrt, asin;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider는 Riverpod 3에서 legacy.dart로 분리됐다 — isStationaryProvider
// (S5)가 단순 명령형 bool 플래그로 이 API를 쓴다.
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../map/providers/map_providers.dart'
    show locationStreamProvider, stationaryModeProvider;
import 'stationary_detector.dart';

@immutable
class NavigationState {
  final LatLng pos;
  final double speedKmh;
  final bool moving;
  final double? headingDeg;
  final bool firstFix;
  final DateTime fixAt;
  // S7: 마지막 fix로부터 _kStaleMs(8초) 넘게 지나 "GPS 상실"로 판정된
  // 상태(_tickSpeed()에서 계산). RouteProgressNotifier의 터널 dead
  // reckoning 진입 판단을 포함해, "GPS 상실"의 단일 기준선을 앱 전체가
  // 이 필드 하나로 공유한다 — 다른 provider가 독자적으로 staleness를
  // 다시 계산하지 않는다.
  final bool stale;

  const NavigationState({
    required this.pos,
    required this.speedKmh,
    required this.moving,
    required this.headingDeg,
    required this.firstFix,
    required this.fixAt,
    required this.stale,
  });
  // ⚠️ copyWith 금지: heading null↔값 오가므로 copyWith(?? this)로는 null 복귀 불가.
  // 매 fix/tick마다 NavigationState(...) 전체 필드 명시 생성.
}

final navStateProvider =
    NotifierProvider<NavStateNotifier, NavigationState?>(NavStateNotifier.new);

/// 정차 모드(속도 5km/h 미만 10초 이상 지속, [StationaryDetector] 참고) 판정
/// 결과. `NavStateNotifier`가 매 속도 틱마다 명령형으로 갱신한다(watch
/// 순환이 아니라 단순 플래그) — nav_screen.dart의 재탐색/POI페치/카메라추종
/// 게이트가 이 값을 읽는다. GPS 스트림 설정 자체를 낮추는
/// `stationaryModeProvider`(map_providers.dart)와는 별도 플래그다 — 모듈
/// 독립성 유지 목적(같은 순간에 같은 값으로 함께 갱신된다).
final isStationaryProvider = StateProvider<bool>((_) => false);

class NavStateNotifier extends Notifier<NavigationState?> {
  static const _kStaleMs      = 8000;
  static const _kFastStopMs   = 1500;
  static const _kJumpGuardM   = 150.0;
  static const _kMaxSpeedMps  = 75.0;
  static const _kDtGuardMs    = 6500;
  static const _kSpeedEpsKmh  = 0.05;
  static const _kBufferTtlSec = 12;

  LatLng? _pos;
  double _speedKmh = 0;
  bool _moving = false;
  double? _headingDeg;
  bool _firstFixReceived = false;
  DateTime? _fixAt;
  bool _stale = false;

  final _posBuffer = <({double lat, double lon, DateTime t, double acc})>[];
  DateTime? _lastSpeedAt;

  double? _vPrev, _vCur;
  DateTime? _vPrevAt, _vCurAt;
  LatLng? _vPrevPos, _vCurPos;

  Timer? _ticker;

  // S5: 정차 모드 상태머신 — _moving(순간 판정, 위)과는 별개의 지속시간
  // 판정. _tickSpeed()가 200ms마다 최신 _speedKmh를 공급한다.
  final _stationaryDetector = StationaryDetector();

  @override
  NavigationState? build() {
    final sub = ref.listen<AsyncValue<Position>>(locationStreamProvider, (_, next) {
      next.whenData(_onFix);
    });
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200), (_) => _tickSpeed());
    ref.onDispose(() {
      _ticker?.cancel();
      sub.close();
    });
    _seed();
    return null;
  }

  Future<void> _seed() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.whileInUse &&
          perm != LocationPermission.always) {
        return;
      }
if (state != null) return; 
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || state != null) return;
      _pos = LatLng(last.latitude, last.longitude);
      _fixAt = DateTime.now();
      _stale = false;
      state = NavigationState(
        pos: _pos!,
        speedKmh: 0,
        moving: false,
        headingDeg: null,
        firstFix: true,
        fixAt: _fixAt!,
        stale: false,
      );
    } catch (_) {
      return;
    }
  }

  void _onFix(Position pos) {
    final loc = LatLng(pos.latitude, pos.longitude);
    final now = DateTime.now();
    // S7: 실측 fix가 도착했으므로 이전 tick의 staleness 판정을 즉시 해제.
    _stale = false;

    _posBuffer.add((lat: pos.latitude, lon: pos.longitude, t: now, acc: pos.accuracy));
    _posBuffer.removeWhere((e) => now.difference(e.t).inSeconds > _kBufferTtlSec);

    final intervalMs = _speedKmh <= 10.0 ? 500 : 1000;
    final elapsedMs = _lastSpeedAt == null
        ? intervalMs
        : now.difference(_lastSpeedAt!).inMilliseconds;

    if (elapsedMs < intervalMs) {
      _pos = loc;
      if (!_firstFixReceived) _firstFixReceived = true;
      _fixAt = now;
      state = NavigationState(
        pos: loc,
        speedKmh: _speedKmh,
        moving: _moving,
        headingDeg: _headingDeg,
        firstFix: _firstFixReceived,
        fixAt: now,
        stale: false,
      );
      return;
    }
    _lastSpeedAt = now;

    final double d = (pos.speed.isNaN || pos.speed < 0) ? 0.0 : pos.speed;
    final (:parked, :bufRadius, :parkThresh) = _calcParkState();

    if (parked) {
      _moving = false;
    } else if (d >= 2.0) {
      _moving = true;
    } else if (d < 1.5) {
      _moving = false;
    }

    _vPrev = _vCur; _vPrevAt = _vCurAt; _vPrevPos = _vCurPos;
    _vCur = d; _vCurAt = now; _vCurPos = loc;

    _speedKmh = _moving ? d * 3.6 : 0.0;
    _pos = loc;
    _headingDeg = pos.heading >= 0 ? pos.heading : null;
    if (!_firstFixReceived) _firstFixReceived = true;
    _fixAt = now;

    debugPrint('SPD d=${d.toStringAsFixed(2)} r=${bufRadius.toStringAsFixed(1)} '
               'thr=${parkThresh.toStringAsFixed(1)} parked=$parked mov=$_moving '
               '=> ${_speedKmh.toStringAsFixed(1)}km/h');

    state = NavigationState(
      pos: loc,
      speedKmh: _speedKmh,
      moving: _moving,
      headingDeg: _headingDeg,
      firstFix: _firstFixReceived,
      fixAt: now,
      stale: false,
    );
  }

  void _tickSpeed() {
    // S5: 첫 fix를 받기 전엔 _speedKmh가 "아직 모름"이지 "정지"가 아니므로
    // 피드하지 않는다 — 정차 모드를 앞당겨 GPS 정확도를 낮추면 최초 fix
    // 획득이 늦어질 위험이 있다.
    if (_firstFixReceived) _updateStationary(_speedKmh);

    final curAt = _vCurAt;
    final vCur = _vCur;
    if (curAt == null || vCur == null) return;

    final sinceFix = DateTime.now().difference(curAt).inMilliseconds;
    // S7: staleness는 매 tick 재계산 — RouteProgressNotifier가 이 필드 하나로
    // 터널 dead reckoning 진입을 판단하므로, 값이 안 바뀌어도(이미 정지 상태)
    // false→true로 막 전환되는 tick은 반드시 emit해야 한다(아래 wasStale 비교).
    final wasStale = _stale;
    _stale = sinceFix > _kStaleMs;

    if (_stale) {
      if (_speedKmh != 0.0 || _moving || _stale != wasStale) {
        _speedKmh = 0.0;
        _moving = false;
        _emitState();
      }
      return;
    }
    if (sinceFix > _kFastStopMs && _calcParkState().parked) {
      if (_speedKmh != 0.0) {
        _speedKmh = 0.0;
        _emitState();
      }
      return;
    }
    if (!_moving) {
      if (_speedKmh != 0.0) {
        _speedKmh = 0.0;
        _emitState();
      }
      return;
    }

    final measured = (vCur * 3.6).clamp(0.0, 270.0);
    final vPrev = _vPrev;
    final prevAt = _vPrevAt;
    if (vPrev == null || prevAt == null) {
      if ((_speedKmh - measured).abs() > _kSpeedEpsKmh) {
        _speedKmh = measured;
        _emitState();
      }
      return;
    }

    final dtFix = curAt.difference(prevAt).inMilliseconds;
    final jumpM = (_vPrevPos != null && _vCurPos != null)
        ? _distanceM(_vPrevPos!, _vCurPos!) : 0.0;
    final avgMs = dtFix > 0 ? jumpM / (dtFix / 1000.0) : double.maxFinite;
    if (dtFix <= 0 || dtFix > _kDtGuardMs || jumpM > _kJumpGuardM || avgMs > _kMaxSpeedMps) {
      if ((_speedKmh - measured).abs() > _kSpeedEpsKmh) {
        _speedKmh = measured;
        _emitState();
      }
      return;
    }

    final slope = (vCur - vPrev) / dtFix;
    final v = (vCur + slope * sinceFix).clamp(0.0, 75.0);
    final kmh = v * 3.6;
    if ((_speedKmh - kmh).abs() > _kSpeedEpsKmh) {
      _speedKmh = kmh;
      _emitState();
    }
  }

  /// [StationaryDetector]에 이번 틱의 속도를 공급하고, 판정 결과가 바뀌면
  /// `isStationaryProvider`/`stationaryModeProvider` 두 플래그를 함께
  /// 명령형으로 갱신한다(둘 다 아무것도 watch하지 않는 단순 플래그라 순환
  /// 없음 — HANDOFF_0807_S5 §5 참고).
  void _updateStationary(double speedKmh) {
    final was = _stationaryDetector.isStationary;
    final now = _stationaryDetector.feed(speedKmh);
    if (now == was) return;
    ref.read(isStationaryProvider.notifier).state = now;
    ref.read(stationaryModeProvider.notifier).state = now;
  }

  void _emitState() {
    final p = _pos;
    if (p == null) return;
    state = NavigationState(
      pos: p,
      speedKmh: _speedKmh,
      moving: _moving,
      headingDeg: _headingDeg,
      firstFix: _firstFixReceived,
      fixAt: _fixAt ?? DateTime.now(),
      stale: _stale,
    );
  }

  ({bool parked, double bufRadius, double parkThresh}) _calcParkState() {
    if (_posBuffer.length < 3) {
      return (parked: false, bufRadius: 0.0, parkThresh: 6.0);
    }
    final cLat = _posBuffer.map((e) => e.lat).reduce((a, b) => a + b) / _posBuffer.length;
    final cLon = _posBuffer.map((e) => e.lon).reduce((a, b) => a + b) / _posBuffer.length;
    final bufRadius = _posBuffer
        .map((e) => _distanceM(LatLng(cLat, cLon), LatLng(e.lat, e.lon)))
        .reduce((a, b) => a > b ? a : b);
    final accs = _posBuffer.map((e) => e.acc).toList()..sort();
    final medAcc = accs[accs.length ~/ 2];
    final parkThresh = (6.0 > 1.2 * medAcc) ? 6.0 : 1.2 * medAcc;
    return (parked: bufRadius < parkThresh, bufRadius: bufRadius, parkThresh: parkThresh);
  }

  double _distanceM(LatLng a, LatLng b) {
    const r = 6371000.0;
    const deg2rad = 0.017453292519943295;
    final lat1 = a.latitude * deg2rad;
    final lat2 = b.latitude * deg2rad;
    final dLat = (b.latitude - a.latitude) * deg2rad;
    final dLon = (b.longitude - a.longitude) * deg2rad;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(sqrt(h));
  }
}
