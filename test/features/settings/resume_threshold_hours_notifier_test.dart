// S15 청크2 — "이어서 안내하기" 재개 제안 임계치 설정
// (HANDOFF_0810_S15_resume_navigation.md §2).
//
// ResumeThresholdHoursNotifier는 MapNightDimEnabledNotifier와 동일한
// AsyncNotifier<T> + shared_prefs 단일 키 패턴을 따른다. 기본값 2시간,
// set() 후 값이 영속화되고 다음 build()에서도 그대로 로드되는지 검증한다.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yurunavi/features/settings/providers/settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('shared_prefs에 저장된 값이 없으면 기본값 2시간을 반환한다', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final hours = await container.read(resumeThresholdHoursProvider.future);

    expect(hours, 2);
  });

  test('set() 호출 후 state가 즉시 새 값으로 갱신된다', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(resumeThresholdHoursProvider.future);
    await container.read(resumeThresholdHoursProvider.notifier).set(6);

    final updated = container.read(resumeThresholdHoursProvider);
    expect(updated.value, 6);
  });

  test('set() 후 값이 shared_prefs에 영속화되어 새 컨테이너에서도 로드된다', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(resumeThresholdHoursProvider.notifier).set(12);

    // 새 ProviderContainer(=새 build() 호출)로 앱 재시작을 흉내낸다. 같은
    // SharedPreferences 목 백엔드를 공유하므로 방금 저장한 값이 그대로
    // 로드되어야 한다.
    final freshContainer = ProviderContainer();
    addTearDown(freshContainer.dispose);
    final reloaded =
        await freshContainer.read(resumeThresholdHoursProvider.future);

    expect(reloaded, 12);
  });

  test('옵션 값 각각(1/2/3/6/12/24시간)이 set→영속 왕복된다', () async {
    for (final hours in [1, 2, 3, 6, 12, 24]) {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(resumeThresholdHoursProvider.notifier).set(hours);
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getInt('resume_threshold_hours_v1'), hours);
    }
  });
}
