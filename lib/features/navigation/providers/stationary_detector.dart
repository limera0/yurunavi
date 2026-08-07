/// 정차 모드 판정 순수 상태머신 (S5).
///
/// [feed]에 매 속도 틱마다 `speedKmh`를 공급하면 정차 모드 여부([isStationary])가
/// 갱신된다. 판정 규칙(safety-first 원칙, memory `feedback_safety_priority` —
/// 안내류 기능은 넓게/보수적으로):
/// - **진입은 신중하게**: 속도가 [thresholdKmh] 미만으로 [sustainDuration] 이상
///   연속 지속돼야 `true`로 전환한다.
/// - **해제는 즉시**: 속도가 [thresholdKmh] 이상으로 단 한 번이라도 회복되면
///   지연 없이 `false`로 되돌린다.
///
/// 실제 `DateTime.now()` 대신 주입 가능한 [clock]을 받아 유닛/위젯 테스트에서
/// 가짜 시간으로 지속시간 경과를 시뮬레이션할 수 있게 한다.
class StationaryDetector {
  StationaryDetector({
    this.thresholdKmh = 5.0,
    this.sustainDuration = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final double thresholdKmh;
  final Duration sustainDuration;
  final DateTime Function() _clock;

  DateTime? _belowSince;
  bool _isStationary = false;

  bool get isStationary => _isStationary;

  /// 속도(km/h)를 공급하고 갱신된 [isStationary]를 반환한다.
  bool feed(double speedKmh) {
    if (speedKmh >= thresholdKmh) {
      // 해제는 즉시 — 지연 없이 리셋(진입 대기 중이었어도 카운트 무효화).
      _belowSince = null;
      _isStationary = false;
      return _isStationary;
    }
    final now = _clock();
    _belowSince ??= now;
    if (!_isStationary && now.difference(_belowSince!) >= sustainDuration) {
      _isStationary = true;
    }
    return _isStationary;
  }
}
