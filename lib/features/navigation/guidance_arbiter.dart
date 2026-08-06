import 'voice_engine.dart';

class GuidanceArbiter {
  static const double _minGapSec = 4.0;

  DateTime? _lastSpoken;

  /// 4개 엔진 출력을 우선순위에 따라 중재한다.
  /// 우선순위: rearCamera > voice(회전) > structure(구조물) > curve(급커브)
  /// rearCamera는 간격 제한 없이 항상 발화. 나머지는 마지막 발화로부터
  /// [_minGapSec]초가 지나야 발화된다. 간격 내 도달한 낮은 순위 항목은 폐기
  /// (큐잉 없음). 같은 틱에서 여러 그룹이 발화를 원할 때도 1개만 통과한다.
  List<SpeakIntent> arbitrate({
    required List<SpeakIntent> rearCamera,
    required List<SpeakIntent> voice,
    required List<SpeakIntent> structure,
    required List<SpeakIntent> curve,
  }) {
    final out = <SpeakIntent>[];
    final now = DateTime.now();

    for (final intent in rearCamera) {
      out.add(intent);
      _lastSpoken = now;
    }

    for (final group in [voice, structure, curve]) {
      for (final intent in group) {
        final elapsed = _lastSpoken == null
            ? double.infinity
            : now.difference(_lastSpoken!).inMilliseconds / 1000.0;
        if (elapsed >= _minGapSec) {
          out.add(intent);
          _lastSpoken = now;
        }
      }
    }

    return out;
  }

  void reset() {
    _lastSpoken = null;
  }
}
