# RECON: Valhalla 3.7.0 포크 패치 설계

작성: 2026-06-06, 읽기 전용 정찰. 코드 수정 없음.

---

## 0. 소스 버전

- **clone 경로**: `/data/projects/valhalla-src`
- **HEAD sha**: `72f459f`
- **운영 이미지 버전**: `ghcr.io/valhalla/valhalla:latest` (docker-compose.yml에 태그 없음), 프롬프트에서 `3.7.0-5ed7267b7`로 명시
- **일치 여부**: ❌ **불일치** — `72f459f` ≠ `5ed7267b7`
  - 이유: GitHub의 `3.7.0` 태그가 이미 업데이트됐거나(force-push), 운영 이미지가 3.7.0 태그 이전의 커밋을 base로 빌드됐을 가능성. 추가 fetch는 지시에 따라 하지 않음.
  - **이후 정찰은 3.7.0 태그(HEAD=72f459f) 기준으로 진행**.

---

## 1. RoadClass enum

**파일**: `valhalla/baldr/graphconstants.h:131-141`

```cpp
// Road class or importance of an edge
enum class RoadClass : uint8_t {
  kMotorway    = 0,
  kTrunk       = 1,
  kPrimary     = 2,
  kSecondary   = 3,
  kTertiary    = 4,
  kUnclassified = 5,
  kResidential = 6,
  kServiceOther = 7,
  kInvalid     = 8, // only 3 bits in DE for road class
};
```

**enum 값 정리표**:

| 멤버명 | 정수값 | OSM highway= 대응 | 앱 class_factors 키 매핑 |
|--------|--------|------------------|------------------------|
| kMotorway | 0 | motorway | "1" (FC1) |
| kTrunk | 1 | trunk | "1" (FC1) ← ⚠️추측: FC2와 합칠지 분리할지 설계 결정 필요 |
| kPrimary | 2 | primary | "2" (FC2) |
| kSecondary | 3 | secondary | "3" (FC3) |
| kTertiary | 4 | tertiary | "4" (FC4) |
| kUnclassified | 5 | unclassified | "5" (FC5) |
| kResidential | 6 | residential | "5" (FC5) |
| kServiceOther | 7 | service/track | "5" (FC5) |

> ⚠️ 앱의 class_factors 키 "1"~"5"(5단계)와 RoadClass enum 멤버(8개)는 1:1 대응이 아님.
> 매핑 설계가 구현 단계에서 확정 필요 (현재 앱 docs의 FC1~5 매핑이 이 enum과 정확히 일치한다는 보장 없음).

**`classification()` 접근자** — `valhalla/baldr/directededge.h:696-698`:

```cpp
RoadClass classification() const {
  return static_cast<RoadClass>(classification_);
}
```

내부 저장: `uint64_t classification_ : 3;` — `directededge.h:1235` (3비트, 0~7 = 8개 값)

**EdgeCost에서의 참조** — `src/sif/motorcyclecost.cc:428`:
```cpp
highway_factor_ * kHighwayFactor[static_cast<uint32_t>(edge->classification())]
```
`edge->classification()`은 EdgeCost 본문에서 이미 사용 중. **패치 주입점으로 직접 활용 가능**.

---

## 2. proto 패턴

**파일**: `proto/descriptors/options.proto`

**`Costing.Options` 메시지 위치**: `options.proto:137`

**기존 factor 필드 선언 (verbatim)**:

```protobuf
// options.proto — Costing.Options 내부
oneof has_use_highways {
  float use_highways = 13;         // L174-175
}
oneof has_top_speed {
  float top_speed = 30;            // L225-226
}
oneof has_use_tracks {
  float use_tracks = 66;           // L307-308
}
oneof has_use_living_streets {
  float use_living_streets = 68;   // L313-314
}
```

**`map<>` 타입 기존 사용 사례**:

```protobuf
map<uint32, HierarchyLimits> hierarchy_limits = 92;  // L351
```
`Costing.Options` 내에 이미 `map<uint32, ...>` 필드가 사용 중 → `map<uint32, float>` 타입 추가에 proto 수준 제약 없음.

**Costing.Options의 마지막 필드 번호**: `96` (`multimodal_start_end_max_distance = 96`, `options.proto:358`)

→ **새 `class_factors` 필드는 97번부터 사용 가능**.

**`urban_penalty`와 `class_factors` 존재 여부**:
- 양쪽 모두 `proto/descriptors/options.proto`에 **없음** (grep 결과 0 hits)
- `src/sif/` 전체에도 **없음** (grep 결과 0 hits)
- **결론**: 앱이 보내는 `class_factors`와 `urban_penalty`는 스톡 3.7.0에서 완전히 무시됨. 포크 패치가 이 필드들을 추가해야 함.

---

## 3. motorcycle costing

**파일**: `src/sif/motorcyclecost.cc` (797줄), 독립 구현 — AutoCost를 상속하지 않음.

```
class MotorcycleCost : public DynamicCost  // motorcyclecost.cc:100
```

### 옵션 파싱부 (`ParseMotorcycleCostOptions`) — `motorcyclecost.cc:588-604`

```cpp
void ParseMotorcycleCostOptions(const rapidjson::Document& doc,
                                const std::string& costing_options_key,
                                Costing* c,
                                google::protobuf::RepeatedPtrField<CodedDescription>& warnings) {
  c->set_type(Costing::motorcycle);
  c->set_name(Costing_Enum_Name(c->type()));
  auto* co = c->mutable_options();

  rapidjson::Value dummy;
  const auto& json = rapidjson::get_child(doc, costing_options_key.c_str(), dummy);

  ParseBaseCostOptions(json, c, kBaseCostOptsConfig, warnings);  // use_tracks, use_living_streets 포함
  JSON_PBF_RANGED_DEFAULT(co, kUseHighwaysRange, json, "/use_highways", use_highways, warnings);
  JSON_PBF_RANGED_DEFAULT(co, kUseTollsRange,    json, "/use_tolls",    use_tolls,    warnings);
  JSON_PBF_RANGED_DEFAULT(co, kUseTrailsRange,   json, "/use_trails",   use_trails,   warnings);
  JSON_PBF_RANGED_DEFAULT(co, kMotorcycleSpeedRange, json, "/top_speed", top_speed,   warnings);
}
```

**`use_tracks`, `use_living_streets` 파싱 위치**: `ParseBaseCostOptions()` 내부 (`dynamiccost.cc:586-591`)

```cpp
// dynamiccost.cc:586-591
JSON_PBF_RANGED_DEFAULT(co, cfg.use_tracks_, json, "/use_tracks", use_tracks, warnings);
JSON_PBF_RANGED_DEFAULT(co, cfg.use_living_streets_, json, "/use_living_streets",
                        use_living_streets, warnings);
```

**JSON → proto 파싱 매크로 패턴** (`dynamiccost.h:42-58`):
```cpp
#define JSON_PBF_RANGED_DEFAULT(costing_options, range, json, json_key, option_name, warnings)
// 1. rapidjson에서 json_key로 float 취득 (없으면 range.def 사용)
// 2. range() 함수로 min/max 범위 클램프
// 3. costing_options->set_##option_name(clamped_value) 로 proto에 저장
```

→ **패치 지점 ①**: `ParseMotorcycleCostOptions()`에 `class_factors` 파싱 코드 추가.  
패턴: `rapidjson`으로 `/class_factors` 오브젝트를 읽어 `map<uint32, float>`를 순회 → proto 필드에 저장.

### `EdgeCost()` 함수 — `motorcyclecost.cc:403-450`

**시그니처**:
```cpp
Cost MotorcycleCost::EdgeCost(const baldr::DirectedEdge* edge,
                              const baldr::GraphId& edgeid,
                              const graph_tile_ptr& tile,
                              const baldr::TimeInfo& time_info,
                              uint8_t& flow_sources) const
```

**비용 계산 핵심 부분** (`motorcyclecost.cc:427-449`):
```cpp
float factor = kDensityFactor[edge->density()] +
               highway_factor_ * kHighwayFactor[static_cast<uint32_t>(edge->classification())] +  // L428
               surface_factor_ * kSurfaceFactor[static_cast<uint32_t>(edge->surface())];           // L429
factor += SpeedPenalty(edge, tile, time_info, flow_sources, edge_speed);
if (edge->toll()) {
  factor += toll_factor_;
}
if (edge->use() == Use::kTrack) {
  factor *= track_factor_;        // L436
} else if (edge->use() == Use::kLivingStreet) {
  factor *= living_street_factor_; // L438
} else if (edge->use() == Use::kServiceRoad) {
  factor *= service_factor_;
}
// ...
factor *= EdgeFactor(edgeid);
return {sec * factor, sec};       // L449
```

**`edge->classification()` 사용**: L428에서 이미 `kHighwayFactor[classification()]`로 참조 중.

**`class_factor` 주입 후보 지점**: L447 (`factor *= EdgeFactor(edgeid);`) 바로 앞.
```cpp
// 주입 후보 (패치 지점 ②):
uint32_t rc = static_cast<uint32_t>(edge->classification());
if (class_factors_.count(rc)) {
  factor *= class_factors_[rc];
}
factor *= EdgeFactor(edgeid);
```

`kHighwayFactor` 배열(`motorcyclecost.cc:60-68`)이 이미 classification을 인덱스로 사용하므로, 같은 패턴으로 배열 또는 맵 조회가 가능.

### `EdgeCost` 오버라이드 여부

`MotorcycleCost::EdgeCost`는 **오버라이드됨** — `motorcyclecost.cc:203-207`에 선언, `motorcyclecost.cc:403`에 구현.  
AutoCost의 `EdgeCost`를 상속하지 않음 (독립 구현). DynamicCost의 transit EdgeCost만 throw로 오버라이드.

---

## 4. 빌드 경로

**공식 Dockerfile 위치**: `docker/Dockerfile` (2스테이지 빌드)

**빌드 핵심 줄** — `docker/Dockerfile:47-50`:
```dockerfile
FROM ubuntu:24.04 AS builder                              # L1
RUN cmake -B build -DCMAKE_BUILD_TYPE=${BUILD_TYPE-"Release"} \
  -DCMAKE_C_COMPILER=gcc -DENABLE_TESTS=Off \
  -DENABLE_SINGLE_FILES_WERROR=Off \
  -DVALHALLA_VERSION_MODIFIER=${VERSION_MODIFIER} \
  -DINSTALL_TEST_LIB=${INSTALL_TEST_LIB:-"Off"} && \
  make -C build all ${ADDITIONAL_TARGETS} -j${CONCURRENCY:-$(nproc)} && \
  make -C build install                                   # L47-50
FROM ubuntu:24.04 AS runner                               # L68
COPY --from=builder /usr/local /usr/local                 # L89
```

**`valhalla_service` CMake 타깃** — `CMakeLists.txt:295-316`:
```cmake
set(valhalla_programs
    valhalla_export_edges valhalla_expand_bounding_box valhalla_service)  # L295-296
# ...
if(ENABLE_TOOLS)
  foreach(program ${valhalla_programs})
    get_source_path(path ${program})
    add_executable(${program} ${path})              # L310
    target_link_libraries(${program} valhalla ...)  # L313
    install(TARGETS ${program} DESTINATION ...)     # L315
  endforeach()
endif()
```

소스 경로는 `get_source_path()`로 자동 탐색 (보통 `src/valhalla_service.cc`).

---

## 5. 종합

### ✅ 패치 3지점 확정

| 지점 | 파일 | 위치 | 작업 |
|------|------|------|------|
| **① proto 필드 추가** | `proto/descriptors/options.proto` | `Costing.Options` 마지막 필드 96 다음 (97번) | `map<uint32, float> class_factors = 97;` 추가 |
| **② JSON 파싱 추가** | `src/sif/motorcyclecost.cc` | `ParseMotorcycleCostOptions()` L599 이후 | JSON `/class_factors` 오브젝트 순회 → proto map 저장 |
| **③ EdgeCost 주입** | `src/sif/motorcyclecost.cc` | `EdgeCost()` L447 (`factor *= EdgeFactor(...)` 직전) | `class_factors_[edge->classification()]` 배수 곱셈 |

### ❓ 미확인

1. **운영 이미지 정확한 베이스 커밋**: `5ed7267b7`이 `72f459f`와 어떻게 다른지 확인 불가 (fetch 금지). 두 커밋 간 `motorcyclecost.cc` 변경이 있을 수 있음 — 실제 패치 전 운영 이미지 소스를 확인하는 것이 안전.
2. **`urban_penalty` 구현 여부**: 앱이 보내지만 소스에 없음. 포크 패치에 포함할지 결정 필요.
3. **`hierarchy_limits = 92` proto 필드의 map 직렬화 패턴**: `class_factors`를 `map<uint32, float>`로 추가 시 C++ protobuf API(`mutable_class_factors()`, `(*co->mutable_class_factors())[key] = val`) 사용 방법 — 소스에서 `hierarchy_limits` 파싱 코드를 참고해야 하나 이번 정찰에서 미확인.

### 🔧 다음 단계(구현 설계)에서 결정할 것

1. **`class_factors` proto 타입 선택**: `map<uint32, float> = 97` (HierarchyLimits 패턴 답습) vs `repeated ClassFactor` 메시지. map이 JSON `{"1": 100.0}` 형식과 자연스럽게 매핑되므로 map 권장.

2. **FC 1~5 → RoadClass enum 매핑 확정**: 앱은 키 "1"~"5"를 쓰지만 RoadClass는 0~7의 8단계. 패치에서는 앱 키 숫자를 uint32로 그대로 받아 내부에서 다음 매핑 적용 필요:
   - `"1"` → kMotorway(0) + kTrunk(1)
   - `"2"` → kPrimary(2)
   - `"3"` → kSecondary(3)
   - `"4"` → kTertiary(4)
   - `"5"` → kUnclassified(5) + kResidential(6) + kServiceOther(7)
   → 또는 키를 RoadClass 정수값(0~7) 직접으로 변경해 앱 측 수정.

3. **`EdgeCost` 주입 위치 1곳 최종 확정**: L428의 `highway_factor_ * kHighwayFactor[classification()]` 항에 `class_factors` 배수를 곱하는 방식(기존 highway 가중치에 추가) vs L447 `EdgeFactor(edgeid)` 직전 독립 배수(완전 독립 제어). 독립 배수 방식이 기존 highway_factor 로직과 분리돼 예측 가능성이 높음.
