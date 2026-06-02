# MORNING_REPORT — Night 7 (2026-06-02)

## 오늘 한 일

**모듈**: `lib/services/routing_service.dart` — Valhalla costing_options 정밀화

OSM 가중치 사양서(Gemini) 기준으로 3개 Valhalla 프로필에 `class_factors`(FC1~FC5)를 추가하고,
시골길 프로필에만 `urban_penalty: 50.0`을 추가함.

### 변경 내용 (costingOptions 3개 맵에만 국한)

| 파라미터 | 시골길 | 지방도로 | 국도 |
|---|---|---|---|
| `class_factors.1` (고속국도) | 100.0 | 100.0 | 100.0 |
| `class_factors.2` (일반국도) | 5.0 | 2.0 | 0.4 |
| `class_factors.3` (지방도) | 2.5 | 0.5 | 1.0 |
| `class_factors.4` (군도) | 1.0 | 0.7 | 2.0 |
| `class_factors.5` (생활도로) | 0.2 | 1.5 | 10.0 |
| `urban_penalty` | **50.0** | — | — |
| 기존 파라미터 | 유지 | 유지 | 유지 |

ETA 관련 파라미터(top_speed, fixed_speed_class)는 **의도적으로 미수정** — 이중보정 위험.

---

## git log (최근 관련 커밋)

```
10eab85 feat(routing): add class_factors + urban_penalty per OSM spec (night7)
a1a2fbd checkpoint: before night7 — class_factors + urban_penalty task
640ce62 docs: MORNING_REPORT night6b — ETA현실화 + 3경로distinct PASS
480ff27 feat(routing): three distinct route profiles via differentiated costing
48f320f fix(routing): realistic per-class ETA (was ~2x too fast)
```

---

## PASS / FAIL

**PASS**

- `flutter analyze`: No issues found (전체 프로젝트)
- Valhalla live 검증 (수원 영통구 → 용인 처인구):
  - 3개 프로필 모두 HTTP 200, 유효한 trip.summary 반환
  - 3경로 모두 다른 거리: 시골길 17.2km / 지방도 15.9km / 국도 15.4km → distinct 유지 ✓
  - `class_factors`, `urban_penalty` 파라미터 오류 없음 (400 없음)
  - 시골길이 가장 긴 경로 → 우회 성향 정상 ✓
- 시크릿 없음, 위험 명령 없음 ✓

---

## 막힌 점 / 미완료

1. **동탄 도심 우회 실제 효과는 APK 화면 확인 필요.**
   `urban_penalty: 50.0`이 적용됐고 Valhalla가 수락했지만, 실제로 시골길 경로가 동탄신도시 10차선 대로를 피하는지는 curl 숫자만으로는 증명 불가.
   → **아침에 APK 빌드 → 폰 설치 → 동탄 구간 경로 확인이 필수.**

2. **ETA Valhalla 전환 미착수 (의도적 보류).**
   사양서 4.2절의 `fixed_speed_class` 방식 ETA 보정은 현재 Dart 후처리 상수
   (`_speedCountrysideKmh` 등)와 이중 적용 시 회귀 위험. 별도 세션에서:
   - Dart 상수 제거 → Valhalla `fixed_speed_class` 적용 순서로 교체 필요.

3. **STRETCH 미착수 (Rust 1.3배 dynamic fallback).**
   토큰 한도 고려 + 주 모듈 완료까지가 오늘 목표였으므로 시작하지 않음.

---

## 다음 세션 추천 1개

**APK 빌드 → 화면 확인 → 동탄 우회 실증**

```bash
cd /data/projects/yurunavi
grep -rn "tail2172f6\|\.ts\.net" lib/ | grep -v "\.bak" || echo "✅ clean"
nohup flutter build apk --release > build_$(date +%H%M).log 2>&1 &
```

- 시골길 경로가 동탄 신도시 내부를 여전히 직진하면 → `urban_penalty`를 100.0으로 상향 또는 `class_factors.5`를 0.1로 추가 강화.
- 통과하면 → Rust 1.3배 dynamic fallback 또는 ETA 전환 세션으로 진행.
