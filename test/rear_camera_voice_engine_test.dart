import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';

void main() {
  List<SpeakIntent> drive(
      RearCameraVoiceEngine e, List<({double distM, bool inPostZone})> seq) {
    final out = <SpeakIntent>[];
    for (final tick in seq) {
      out.addAll(e.onProgress(tick.distM, tick.inPostZone));
    }
    return out;
  }

  group('A — 150m 진입', () {
    test('150m 이하로 처음 진입할 때 정확히 1회만 발화한다(그 이내에 머물러도 재발화 없음)', () {
      final engine = RearCameraVoiceEngine();
      final intents = drive(engine, [
        (distM: 200, inPostZone: false), // 아직 150m 밖 — idle
        (distM: 150, inPostZone: false), // 진입 — 발화
        (distM: 140, inPostZone: false), // 계속 접근 — 재발화 없음
        (distM: 120, inPostZone: false),
        (distM: 100, inPostZone: false),
      ]);
      expect(intents.map((i) => i.key).toList(), ['rear_camera_approach']);
    });
  });

  group('B — 50m 진입', () {
    test('50m 이하로 처음 진입할 때 정확히 1회만 발화한다(그 이내에 머물러도 재발화 없음)', () {
      final engine = RearCameraVoiceEngine();
      final intents = drive(engine, [
        (distM: 150, inPostZone: false), // approach 발화
        (distM: 100, inPostZone: false),
        (distM: 50, inPostZone: false), // final_countdown 발화
        (distM: 40, inPostZone: false), // 계속 접근 — 재발화 없음
        (distM: 10, inPostZone: false),
      ]);
      expect(intents.map((i) => i.key).toList(),
          ['rear_camera_approach', 'rear_camera_final_countdown']);
    });

    test('inPostZone=true(통과 후 사후구간)에서는 거리가 오르내려도 재발화하지 않는다', () {
      final engine = RearCameraVoiceEngine();
      final intents = drive(engine, [
        (distM: 150, inPostZone: false),
        (distM: 50, inPostZone: false),
        (distM: 10, inPostZone: false),
        (distM: 5, inPostZone: true), // 카메라 통과, 사후구간 진입
        (distM: 20, inPostZone: true), // 사후구간 안에서 거리 재상승 — 헷갈리면 안 됨
        (distM: 60, inPostZone: true),
      ]);
      expect(intents.map((i) => i.key).toList(),
          ['rear_camera_approach', 'rear_camera_final_countdown']);
    });
  });

  group('C — 이벤트 종료 후 새 카메라 재진입', () {
    test('idle(150m 초과 + inPostZone=false)로 완전히 복귀하면 다음 카메라에서 두 안내가 다시 나간다', () {
      final engine = RearCameraVoiceEngine();
      // 첫 번째 카메라: 접근 + 최종 카운트다운 + 사후구간 통과.
      drive(engine, [
        (distM: 150, inPostZone: false),
        (distM: 50, inPostZone: false),
        (distM: 5, inPostZone: true),
        (distM: 90, inPostZone: true), // 사후구간 끝자락
      ]);
      // 사후구간을 완전히 벗어나 idle로 복귀(무한대 + inPostZone=false).
      final idleIntents =
          drive(engine, [(distM: double.infinity, inPostZone: false)]);
      expect(idleIntents, isEmpty);

      // 두 번째 카메라 접근 — 두 안내 모두 재발화돼야 한다.
      final secondCamIntents = drive(engine, [
        (distM: 150, inPostZone: false),
        (distM: 50, inPostZone: false),
      ]);
      expect(secondCamIntents.map((i) => i.key).toList(),
          ['rear_camera_approach', 'rear_camera_final_countdown']);
    });
  });

  group('D — mid-event 마운트(생성자 시드 없이 첫 onProgress부터 이미 진행 중)', () {
    test('갓 생성된 엔진의 첫 onProgress가 이미 50m 이내면 접근+최종 안내가 그 자리에서 한 번에 나가고 '
        '이후 재진입해도 재발화하지 않는다', () {
      final engine = RearCameraVoiceEngine();
      final intents = drive(engine, [
        (distM: 30, inPostZone: false), // 첫 호출부터 이미 최종구간 이내
        (distM: 20, inPostZone: false),
        (distM: 40, inPostZone: false), // 같은 사이클 내 거리 재상승 — 재발화 없음
      ]);
      expect(intents.map((i) => i.key).toList(),
          ['rear_camera_approach', 'rear_camera_final_countdown']);
    });

    test('갓 생성된 엔진의 첫 onProgress가 이미 사후구간(inPostZone=true)이면 안내를 내지 않는다', () {
      final engine = RearCameraVoiceEngine();
      final intents = drive(engine, [
        (distM: 20, inPostZone: true), // 첫 호출부터 이미 사후구간
        (distM: 80, inPostZone: true),
      ]);
      expect(intents, isEmpty);
    });
  });

  group('E — reset()', () {
    test('reset 후 이미 접근 사이클 중이었어도 다음 tick에서 다시 발화한다', () {
      final engine = RearCameraVoiceEngine();
      drive(engine, [(distM: 150, inPostZone: false)]);
      engine.reset();
      final intents = drive(engine, [(distM: 100, inPostZone: false)]);
      expect(intents.map((i) => i.key).toList(), ['rear_camera_approach']);
    });
  });
}
