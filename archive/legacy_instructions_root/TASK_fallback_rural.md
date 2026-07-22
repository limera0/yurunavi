# TASK — 시골길 1.3배 폴백 이식 (ROADMAP v2 item 1 마무리)

실행: tmux 안에서 `claude --permission-mode auto`
스코프: **`lib/services/routing_service.dart` 의 `_doFetch` 한 메서드만 수정.**
원칙: Repair over rewrite. 작동 중인 3경로·ETA·캐시·재시도·polyline 디코더는 절대 건드리지 말 것.

---

## 배경 (에이전트가 먼저 이해할 것)

`routing_service.dart` 는 이미 시골/지방/국도 3개 costing 을 Valhalla 에 병렬 요청해
서로 다른 경로를 받고 있다. fun_score·ETA·카드 표시 모두 작동 중이다.

**유일하게 빠진 것:** 시골길(i=0)이 너무 멀리 우회할 때의 안전장치.
Rust `native/src/main.rs` 의 `handle_calc_route` 에는 있지만 Flutter 에는 없다:

> 시골 경로 시간 / 지방 경로 시간 ≥ 1.3 이면, 시골 costing 을 "balanced" 로 완화해
> 다시 요청하고 그 결과로 시골 경로를 교체한다.

이 폴백이 없으면 산 하나 넘으려고 50km 우회하는 비현실적 시골 경로가 사용자에게 노출된다.

---

## 작업 내용

### 위치
`lib/services/routing_service.dart` 의 `static Future<List<RouteResult>> _doFetch(...)`
(현재 약 213~305행. 3개 응답을 받아 `results` 리스트를 만드는 for 루프가 있는 메서드.)

### 수정 방식

**Step 1 — balanced costing 상수 추가**

`main.rs` 의 balanced 와 동일하게. `_doFetch` 위쪽 또는 클래스 상수 영역에 추가:

```dart
// 시골길 우회 과다 시 완화용 costing (main.rs handle_calc_route 와 동일)
static const Map<String, dynamic> _ruralBalancedOpts = {
  'use_highways': 0.0,
  'use_ferry': 0.0,
  'class_factors': {
    '1': 100.0,
    '2': 4.0,
    '3': 1.2,
    '4': 0.8,
    '5': 0.5,
  },
};
```

**Step 2 — 폴백 임계 상수**

```dart
static const double _ruralDetourThreshold = 1.3;
```

**Step 3 — for 루프 종료 후, results 반환 직전에 폴백 블록 삽입**

기존 for 루프(`for (int i = 0; i < 3; i++)`)는 그대로 두고,
`return results;` **직전에** 아래를 끼운다. 이렇게 하면 평소엔 추가 호출 0,
우회가 심할 때만 1회 추가 호출.

```dart
// ── 시골길 1.3배 폴백 (main.rs 와 동작 일치) ──────────────────
// 시골(0) 시간이 지방(1) 시간의 1.3배 이상이면 과다 우회로 보고
// balanced costing 으로 시골 경로만 재요청해 교체한다.
if (results.length == 3) {
  final ruralMins = results[0].durationMin;
  final provMins = results[1].durationMin;
  if (provMins > 0 && ruralMins / provMins >= _ruralDetourThreshold) {
    dev.log(
      '시골길 과다우회 감지 (rural=${ruralMins}m / prov=${provMins}m '
      '= ${(ruralMins / provMins).toStringAsFixed(2)}x ≥ $_ruralDetourThreshold) '
      '→ balanced 재요청',
      name: 'RoutingService',
    );
    try {
      final resp = await http
          .post(
            Uri.parse('$_valhallaBase/route'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'locations': locations,
              'costing': 'motorcycle',
              'costing_options': {'motorcycle': _ruralBalancedOpts},
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final trip = data['trip'] as Map<String, dynamic>?;
        final legs = (trip?['legs'] as List?) ?? [];
        final pts = _extractPoints(legs);
        if (pts.isNotEmpty) {
          final km = legs.fold<double>(
            0,
            (sum, leg) =>
                sum + ((leg['summary']?['length'] as num?) ?? 0).toDouble(),
          );
          // ETA 는 기존과 동일하게 _courseSpeeds[0] 로 재계산 (회귀 방지 핵심)
          final realisticMins = (km / _courseSpeeds[0] * 60).round();
          final maneuvers = <ManeuverStep>[];
          for (final leg in legs) {
            for (final m in (leg['maneuvers'] as List? ?? [])) {
              maneuvers.add(ManeuverStep(
                type: (m['type'] as num?)?.toInt() ?? 0,
                instruction: (m['instruction'] as String?) ?? '',
                distanceKm: (m['length'] as num?)?.toDouble() ?? 0.0,
              ));
            }
          }
          results[0] = RouteResult(
            points: pts,
            distanceKm: km,
            durationMin: realisticMins,
            maneuvers: maneuvers,
          );
          dev.log(
            'balanced 교체 완료: ${km.toStringAsFixed(1)}km '
            '${realisticMins}m',
            name: 'RoutingService',
          );
        }
      }
      // balanced 실패 시: 기존 시골 경로 유지 (조용히 폴백, throw 금지)
    } catch (e) {
      dev.log('balanced 폴백 실패 → 기존 시골 경로 유지: $e',
          name: 'RoutingService', level: 900);
    }
  }
}

return results;
```

⚠️ 기존 `return results;` 한 줄을 위 블록으로 **교체**하는 것. results 반환이 두 번
일어나지 않도록 주의.

---

## 절대 금지
- for 루프 내부의 기존 파싱 로직 수정 (3경로 distinct·ETA 계산 그대로)
- `_courseSpeeds`, `_courseNames`, 캐시(`_cache`), 재시도 루프(`fetchRoutes`) 수정
- `_extractPoints`, `_decodePolyline6` 수정
- balanced 실패 시 throw (반드시 기존 시골 경로로 조용히 폴백)
- 다른 파일 수정 (이번 작업은 routing_service.dart 단일 파일)

---

## 검증 (모두 통과해야 커밋)

```bash
cd /data/projects/yurunavi
flutter analyze                              # No issues
```

**런타임 검증** — Rust 서버 로그로 폴백 동작 확인이 어려우니,
balanced 분기가 코드상 도달 가능한지 + 일반 케이스 회귀 없는지 두 가지를 본다:

1. `flutter analyze` 무이슈
2. 디버그 빌드 성공:
   ```bash
   flutter build apk --debug 2>&1 | tail -5
   ```
3. (선택) 실기기/curl 로 산악 우회 경로 1건 확인은 [HUMAN] 게이트 — 마스터가 폰에서.

---

## 커밋 + 보고

```bash
git add lib/services/routing_service.dart
git commit -m "feat: rural 1.3x detour fallback in fetchRoutes (match main.rs) [ROADMAP-1]"
```

MORNING_REPORT 또는 대화에 보고:
- 수정 파일: routing_service.dart 단일
- flutter analyze 결과
- 빌드 결과
- 커밋 해시
- [HUMAN] 잔여: 실기기에서 산악 우회 경로 폴백 체감 확인

---

## 참고 — 왜 이게 ROADMAP item 1 의 "진짜" 작업인가

Night 11 은 item 1 을 "Valhalla custom_costing 직접 편집 불가"로 [BLOCKED] 처리했으나
이는 오진이었다. costing 은 routing_service.dart 와 main.rs 양쪽에 이미 구현되어
작동 중이며, 3경로는 실제로 다른 도로를 탐색하고 fun_score 도 카드에 표시된다.
유일한 미구현분이 시골길 폴백이었고, 이 작업으로 item 1 은 사실상 종료된다.
(추후 별도 작업: Flutter/Rust costing 중복 일원화 — 지금은 회귀 위험으로 보류.)
