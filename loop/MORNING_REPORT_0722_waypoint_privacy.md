# MORNING REPORT — 경유지 관리 UI + 개인정보처리방침 호스팅 (2026-07-22)

Goal: 17번 경유지 관리 UI Phase 0~4 완료 + 6번 개인정보처리방침 호스팅 / Met: yes

---

## 완료 항목

### 17번 — 경유지 관리 UI (Phase 0~4 전부)

**Phase 0** — stops 통합 아키텍처 마이그레이션 (커밋 `08e0e94`)
- `lib/features/map/models/route_stop.dart` 신규: `RouteStop(latLng, name, isCurrentLocation)`
- `MapInteractionState`: `destination/waypoints/waypointNames` → `stops: List<RouteStop>` 통합
- 기존 getter 유지(origin/destination/waypoints/waypointNames) — 호출부 변경 없음
- `reorderStop()` 신규 메서드 + ReorderableListView 인덱스 보정 포함
- `setDestination(snapshotOrigin:)` — GPS 스냅샷 저장
- `flutter analyze` PASS, code-auditor PASS

**Phase 1** — 경유지 포인터 번호 표시 (커밋 `bb4b3ee`)
- `_syncWaypointMarkers()`: textField = 순서 번호(1,2,3), 흰색 텍스트, offset(-2.1)
- SymbolOptions에 textIgnorePlacement/textAllowOverlap 없음 확인 → 제거

**Phase 2** — WaypointManagementSheet (커밋 `26e5c4a`)
- `lib/features/map/presentation/waypoint_management_sheet.dart` 신규
- `DraggableScrollableSheet`(60%/90%/40%) + `ReorderableListView`
- reorder/remove 후 `RoutingService.fetchRoutes` 즉시 재호출
- code-auditor FAIL → `await` 이후 `mounted` 체크 누락 수정 → PASS

**Phase 3** — 검색 결과 출발지/경유지/목적지 선택 (커밋 `f6b021c`)
- `_AddToRouteSheet("어디로 추가할까요?")` showModalBottomSheet
- `setOrigin()` notifier 메서드 추가
- 경유지는 destination 설정 후 활성화

**Phase 4** — 코스 시트 진입점 UI (커밋 `43b5c31`)
- `CourseSheet`에 `waypointCount`/`onWaypointEntryTap` 파라미터 추가 (optional)
- 경유지 있으면 ActionChip, 없으면 TextButton

---

### 6번 — 개인정보처리방침 호스팅

- `navi.westinx.com/privacy` — Axum `/privacy` GET 라우트로 HTML 서빙 (커밋 `259360b`)
- `native/src/main.rs`에 `PRIVACY_HTML` const + `handle_privacy()` 핸들러 추가
- Docker 이미지 재빌드 + `--force-recreate` 배포
- 외부 `https://navi.westinx.com/privacy` 200 OK 확인
- RELEASE_ROADMAP 6번 DONE 갱신 (커밋 `ff36d6f`)

---

## 검증 상태
- `flutter analyze --no-fatal-infos`: PASS (No issues found)
- `cargo check --bin yurunavi_server`: PASS (76 tests pass)
- code-auditor: Phase 0/2/3/4 각 PASS (Phase 2는 1차 FAIL → 수정 후 PASS)
- git push 없음 (로컬 커밋만, CLAUDE.md 준수)

---

## 실기기 확인 권장
- `pointer_yellow` 아이콘 위 숫자 `textOffset(-2.1)` — 기기에서 원 중앙 맞는지 확인 후 미세조정

## 남은 릴리스 항목
- **8번** 브랜드 방향성 확정 (마스터 결정 필요)
- **9번** 앱 아이콘 확정 (8번 선행)
- **10번** release build 검증
- **11번** 하드코딩 스타일 → 토큰 리팩터 (8번 선행)
- **14번** Crashlytics 감사 B/D 남음 (콘솔 직접 확인 필요)
- **6번 별도 액션** 위치기반서비스사업 신고 여부 검토 (행정 절차, 자동화 불가)
