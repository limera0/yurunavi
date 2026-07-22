# REPORT 작성 — Valhalla class_factors 포크 빌드/검증 기록

> 범위: `/data/projects/yurunavi/REPORT_FORK_BUILD.md` 한 파일 작성만. 코드·빌드·서비스 조작 없음.
> 목적: 포크 재현·운영 교체에 필요한 사실을 한 곳에 기록.

아래 내용으로 `/data/projects/yurunavi/REPORT_FORK_BUILD.md`를 작성하라:

```
# REPORT: Valhalla class_factors 포크 (빌드·검증 완료)

작성: 2026-06-07

## 목적
스톡 Valhalla가 class_factors를 무시 → 세 코스(시골길/지방도/국도)가 동일 geometry로 붕괴.
RoadClass(0~7)별 비용 배수를 motorcycle costing에 구현해 코스 차별화를 엔진 레벨에서 강제.

## 소스 / 버전
- 베이스: valhalla 3.7.0 (clone /data/projects/valhalla-src)
- 빌드 HEAD: <git rev-parse --short HEAD 값 기입>
- 운영 이미지: ghcr.io/valhalla/valhalla:latest (3.7.0-5ed7267b7)
- ⚠️ 운영 커밋(5ed7267b7)과 빌드 커밋이 일치하지 않을 수 있음(STEP 0 checkout 결과 기입). 현재 포크는 빌드 커밋 기준.

## 패치 3지점
- ① proto/descriptors/options.proto : Costing.Options에 `map<uint32,float> class_factors = 97;` 추가
- ② src/sif/motorcyclecost.cc ParseMotorcycleCostOptions() : JSON /class_factors → proto map 파싱
      (strtoul 키검증 + key<=7 + static_cast<float>(GetDouble()) — int/double 혼용·잘못된 키 안전)
- ③ src/sif/motorcyclecost.cc : 생성자에서 proto map → std::array<float,8> class_factor_{1..1}로 펼침,
      EdgeCost()의 `factor *= EdgeFactor(edgeid)` 직전에 `factor *= class_factor_[classification()]` 주입
- 기본값 1.0 = class_factors 미지정 시 스톡과 완전 동일(하위호환).

## 빌드 (커스텀 이미지)
- 이미지: valhalla-fork:5ed7267b-classfactors
- 빌드 파일: docker/Dockerfile.fork (원본 docker/Dockerfile 사본, 원본 불변)
- 사본 수정 3곳(전부 Python 바인딩 비활성화의 후속):
  - cmake 플래그에 `-DENABLE_PYTHON_BINDINGS=Off` 추가 (third_party/nanobind 서브모듈 회피)
  - runner 스테이지 `COPY --from=builder .../dist-packages/valhalla` 줄 제거
  - runner 스테이지 python smoke test(`import valhalla`) 줄 제거
- 서브모듈: shallow clone이라 빌드 전 `git submodule update --init --recursive --depth 1` 필요
  (ankerl/unordered_dense.h 등 빌드 의존 헤더)
- 빌드 커맨드: docker build -t valhalla-fork:5ed7267b-classfactors --build-arg CONCURRENCY=2 -f docker/Dockerfile.fork .

## 검증 (포트 8012, 운영 타일 읽기전용 공유, 운영 8002 불가침)
- 기동: docker run -d --name valhalla-fork-test -p 8012:8002 -v /data/valhalla/custom_files:/custom_files:ro <image> valhalla_service /custom_files/valhalla.json 1
- OD: (37.2793,127.0431) → (37.2394,127.1999)

### A/B/C 거리
| 프로필 | 거리 | class_factors |
| A 시골길 | 20.94km | 국도(2) 6배 회피, 시군도(4) 0.6 선호 |
| B 기본   | 17.19km | 없음 (하위호환 확인) |
| C 국도   | 17.30km | 국도(2) 0.5 선호 |

### 등급 분포 (trace_attributes, 거리%)
| 프로필 | primary(국도) | secondary(지방도) | tertiary(시군도) | residential |
| A 시골길 | 0%   | 28.3% | 70.1% | 1.5% |
| B 기본   | 76.1%| 19.0% | 3.7%  | 1.0% |
| C 국도   | 92.5%| 3.8%  | 2.9%  | 0.6% |

### 판정
- A에 primary 0% → 국도 완전 회피, PPT 정의 "시골길=시군도 위주+지방도 보완"과 일치.
- 등급 사다리 코스별 분리(primary 76→92→0%). 스톡 붕괴 문제 해결.
- B는 스톡 동작 보존(하위호환 OK).

## 한국 도로 ↔ RoadClass 확정 매핑 (RECON_KR_ROADCLASS.md)
- 0 motorway=고속도로 / 1 trunk=도시고속·자동차전용 / 2 primary=일반국도 /
  3 secondary=지방도 / 4 tertiary=시군도 / 5 unclassified=소로 / 6 residential=마을 / 7 service=농로
- ★ 일반국도=primary(2)이지 trunk 아님. motorway(0)+trunk(1)은 세 코스 전부 회피(이륜차 부적합).

## 남은 일 (이번 범위 밖)
- [ ] 앱: routing_service.dart class_factors 5키 → 0~7 8키 교체 (별도 커밋, 앱 빌드는 마스터)
- [ ] 스쿠터 실측으로 체감 검증
- [ ] 실측 통과 후에만 운영 docker-compose를 포크 이미지로 교체 + 태그 핀 고정
- [ ] unclassified(5) 실사례 미관측 — osmium bulk 샘플은 선택적 하드닝
- [ ] urban_penalty는 미구현(타일 use_urban_tag:false) — 필요시 타일 재빌드 별건
- [ ] 곡률/골프 보너스(2차축)는 Rust fun_score 레이어 — 미연결, 별도 작업

## 검증 컨테이너 정리
- valhalla-fork-test는 검증용. 앱 연결 실측까지 살려두고, 불필요 시 docker stop/rm.
```

작성 후 정지.
