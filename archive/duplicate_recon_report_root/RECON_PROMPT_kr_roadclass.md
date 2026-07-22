# 정찰 프롬프트 — 한국 OSM 도로 등급 ↔ RoadClass(0~7) 실데이터 검증

> **실행 환경:** Claude Code on Ubuntu(westinx), Sonnet 4.6, 읽기전용. osmium 있으면 /goal 무인 가능.
> **목표:** 한국 OSM에서 **국도·지방도·시군도가 실제로 어떤 `highway=` 클래스로 태깅됐는지**를 실데이터로 확정하고, Valhalla `RoadClass`(0~7) 매핑을 검증한다. 이게 class_factors 8키 프로필 값의 전제다.
> **배경:** 포크는 class_factors를 Valhalla RoadClass enum 0~7 직결로 받음(0 motorway … 7 service). 프로필 값은 "trunk(1)=국도, primary(2)=지방도, secondary(3)=시군도"라는 **가정** 위에 있는데, 한국 태깅이 이와 다를 수 있어 검증 필요.

---

## 🚫 절대 규칙

- **읽기전용.** 허용 쓰기: ① `/tmp` 스크래치 파일(중간 추출물), ② 최종 보고서 `/data/projects/yurunavi/RECON_KR_ROADCLASS.md`. 그 외 일절 금지.
- **금지:** `apt install` 등 패키지 설치(osmium 없으면 설치하지 말고 보고만), 소스/프로젝트 파일 수정, docker/systemctl/서비스 재시작, 운영 타일 변경.
- `/trace_attributes` 등 운영 Valhalla로의 **읽기 요청(POST지만 조회용)은 허용**.
- **추측 금지.** 실제 추출된 ref/name 값만 인용. 사용한 명령은 보고서에 그대로 기록.

---

## 0단계: 데이터·도구 확인

```bash
# 한국 pbf 위치 탐색
ls -lah /data/valhalla/custom_files/*.pbf 2>/dev/null
find /data -maxdepth 4 -iname "*korea*.osm.pbf" 2>/dev/null
find /data -maxdepth 4 -iname "*south-korea*.pbf" 2>/dev/null
# 도구 확인
which osmium osmconvert osmfilter 2>/dev/null
osmium --version 2>/dev/null
```

- 한국 pbf 경로와 osmium 가용 여부를 **먼저 보고**.
- **osmium이 없으면**: 설치하지 말고, 0단계 결과 + 아래 "부록(엔진 검증)"만 채운 뒤 정지. (마스터가 설치 여부 판단.)

---

## A단계: OSM 소스 샘플링 (osmium 있을 때 — 1차·핵심)

각 highway 클래스별로 **한국 도로의 실제 ref/name 샘플**을 뽑는다. 목표: "이 클래스 = 한국의 무슨 도로"를 눈으로 확인.

대상 클래스: `motorway`, `trunk`, `primary`, `secondary`, `tertiary`, `unclassified`, `residential`

참고 파이프라인(설치된 osmium 버전에 맞게 적응하고, **실제 사용한 명령을 보고서에 기록**):

```bash
KR=/data/valhalla/custom_files/<korea>.pbf   # 0단계서 확인된 실제 경로
for C in motorway trunk primary secondary tertiary unclassified residential; do
  osmium tags-filter "$KR" w/highway=$C -o /tmp/kr_$C.osm.pbf --overwrite 2>/dev/null
  echo "=== $C ==="
  # ref/name 분포 상위 추출 (OPL로 펼쳐 ref=/name= 태그 집계)
  osmium cat /tmp/kr_$C.osm.pbf -f opl 2>/dev/null \
    | grep -oE 'Tref=[^,]*|Tname:ko=[^,]*|Tname=[^,]*' \
    | sort | uniq -c | sort -rn | head -25
done
```

각 클래스마다 보고서에 적을 것:

- 전체 way 개수(대략)
- **상위 ref 값 15~25개** (예: trunk → `ref=1`, `ref=17` … = 국도 번호인지)
- 대표 name 샘플 몇 개 (한글명 — 무슨 길인지 식별)

> 핵심 판독 포인트:
> 
> - **국도(1·2·3자리 번호 단독, "국도 N호선")가 trunk에 있나 primary에 있나?**
> - **지방도(보통 3자리, "지방도 NNN")가 primary인가 secondary인가?**
> - **시군도/면도가 secondary~tertiary 어디에 떨어지나?**

---

## B단계: Valhalla 엔진 교차확인 (road_class가 OSM 태그와 일치하는지)

A단계에서 식별된 **대표 도로 1~2개씩**(국도/지방도/시군도)의 좌표를 잡아(osmium 추출물의 노드 좌표 또는 알려진 지점), 운영 Valhalla에 질의해 `road_class`가 OSM highway 태그와 일치하는지 확인.

```bash
# 예시: 두 점 사이를 motorcycle로 trace해 edge.road_class + edge.names 반환
curl -s -X POST https://valhalla.westinx.com/trace_attributes \
  -H "Content-Type: application/json" \
  -d '{
    "shape":[{"lat":<L1>,"lon":<O1>},{"lat":<L2>,"lon":<O2>}],
    "costing":"motorcycle",
    "shape_match":"map_snap",
    "filters":{"attributes":["edge.road_class","edge.names","edge.way_id"],"action":"include"}
  }' | python3 -m json.tool | head -60
```

- 반환된 `edge.road_class`(문자열: "motorway"/"trunk"/"primary"…)와 `edge.names`를 대조표에 기록.
- A단계 결과와 **모순이 없는지**만 확인(있으면 그 사실을 강조).

---

## 출력: `RECON_KR_ROADCLASS.md`

```
# RECON: 한국 OSM 도로등급 ↔ RoadClass 검증

## 0. 데이터·도구
- pbf 경로 / osmium 버전 / 가용 여부

## A. OSM 소스 샘플링 (클래스별 ref·name 상위)
- motorway / trunk / primary / secondary / tertiary / unclassified / residential
  (각: way수, 상위 ref 목록, 대표 name)
- 사용한 실제 명령 기록

## B. 엔진 교차확인
- 샘플 도로 → road_class → OSM 태그 일치/불일치 표

## C. 결론 — 한국 도로 ↔ RoadClass 확정 매핑
| 한국 행정 도로 | 실제 OSM highway | RoadClass(0~7) | 비고 |
| 고속도로 | motorway | 0 | |
| 일반국도 | trunk? primary? | ? | ★검증 결과 |
| 지방도 | ? | ? | |
| 시군도 | ? | ? | |
| 시골/이면/농도 | tertiary/unclassified/residential | 4~6 | |

## D. class_factors 8키 프로필에 주는 영향
- ✅ 가정(국도=trunk 등)이 맞았는지
- ⚠️ 어긋난 부분 + 어느 키 값을 조정해야 하는지
- ❓ 미확인

## 부록(osmium 부재 시): 마스터가 직접 돌릴 검증 명령
- (B단계 trace_attributes 템플릿 + 마스터가 아는 국도/지방도 좌표 넣는 법)
```

작성 후 **정지**. 프로필 값 수정 제안은 하지 말 것(사실 수집·매핑 확정만).
