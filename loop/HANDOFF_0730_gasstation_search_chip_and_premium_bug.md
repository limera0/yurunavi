GOAL: 지도 검색창(주변 탐색)에서 "주유소" 단독 선택 시 오피넷 가격순 목록으로 전환 + 고급휘발유(B034) 가격이 전부 99,999원으로 나오는 버그 수정

이 파일을 읽는 Claude는 아래 계획을 순서대로 실행한다.
**코딩 전에 반드시 이 파일 전체를 읽어라.**

---

## 관계 문서

- 19번(실시간 최저가 주유소 안내) — `loop/RELEASE_ROADMAP.md` 19번 섹션(DONE 처리됨, 이 작업은
  그 후속 확장 + 버그픽스)
- 기존 구현: `native/src/main.rs`(`/gasstations/nearby`), `lib/services/gas_station_service.dart`,
  `lib/features/navigation/presentation/nav_screen.dart`(`_GasStationSheet`)

## 절대 규칙 — 위반 금지 (캐리오버)

- `git push` 금지.
- `git add -A` / `git add .` 금지 — named files만.

---

## Phase A — 고급휘발유 99999 센티널 버그 수정 (먼저 진행, 우선순위 높음)

### 원인 (2026-07-30 세션에서 확정)

마스터가 "고급휘발유 가격이 전부 99,999원으로 나온다"고 리포트. `native/src/main.rs`의
`parse_opinet_price()`(1195줄)를 조사한 결과:

```rust
fn parse_opinet_price(v: &serde_json::Value) -> Option<i32> {
    v.as_str()?.trim().parse::<i32>().ok().filter(|&p| p > 0)
}
```

`p > 0`만 걸러서 유효한 가격으로 취급한다. 그런데 **오피넷 원본 API 자체가 고급휘발유(B034)를
취급하지 않는 주유소에 대해 `B034_P` 필드에 리터럴 문자열 `"99999"`를 반환**한다 — "해당없음"을
뜻하는 자체 센티널 값인데, 현재 파서가 이걸 진짜 가격(99,999원/L)으로 통과시켜버리는 게 원인.

**실측 확인(이 세션에서 직접 오피넷 원본 엔드포인트 curl)**:
- 서울 중구(프리미엄 정상 취급 지역): `B034_P` 정상값 2369~3240 — 문제 없음.
- 경상북도 울릉군: 3개 주유소 전부 `B034_P: "99999"` (B027_P는 2059/2079/2079로 정상).
- 강원 정선군: 15개 중 확인된 것 전부 `B034_P: "99999"`.
- 경상북도 영양군: 7개 전부 `B034_P: "99999"`.

즉 **고급휘발유를 안 파는 지방 소형 주유소가 많은 지역일수록 99999가 광범위하게 나타남** —
마스터가 테스트한 지역이 이런 케이스였을 가능성이 높음. B027(일반휘발유)에선 이 패턴이
관찰되지 않았음(항상 정상 범위 가격).

### 수정

- `parse_opinet_price()`(`native/src/main.rs:1195`)에 99999 센티널 필터 추가:
  ```rust
  fn parse_opinet_price(v: &serde_json::Value) -> Option<i32> {
      v.as_str()?.trim().parse::<i32>().ok().filter(|&p| p > 0 && p != 99999)
  }
  ```
  (B027/B034 공용 함수라 양쪽에 다 적용해도 안전 — 실제 유가가 99,999원/L일 수는 없음)
- 단위테스트 추가: `parse_opinet_price`에 `"99999"` 입력 시 `None` 반환 확인, 정상값(`"2369"`)은
  `Some(2369)` 반환 확인.
- Flutter 쪽은 수정 불필요 — `nav_screen.dart:2660`에 이미 `displayPrice == null`일 때
  "정보 없음" 렌더링이 있음. 서버가 `premium_price: null`을 내려주기만 하면 자동으로 해결됨.

**완료 기준**:
- [ ] `parse_opinet_price` 단위테스트 통과 (99999 → None, 정상값 → Some)
- [ ] `cargo test` 전체 PASS
- [ ] code-auditor PASS
- [ ] 운영 navi 컨테이너 재빌드·재기동 (이 수정은 서버 코드라 배포해야 반영됨)
- [ ] 배포 후 curl로 재검증: `curl ".../gasstations/nearby?lat=37.4837&lon=130.9057&fuel=B034"`
  (울릉군 좌표 근사치, 정확한 좌표는 실제 울릉 지역 아무 지점) → `premium_price`가 `null`로
  나오는지 확인 (원본 오피넷 자체는 여전히 99999를 주지만 우리 서버가 걸러내야 함)
- [ ] 실기기에서 고급휘발유 토글 시 프리미엄 미취급 지역은 "정보 없음"으로 표시되는지 확인

---

## Phase B — 지도 검색창(_PlacesSheet) "주유소" 단독 선택 시 오피넷 경로 전환

### 배경

마스터 결정(2026-07-30): 지도 검색창(`main_map_screen.dart`의 `_PlacesSheet`, "주변 탐색" 시트)
카테고리 필터칩(`PoiType.values` 5종 — 카페/편의점/주유소/마트/식당)은 현재 전부
소상공인진흥공단 벌크 데이터(`/poi/nearby`) 기반이라 가격 정보가 없음. 오피넷(가격 있음)과
소상공인 DB는 서로 다른 사업자 ID 체계라 매칭 방식으로 합치는 건 오매칭 위험이 커서
권장하지 않음(2026-07-30 세션 결론).

**대신**: "주유소" 카테고리 **하나만 단독 선택**된 상태일 때는 기존 `/poi/nearby` 대신 이미
동작 중인 `GasStationService.fetchNearby()`(오피넷 경유)를 호출해서 가격순 목록을 보여준다.
다른 카테고리와 같이 선택돼 있으면(또는 주유소가 선택 안 돼 있으면) 지금처럼
소상공인 DB 기반으로 동작 — 이 경우엔 가격 없이 그대로 둔다.

### 작업 범위

- 대상 파일: `lib/features/map/presentation/main_map_screen.dart`의 `_PlacesSheet`
  (카테고리 필터 칩·`_selectedTypes` Set·목록 렌더링 부분, 3160줄대~)
- 분기 조건: `_selectedTypes.length == 1 && _selectedTypes.single == PoiType.gasStation`
  일 때만 오피넷 경로. 그 외엔 기존 로직 그대로 — **기존 5종 통합 리스트 렌더링을 건드리지
  말고, 이 특수 케이스만 별도 분기로 추가**(최소 침습).
- 오피넷 분기일 때 리스트 아이템: `nav_screen.dart`의 `_GasStationSheet` 리스트 아이템
  (`ListTile` + 순번 + 이름/거리/브랜드 + 가격) 스타일을 그대로 재사용하거나 공용 위젯으로
  추출해서 씀 — 새로 디자인하지 말 것([[feedback_prefer_simple_reuse]] 원칙, 메모리 참고 불가시
  그냥 기존 패턴 재사용이라고 이해하면 됨).
- 유종 선택 UI: 스코프 최소화 — 기본 휘발유(B027) 고정으로 우선 구현. 토글칩까지 넣을지는
  이 Phase B 완료 후 마스터 확인.
- 목적지/경유지 설정 흐름: `_PlacesSheet`가 이미 갖고 있는 기존 선택 콜백 구조를 그대로 타도록
  구현(정확한 콜백 시그니처는 coder가 파일 읽고 파악할 것 — 여기서 임의로 가정하지 않음).

**완료 기준**:
- [ ] `flutter analyze` PASS
- [ ] 지도 검색창에서 "주유소" 칩만 켰을 때 오피넷 가격순 목록 표시, 다른 칩과 같이 켰을 때는
  기존 소상공인 DB 기반 목록(가격 없음) 그대로 유지되는지 실기기 확인
- [ ] code-auditor PASS

---

## 실행 순서 (CLAUDE.md 표준 루프)

```
Phase A (99999 버그) → rust-coder → code-auditor → 컨테이너 재배포·재검증 → 커밋
Phase B (검색창 전환) → flutter-coder → code-auditor → 실기기 확인 → 커밋
```

Phase A를 먼저 끝내고 커밋한 뒤 Phase B로 넘어갈 것 — 서로 독립적인 변경이라 순서를 바꿔도
무방하지만, 버그픽스가 더 급함.

---

## 건드리지 말아야 할 것

- `git push`
- 소상공인 DB(`/poi/nearby`) 경로의 기존 5종 통합 렌더링 로직 — 오피넷 분기는 완전히 별도
  경로로 얹을 것, 기존 코드를 리팩터링하지 말 것.
