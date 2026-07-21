cat > /data/projects/yurunavi/NIGHT_TASK.md << 'EOF'

# NIGHT_TASK 6: 경로 ETA 현실화 + 3경로 차별화 (routing_service.dart)

## 배경 (마스터 PPT 피드백 260602)

- 거리 정확(71km ≈ 네이버 71km). 그러나:
  - ETA 2배 빠름: 앱 71km=1:09(61km/h) vs 네이버 71km=1:58(36km/h, 실측 정확).
  - "지방도로 여유롭게"(71km/1:09)와 "국도로 빠르게"(71km/1:09)가 동일 경로.
  - "시골길로 느긋하게"(79km/1:26)가 동탄신도시 직선 10차선 관통 — 시골길 정의 위반.
  - 고속도로 미사용 = 정상(앱 존재 이유). 절대 건드리지 말 것.

## 스코프 (엄격)

- 수정 대상: lib/services/routing_service.dart 중심. 그 외 파일·UI·라우팅 흐름 변경 금지.
- 숲/굽이 기반 진짜 "fun-road 스코어링"은 이번 범위 아님 → Rust 차기 작업. 설계만 보고서에.
- APK 빌드 금지(아침에 사람이). flutter analyze까지만.
- 단계마다 git 커밋. 회귀 시 해당 단계만 되돌리고 보고.

## STEP 0: 체크포인트

git add -A && git commit -m "checkpoint: before night6 routing fixes" || true
git log --oneline -1

## STEP 1: 진단 (수정 전 필수)

1-a. fetchRoutes 현재 구현 전체와 Valhalla 응답 파싱부 확인:
    sed -n '1,140p' lib/services/routing_service.dart
1-b. 실제 Valhalla 응답에서 시간/거리 원본값 확인 (서울→동탄 근방 좌표로):
    curl -s "http://localhost:8002/route" -H "Content-Type: application/json" \
      -d '{"locations":[{"lat":37.40,"lon":127.10},{"lat":37.20,"lon":127.07}],"costing":"auto","directions_options":{"units":"kilometers"}}' \
      | python3 -c "import sys,json;d=json.load(sys.stdin);s=d['trip']['summary'];print('length_km',s['length'],'time_s',s['time'],'-> km/h',round(s['length']/(s['time']/3600),1))"
    → 표시 ETA가 Valhalla time(초)을 그대로 쓰는지, Dart에서 자체 계산하는지 판별.

## STAGE 1: ETA 현실화

- 경로 종류별 실효속도로 도착시간 산출 (Valhalla의 낙관적 속도 대신):
    시골길 ≈ 30 km/h, 지방도 ≈ 36 km/h, 국도 ≈ 45 km/h
  (근거: 네이버 71km=118분=36km/h가 지방도+국도 혼합 실측. 시골길은 더 느림.)
- 구현: 각 경로의 거리(Valhalla length)는 그대로 두고, ETA = 거리 / 실효속도.
  상수는 파일 상단에 명명된 const로 (하드코딩 매직넘버 금지, 주석으로 근거).
- 검증: 약 71km 경로가 지방도 기준 ~118±10분으로 표시되는지 (curl 결과로 거리 확인 후 계산).
- flutter analyze 통과 확인.
- 커밋: git add -A && git commit -m "fix(routing): realistic per-class ETA (was ~2x too fast)"

## STAGE 2: 세 경로 distinct화 (Stage 1 커밋 성공 시에만)

- 현행 'alternates 1회 + 거리정렬' 방식 폐기. 대신 코스 타입별로 Valhalla 3회 호출,
  costing_options를 차등하여 서로 다른 geometry 유도:
    국도로 빠르게:   use_highways:0(모터웨이 배제 유지), use_living_streets:0, top_speed 높게, 최단 우선 성향
    지방도로 여유롭게: use_highways:0, use_living_streets:0.3, 국도 의존 낮춤
    시골길로 느긋하게: use_highways:0, use_living_streets:1, use_tracks 소폭↑, top_speed 낮게 → 큰 도로 회피
  (주의: Valhalla 노브 한계로 "지방도 vs 국도" 의미 구분은 불완전할 수 있음. 일단 distinct + 시골길의 대로 회피가 목표.)
- 세 호출 결과 geometry가 서로 다른지 확인. 동일하면 파라미터 조정 후 재시도(최대 3회 튜닝).
- 검증 (curl 3회, 거리/시간/요약 비교):
  - 세 경로의 거리 또는 polyline이 서로 다를 것.
  - Stage1 속도모델 적용 시 국도가 지방도보다 ~20~30% 빠른 ETA가 나오는지 확인.
  - 시골길이 1번 캡처처럼 도심 대로로만 직진하지 않는지 (가능하면 polyline 길이/우회 정도로 간접 확인).
- flutter analyze 통과.
- 커밋: git add -A && git commit -m "feat(routing): three distinct route profiles via differentiated costing"

## STOP 조건

- Stage 2에서 세 경로를 distinct하게 만들지 못하거나 route search가 불안정해지면:
  → Stage 2 변경만 git revert, Stage 1은 유지, 사유를 보고서에 기록하고 중단.

## STEP 5: MORNING_REPORT_night6b.md

- STEP1 진단(원본 time/거리/속도) 수치.
- Stage1/2 변경 diff 요약(before/after 값).
- curl 검증 결과 3경로 비교표.
- [중요] 차기 Rust 스코어링 설계 제안: 숲 근접도·굽이지수(curviness)·도로등급 가중으로
  Valhalla 후보를 재평가/재탐색하는 구조. PPT 정의(숲길/좁은길/저교통, 1.3배 초과 시 지방도 혼합,
  국도 20~30% 빠름)를 어떤 데이터(OSM highway tag, geometry 곡률)로 계산할지 초안.

## 절대 금지

- 고속도로 회피 로직 변경 / UI·다른 서비스 파일 수정 / APK 빌드 / .bak 외 파일에 ts.net 잔재 재유입
  EOF
  echo "NIGHT_TASK.md 작성 완료"
