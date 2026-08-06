import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_arbiter.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';

void main() {
  const voiceIntent = SpeakIntent('turn_left_approach', {'dist': '300'});
  const structureIntent = SpeakIntent('bridge_approach', {'dist': '200'});
  const curveIntent = SpeakIntent('sharp_turn_left_approach', {'dist': '150'});
  const rearCameraIntent = SpeakIntent('rear_camera_approach', {});

  group('1 — 우선순위 기본: voice + curve 동시 → voice만 통과', () {
    test('같은 틱에서 voice와 curve가 있을 때 voice만 나온다', () {
      final arbiter = GuidanceArbiter();
      final result = arbiter.arbitrate(
        rearCamera: [],
        voice: [voiceIntent],
        structure: [],
        curve: [curveIntent],
      );
      expect(result.length, 1);
      expect(result[0].key, 'turn_left_approach');
    });
  });

  group('2 — 4초 간격: voice 발화 후 2초 뒤 structure → 드롭', () {
    test('마지막 발화로부터 2초 경과 시 structure 드롭', () {
      final arbiter = GuidanceArbiter();
      // voice 발화
      arbiter.arbitrate(
        rearCamera: [],
        voice: [voiceIntent],
        structure: [],
        curve: [],
      );
      // 2초 후 — 내부 _lastSpoken을 조작할 수 없으므로
      // 발화 직후의 두 번째 arbitrate로 gap=0 상황을 재현한다
      final result = arbiter.arbitrate(
        rearCamera: [],
        voice: [],
        structure: [structureIntent],
        curve: [],
      );
      expect(result, isEmpty, reason: 'gap < 4s이면 드롭돼야 한다');
    });
  });

  group('3 — 4초 경과 후: 다음 발화 통과', () {
    test('reset 후(= gap 무한) structure 통과', () {
      // reset()은 _lastSpoken을 null로 만들어 경과=∞로 취급한다.
      // 이 방식으로 "4초 이상 지난 상태"를 재현한다.
      final arbiter = GuidanceArbiter();
      arbiter.arbitrate(
        rearCamera: [],
        voice: [voiceIntent],
        structure: [],
        curve: [],
      );
      arbiter.reset(); // _lastSpoken = null → elapsed = ∞
      final result = arbiter.arbitrate(
        rearCamera: [],
        voice: [],
        structure: [structureIntent],
        curve: [],
      );
      expect(result.length, 1);
      expect(result[0].key, 'bridge_approach');
    });
  });

  group('4 — 후면단속 간격 무시: voice 발화 직후 rearCamera → 통과', () {
    test('voice 직후(gap=0)에도 rearCamera는 나온다', () {
      final arbiter = GuidanceArbiter();
      // voice 발화 후 gap=0 상태에서 rearCamera를 함께 넣는다
      final result = arbiter.arbitrate(
        rearCamera: [rearCameraIntent],
        voice: [voiceIntent],
        structure: [],
        curve: [],
      );
      // rearCamera는 반드시 포함
      expect(result.any((i) => i.key == 'rear_camera_approach'), isTrue);
    });
  });

  group('5 — 후면단속 → voice 억제: rearCamera 발화 후 0ms → voice 드롭', () {
    test('같은 틱에서 rearCamera 발화 후 voice는 gap 부족으로 드롭', () {
      final arbiter = GuidanceArbiter();
      final result = arbiter.arbitrate(
        rearCamera: [rearCameraIntent],
        voice: [voiceIntent],
        structure: [],
        curve: [],
      );
      // rearCamera만 있어야 하고 voice는 없어야 한다
      expect(result.any((i) => i.key == 'rear_camera_approach'), isTrue);
      expect(result.any((i) => i.key == 'turn_left_approach'), isFalse,
          reason: 'rearCamera 직후 gap=0이라 voice는 드롭돼야 한다');
    });
  });

  group('6 — reset 후: 첫 발화는 gap 없이 통과', () {
    test('reset() 후 첫 voice는 바로 통과된다', () {
      final arbiter = GuidanceArbiter();
      // 먼저 한번 발화해서 _lastSpoken을 세팅
      arbiter.arbitrate(
        rearCamera: [],
        voice: [voiceIntent],
        structure: [],
        curve: [],
      );
      // reset으로 _lastSpoken = null
      arbiter.reset();
      // 바로 두 번째 발화 → gap = ∞ → 통과
      final result = arbiter.arbitrate(
        rearCamera: [],
        voice: [voiceIntent],
        structure: [],
        curve: [],
      );
      expect(result.length, 1);
      expect(result[0].key, 'turn_left_approach');
    });
  });

  group('7 — 첫 발화(virgin arbiter)는 gap 없이 통과', () {
    test('새 arbiter에서 voice는 바로 통과', () {
      final arbiter = GuidanceArbiter();
      final result = arbiter.arbitrate(
        rearCamera: [],
        voice: [voiceIntent],
        structure: [],
        curve: [],
      );
      expect(result.length, 1);
      expect(result[0].key, 'turn_left_approach');
    });
  });
}
