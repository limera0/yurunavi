# RECON N1: Valhalla costing — motorway/motorway_link 배제 여부

대상 파일: `lib/services/routing_service.dart`  
Rust/NativeEngine: winding score 계산 전용 — costing 결정에 관여 없음.

---

## class_factors 배치 현황 (4개 costing 세트 공통)

| 코스 세트 | 위치 | motorway('0') | trunk('1') |
|-----------|------|----------------|------------|
| 시골길 | routing_service.dart:156-165 | `'0': 100` | `'1': 100` |
| 지방도로 | routing_service.dart:177-186 | `'0': 100` | `'1': 100` |
| 국도 | routing_service.dart:199-208 | `'0': 100` | `'1': 100` |
| _ruralBalancedOpts | routing_service.dart:88-97 | `'0': 100` | `'1': 100` |

모든 코스에 `use_highways: 0.0`도 추가로 적용됨 (routing_service.dart:151, 173, 194, 86).

### class_factors 키↔도로 매핑 (Valhalla graphconstants.h 확인)

```
'0': motorway      (kMotorway — 고속도로)
'1': trunk         (자동차전용도로·고속화도로)
'2': primary       (일반국도)
'3': secondary     (지방도)
'4': tertiary      (시군도)
'5': unclassified  (소로)
'6': residential   (마을길)
'7': service       (농로·주차장 접근로)
```

출처: `/usr/local/include/valhalla/baldr/graphconstants.h` (컨테이너 내)
`{static_cast<uint8_t>(RoadClass::kMotorway), "motorway"}` 확인됨.

---

## motorway_link 전용 항목 여부

class_factors 키 8개(`'0'`~`'7'`) 중 **motorway_link 전용 키 없음.**

Valhalla에서 motorway_link(고속도로 램프·연결로)의 class_factor 처리:
- Valhalla 내부적으로 motorway_link는 `kMotorWayJunction`(node attribute) 또는
  링크 여부 플래그(`is_link`)로 처리되며, RoadClass는 상위 도로 클래스를 따름.
- class_factors `'0': 100` 설정이 motorway_link에도 간접 적용되나,
  **명시적 motorway_link 배제 로직(키·분기)은 routing_service.dart에 없음.**

---

## 배제 구현 방식 판정

**구현됨 (간접):** `use_highways: 0.0` + `class_factors '0': 100` 조합으로  
motorway(고속도로) 진입 비용을 최대치로 설정하여 사실상 배제.  
trunk(자동차전용) `'1': 100` 도 동일하게 배제.

**미구현:** motorway_link(램프·진입로) 전용 키·분기 없음.  
use_highways=0.0이 링크 포함 여부에 어느 범위까지 영향을 주는지는  
Valhalla motorcycle costing 내부 구현에 의존 (코드에서 별도 명시 없음).
