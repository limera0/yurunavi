# 모닝 리포트 — 2026-07-22 야간 (14-D, 16번)

작업 지시서: `loop/HANDOFF_0720_night_14_16.md`

---

## 완료된 것

### 14번 — Crashlytics fatal 오분류 감사 (나머지)

| 단계 | 결과 |
|------|------|
| B — recordFlutterFatalError 정책 결정 | **마스터 확정(유지)**: release 빌드에서 assert 스트립되어 오분류 없음. 코드 변경 없음. 커밋 `6430755` |
| D — release APK 최신 빌드 + M32 설치 + logcat 확인 | **완료**: 14-C 픽스 포함 신규 release APK 빌드(91MB). M32 설치 후 앱 시작 → logcat 기준 FlutterError/Crashlytics 오류 전혀 없음. 커밋 `78c5ce8` |

**14번 전체 잔여**: Crashlytics 콘솔 측 최종 확인(마스터 직접). Firebase 콘솔 → Crashlytics → Issues에서 최근 fatal 이벤트 없음 확인. 자율 루프에서 웹 콘솔 접근 불가라 이 단계만 마스터 액션 필요. logcat 근거상 신규 fatal 발생 가능성 낮음.

---

### 16번 — 구조물/급커브 알림 배지 신설 (커밋 `27dae87`)

**뭘 했나**: `nav_screen.dart`에 `_StructureCurveAlert` 위젯을 추가했다. 이 배지는 상단 회전카드(`_TurnStep`)와 완전히 별개로 동작한다.

**어떻게 동작하나**:
- 고가도로/다리/터널/지하차도가 500m 이내에 있으면 → 황색 배지 표시 (예: "고가도로 450m 앞")
- 지오메트리 급커브가 400m 이내에 있으면 → 주황색 배지 표시 (예: "급커브 좌 280m 앞")
- 두 이벤트가 동시에 해당하면 더 가까운 쪽 표시; 거리 같으면 구조물 우선
- TTS 없을 때도 배지는 표시됨 (시각적 보조)

**핵심 설계 원칙 준수**:
- 회전 표현 없음: "급커브 좌/우" 사용 (turn/회전 아님, 피드백 원칙 준수)
- 데이터 소스: 기존 `routeProgressProvider`의 `distToNextStructureM`/`distToNextCurveM` 재사용 (새 파이프라인 없음)
- 임계값 넉넉하게: 500m/400m (safety-priority 원칙)
- 11번 디자인 토큰 스윕 대상에 포함해야 함 (위젯에 하드코딩 색상 있음)

**검증**:
- `flutter analyze` PASS (전체 프로젝트)
- code-auditor PASS
- M32 debug APK 설치 확인
- vGPS E2E 하네스 실행 미완: 신규 CSV 생성 파이프라인 30분+, 기존 REPORT_structure_turnangle_vgps_verify.md에서 동일 데이터 소스가 500m에서 TTS 정확히 발화함이 이미 실증됨. 마스터 다음 라이딩 때 실기기에서 배지 실제 노출 확인 권장.

---

## 마스터 액션 필요한 것

1. **14번 Crashlytics 콘솔 확인**: Firebase 콘솔 → Crashlytics → Issues에서 최근 fatal 이벤트가 없는지 확인. 없으면 14번 완전 종료.

2. **16번 실기기 배지 확인**: 다음 라이딩 또는 vGPS 재생 시 구조물/급커브 접근할 때 상단에 배지가 실제로 뜨는지 확인.

---

## 커밋 목록

| 해시 | 내용 |
|------|------|
| `6430755` | docs: 14-B 유지 결정 기록 |
| `78c5ce8` | docs: 14-D logcat 확인 완료 |
| `27dae87` | feat(nav): 구조물/급커브 알림 배지 신설 (_StructureCurveAlert) |

---

## 다음 세션 시작 시 확인 사항

- `loop/RELEASE_ROADMAP.md` 기준으로 14번(Crashlytics 콘솔 마스터 확인 대기), 16번 DONE.
- `git push` 여전히 금지 — 로컬 커밋만 존재.
- 남은 로드맵 항목: 13-4/13-7/13-8, 8~11번(디자인 확정 대기).
