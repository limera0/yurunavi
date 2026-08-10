GOAL: 검색 UX 3종 구현 — 최근 검색 이력 표시 + 주소/POI 통합 검색 + 거리순 정렬

- 작성 2026-08-10 · 근거: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S16 (781~785행)
- 마스터 확인 완료(2026-08-10):
  - **S16 착수 전 RECON 선행 — 이미 이 파일에 결과 포함 (§0 참조)**

## §0. RECON 결과 (2026-08-10 조사)

### 기존 저장 인프라
- `SharedPreferences` 의존성 이미 있음 (`shared_preferences: ^2.5.3`)
- `PlacesService` (`lib/services/places_service.dart`): SharedPreferences 래퍼
  - 즐겨찾기(`favorite_places_v1`), 최근경로(`recent_routes_v1`) 저장 패턴 이미 구현
  - `addRecent()`, `loadRecent()` 메서드 패턴 참조
- **검색 이력 전용 키 없음** → 신규 구현 필요 (`search_history_v1`)

### 현재 검색 코드 위치
| 파일 | 역할 |
|------|------|
| `lib/services/address_search_service.dart` | 주소 검색 (V-World 프록시 `navi.westinx.com/geocode/search`) |
| `lib/services/poi_service.dart` | POI 점포명 검색 (뷰포트 기반) |
| `lib/features/map/presentation/main_map_screen.dart` | 검색 입력/상태 관리 (`_SearchMode.business`/`_SearchMode.address`) |
| `lib/features/map/presentation/address_search_sheet.dart` | 경유지 검색 바텀시트 (메모리 임시, 저장 없음) |
| `lib/models/address_result.dart` | 주소+좌표 모델 (검색어 저장 안 함) |
| `lib/features/map/providers/map_providers.dart` | `recentRoutesProvider` — Riverpod 패턴 참고 |

### 판정
- ✅ 저장 패턴·인프라 재사용 가능
- ❌ 검색 이력 모델·저장 로직·UI 전부 신규 구현

---

## 구현 범위

### 청크 1 — 검색 이력 저장 레이어 (`PlacesService` 확장)

**`lib/services/places_service.dart`에 추가할 것:**

```dart
// 검색 이력 항목 모델 (saved_place.dart 같은 파일에 추가하거나 별도 파일)
class SearchHistoryItem {
  final String query;      // 검색어 또는 장소명
  final double? lat;       // 선택된 결과 좌표 (null=검색어만 저장)
  final double? lng;
  final String type;       // 'address' | 'poi'
  final DateTime timestamp;

  // toJson / fromJson
}
```

- 키: `'search_history_v1'`
- 최대 20건 유지 (초과 시 가장 오래된 것 제거)
- 메서드: `loadSearchHistory()`, `addSearchQuery(SearchHistoryItem)`, `clearSearchHistory()`
- Provider: `searchHistoryProvider` (Riverpod `AsyncNotifierProvider`)

### 청크 2 — 검색바 탭 → 최근 검색 리스트 UI

**`main_map_screen.dart` 검색 입력 영역:**
- 검색바 포커스 시 (텍스트 비어있을 때) `searchHistoryProvider`에서 최근 20건 목록 표시
- 각 항목 탭 → 검색어 자동 입력 or 저장된 좌표로 바로 목적지 설정
- 최근 검색 헤더 + "전체 삭제" 버튼

### 청크 3 — 통합 검색 (주소 + POI 병합)

현재 `_SearchMode.address` / `_SearchMode.business` 두 탭이 분리되어 있음.
**한 입력창에서 두 소스를 동시 쿼리해 병합 결과 표시:**

```dart
// 두 Future를 동시 실행
final results = await Future.wait([
  _addressService.search(query),  // V-World 프록시
  _poiService.searchByName(query, nearLat, nearLng),
]);
// 합쳐서 표시: 주소 결과 + POI 결과 (섹션 구분 또는 혼합)
```

- 사용자 입력 debounce 300ms 이후 동시 호출
- 로딩 인디케이터는 두 소스 중 하나라도 응답 전까지

### 청크 4 — 거리순 정렬 (POI 결과)

POI 검색 결과를 현재 GPS 위치 또는 지도 뷰포트 중심 기준 가까운 순 정렬:

```dart
double haversine(double lat1, double lng1, double lat2, double lng2) { ... }

results.sort((a, b) =>
  haversine(refLat, refLng, a.lat, a.lng)
    .compareTo(haversine(refLat, refLng, b.lat, b.lng))
);
```

- 기준점 우선순위: GPS 픽스 있으면 GPS 좌표, 없으면 지도 뷰포트 중심
- 외부 패키지 금지 — 직접 haversine 구현

---

## 코딩 지시사항

- `PlacesService` 확장 — 기존 `RecentRoute` 패턴 복제, 외부 패키지 추가 금지
- `SearchHistoryItem` 모델: `lib/models/` 또는 `places_service.dart` 내부에
- 검색 이력 provider: `map_providers.dart`에 `recentRoutesProvider` 옆에 추가
- UI는 `main_map_screen.dart` 검색 영역 안에 인라인으로 — 새 화면 금지
- 기존 `_SearchMode` enum 활용, 새 enum 추가 최소화
- `haversine()` 함수: 정적 유틸 (외부 패키지 불필요)

## 검증 체크리스트

- [ ] 검색어 입력 후 장소 선택 → 이력에 저장되는지 확인
- [ ] 검색바 탭 (빈 상태) → 최근 검색 목록 표시
- [ ] 이력 항목 탭 → 검색 실행
- [ ] "전체 삭제" 버튼 → 이력 초기화
- [ ] 통합 검색: 주소+POI 결과 한 화면에 표시
- [ ] POI 결과 거리순 정렬 확인 (GPS 픽스 상태에서)
- [ ] 앱 재시작 후 이력 유지 (SharedPreferences persist)
