# 구현 프롬프트 — Valhalla class_factors 포크 (감독형, 단계별 정지)

> **실행 환경:** Claude Code on Ubuntu(westinx), **마스터 직접 감독**(무인 /goal 금지 — C++ 빌드·회귀위험).
> **목표:** 운영과 동일한 커밋 `5ed7267b7`에서 Valhalla를 포크해 `class_factors`(RoadClass 0~7별 비용 배수)를 motorcycle costing에 구현하고, **별도 포트 8012**로 커스텀 이미지를 띄워 A/B curl로 동작을 검증한다.
> **운영(8002) 절대 불가침.** docker-compose 교체·운영 컨테이너 조작은 이번 범위 밖.

---

## 🚫 절대 규칙

- 각 단계(STEP) 끝에서 **반드시 정지하고 결과를 보고**한다. 다음 STEP로 자동 진행 금지. 마스터의 "다음" 지시를 기다린다.
- **운영 건드림 금지:** `yurunavi-valhalla` 컨테이너, 포트 8002, `/data/valhalla/custom_files/valhalla.json`, docker-compose.yml 수정·재시작 일절 금지.
- 커스텀 빌드/실행은 **`/data/projects/valhalla-src` 소스 + 새 컨테이너명 `valhalla-fork-test` + 포트 8012**로만.
- **추측 금지.** 패치 전 각 파일의 실제 현재 내용을 `view`로 재확인(줄번호는 커밋이 달라 이동했을 수 있음). 정찰 보고서의 줄번호를 맹신하지 말 것.
- 타일은 **운영 것을 읽기전용으로 공유 마운트**(재빌드 없음).
- 빌드/장시간 작업은 tmux 세션에서. 보고는 터미널이 아니라 단계별 요약 + 최종 `REPORT_FORK_BUILD.md`.

---

## 패치 사양 (확정)

**class_factors = RoadClass enum(0~7) 직결 map.** 8칸 배열로 펼쳐 EdgeCost 핫패스에서 인덱스 1회 조회. 기본값 1.0(미지정 시 스톡과 완전 동일 동작 → 하위호환).

3지점:
- **① proto:** `proto/descriptors/options.proto`의 `Costing.Options`에 `map<uint32, float> class_factors = <마지막필드+1>;` 추가. (정찰: 마지막 96 → 97. **실제 파일에서 마지막 필드번호 재확인 후 +1.**)
- **② 파싱:** `src/sif/motorcyclecost.cc` `ParseMotorcycleCostOptions()`에서 JSON `/class_factors` 오브젝트를 읽어 proto map에 적재. (`hierarchy_limits` map 파싱 패턴 참고.)
- **③ EdgeCost:** `MotorcycleCost` 생성자에서 proto map → `std::array<float,8> class_factor_{1,1,1,1,1,1,1,1}`로 펼침. `EdgeCost()`의 `factor *= EdgeFactor(edgeid);` **직전**에 독립 배수 주입:
  ```cpp
  factor *= class_factor_[static_cast<uint32_t>(edge->classification())];
  ```

---

## STEP 0 — 소스 정합성 게이트 (빌드 전 추측 닫기)

```bash
cd /data/projects/valhalla-src
git fetch --depth 50 origin 2>&1 | tail -3
git checkout 5ed7267b7 2>&1 | tail -3 || echo "CHECKOUT_FAIL"
git rev-parse --short HEAD     # 5ed7267b 확인
```

- `5ed7267b7` checkout 성공 여부 보고. **실패(GC 등) 시 정지하고 보고** — 폴백(3.7.0 태그) 여부는 마스터가 결정.
- 성공 시 **3지점 실제 현재 상태를 view로 확인**하고 보고:
  - `proto/descriptors/options.proto` — `Costing.Options`의 **마지막 필드번호**, `map<uint32,...>` 사용례(hierarchy_limits) 줄번호
  - `src/sif/motorcyclecost.cc` — `ParseMotorcycleCostOptions()` 위치, `MotorcycleCost` 생성자 위치, `EdgeCost()`의 `factor *= EdgeFactor` 줄번호, `edge->classification()` 현재 사용 줄
- **여기서 정지.** 줄번호·필드번호 확정값을 보고하고 마스터 확인 대기. (← 패치는 다음 STEP)

---

## STEP 1 — 3지점 패치 (코드 수정, 빌드 전)

STEP 0에서 확정한 위치에만 최소 수정:
1. proto 필드 추가
2. 파싱 코드 추가
3. 생성자 펼침 + EdgeCost 1줄 주입

각 수정 후 `git diff`를 보고한다. **빌드는 하지 않는다. 여기서 정지.** diff를 마스터가 검토.

---

## STEP 2 — 빌드 (tmux, 장시간)

```bash
tmux new -s fork-build
cd /data/projects/valhalla-src
# 공식 Dockerfile로 커스텀 이미지 빌드 (이미지명 분리)
docker build -t valhalla-fork:5ed7267b-classfactors -f docker/Dockerfile . 2>&1 | tee /tmp/fork_build.log
```

- 빌드 성공/실패 보고. 실패 시 `/tmp/fork_build.log` 마지막 30줄 + 원인 추론. **수정·재시도 전 정지하고 보고.**
- proto 변경이 포함되므로 protobuf 코드 재생성이 빌드에 포함되는지 확인(로그에서 `options.pb` 재생성 흔적).

---

## STEP 3 — 포트 8012로 기동 (운영과 격리)

운영 타일을 **읽기전용**으로 공유, 새 컨테이너·새 포트:
```bash
docker run -d --name valhalla-fork-test \
  -p 8012:8002 \
  -v /data/valhalla/custom_files:/custom_files:ro \
  valhalla-fork:5ed7267b-classfactors \
  valhalla_service /custom_files/valhalla.json 1
sleep 5
curl -s http://localhost:8012/status | python3 -m json.tool   # 기동 확인
```

- 기동 성공/실패 보고. 실패 시 `docker logs valhalla-fork-test` 마지막 20줄. **정지.**

---

## STEP 4 — A/B 검증 (class_factors가 이제 실제로 동작하는지)

동일 OD에 **class_factors만 넣고/빼고** → 거리/geometry가 **달라져야** 성공(스톡에선 19.51로 동일했던 그 테스트).
```bash
# A: class_factors 적용 (국도 회피·농로 선호 극단값)
curl -s -X POST http://localhost:8012/route -H "Content-Type: application/json" -d '{
  "locations":[{"lat":37.2793,"lon":127.0431},{"lat":37.2394,"lon":127.1999}],
  "costing":"motorcycle",
  "costing_options":{"motorcycle":{"use_highways":0.0,"class_factors":{"0":100,"1":100,"2":6,"3":2,"4":0.6,"5":0.8,"6":0.9,"7":1.0}}}
}' | python3 -c "import sys,json;d=json.load(sys.stdin);print('A(시골길) km:',d['trip']['summary']['length'])"

# B: class_factors 제거, 나머지 동일
curl -s -X POST http://localhost:8012/route -H "Content-Type: application/json" -d '{
  "locations":[{"lat":37.2793,"lon":127.0431},{"lat":37.2394,"lon":127.1999}],
  "costing":"motorcycle",
  "costing_options":{"motorcycle":{"use_highways":0.0}}
}' | python3 -c "import sys,json;d=json.load(sys.stdin);print('B(기본) km:',d['trip']['summary']['length'])"

# C: 국도 코스 (primary 선호) — A와도 달라야
curl -s -X POST http://localhost:8012/route -H "Content-Type: application/json" -d '{
  "locations":[{"lat":37.2793,"lon":127.0431},{"lat":37.2394,"lon":127.1999}],
  "costing":"motorcycle",
  "costing_options":{"motorcycle":{"use_highways":0.0,"class_factors":{"0":100,"1":100,"2":0.5,"3":1.2,"4":2,"5":4,"6":5,"7":8}}}
}' | python3 -c "import sys,json;d=json.load(sys.stdin);print('C(국도) km:',d['trip']['summary']['length'])"
```

- **판정:** A ≠ B 이면 class_factors 동작 확정. A ≠ C 이면 코스 차별화 동작. 세 거리값 보고.
- 추가 확인: A 경로를 `/trace_attributes`로 trace해 **primary(국도) 비중이 B보다 낮은지** edge.road_class 분포로 검증(가능하면).
- 결과를 `REPORT_FORK_BUILD.md`에 정리하고 정지.

---

## 마무리 / 범위 밖 (이번에 하지 말 것)

- 운영 docker-compose 교체, 8002 중단 — **하지 않음**(마스터 스쿠터 실측 통과 후 별도 단계).
- Dart `routing_service.dart`의 class_factors를 0~7 8키로 교체 — **별도 커밋**(앱 빌드는 마스터 담당). 이번 프롬프트는 엔진 검증까지만.
- `valhalla-fork-test` 컨테이너는 검증용 — 검증 후 `docker stop/rm valhalla-fork-test`로 정리(마스터 판단).

각 STEP 끝에서 정지·보고. 전체 완료 후 `REPORT_FORK_BUILD.md` 작성.
