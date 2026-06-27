import 'dart:async';
import 'dart:math' show sin, cos, sqrt, asin;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../map/providers/map_providers.dart' show locationStreamProvider;

@immutable
class NavigationState {
  final LatLng pos;
  final double speedKmh;
  final bool moving;
  final double? headingDeg;
  final bool firstFix;
  final DateTime fixAt;

  const NavigationState({
    required this.pos,
    required this.speedKmh,
    required this.moving,
    required this.headingDeg,
    required this.firstFix,
    required this.fixAt,
  });
  // ⚠️ copyWith 금지: heading null↔값 오가므로 copyWith(?? this)로는 null 복귀 불가.
  // 매 fix/tick마다 NavigationState(...) 전체 필드 명시 생성.
}

final navStateProvider =
    NotifierProvider<NavStateNotifier, NavigationState?>(NavStateNotifier.new);

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

  final _posBuffer = <({double lat, double lon, DateTime t, double acc})>[];
  DateTime? _lastSpeedAt;

  double? _vPrev, _vCur;
  DateTime? _vPrevAt, _vCurAt;
  LatLng? _vPrevPos, _vCurPos;

  Timer? _ticker;

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
    final last = await Geolocator.getLastKnownPosition();
    if (last == null || state != null) return;
    _pos = LatLng(last.latitude, last.longitude);
    _fixAt = DateTime.now();
    state = NavigationState(
      pos: _pos!,
      speedKmh: 0,
      moving: false,
      headingDeg: null,
      firstFix: false,
      fixAt: _fixAt!,
    );
  }

  void _onFix(Position pos) {
    final loc = LatLng(pos.latitude, pos.longitude);
    final now = DateTime.now();

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
    );
  }

  void _tickSpeed() {
    final curAt = _vCurAt;
    final vCur = _vCur;
    if (curAt == null || vCur == null) return;

    final sinceFix = DateTime.now().difference(curAt).inMilliseconds;

    if (sinceFix > _kStaleMs) {
      if (_speedKmh != 0.0 || _moving) {
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
