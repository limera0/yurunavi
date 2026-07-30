GOAL: Galaxy Z Flip류 좁은 화면에서 발생하는 RenderFlex overflow(Crashlytics fatal, F766N 80%)를 고쳐 화면 폭에 관계없이 정상 렌더링되게 한다

이 파일을 읽는 Claude는 아래 계획을 순서대로 실행한다.
**코딩 전에 반드시 이 파일 전체를 읽어라.**

---

## ⚠️ 선행 조건 — 착수 전 반드시 확인

**마스터가 진행 중인 화면 레이아웃/스킨/로고 최종 수정이 끝난 뒤에 착수할 것.**
이 작업은 기존 위젯의 Row 구조를 건드리는데, 레이아웃이 아직 유동적인 상태에서 먼저 손대면
같은 파일에서 충돌·재작업이 발생한다. 세션 시작 시 `git log`로 최근 커밋 중 스킨/레이아웃
관련 작업이 이미 마무리됐는지(또는 로드맵 10번 "실제 release build 검증" 착수 여부로 간접
확인) 먼저 확인하고, 아직 진행 중인 것 같으면 착수하지 말고 대기할 것.

---

## 관계 문서

- `loop/RELEASE_ROADMAP.md` 14번 섹션 "추가 발견 (2026-07-30, ... 별도 패턴, 재오픈)" —
  이번 건의 배경(기존 ListTile ink-splash 이슈와는 무관한 별개 크래시)

## 절대 규칙 — 위반 금지 (캐리오버)

- `git push` 금지.
- `git add -A` / `git add .` 금지 — named files만.

---

## 배경

Firebase Crashlytics에서 `RenderFlex overflowed by 186 pixels on the right`
(`DebugOverflowIndicatorMixin._reportOverflow` 경유) fatal이 2026-07-26(필드테스트일) 46건,
2026-07-29 2건, 총 49건 확인됨 — **80%가 F766N(갤럭시 Z 플립7)에서 발생**. 이 오버플로
페인팅 코드는 Flutter가 `assert()`로 감싸는 debug 전용 경로라 release 빌드에선 안 뜰
가능성이 있지만(기존 14번 ListTile 건과 동일한 패턴), 실제로 어딘가의 Row가 화면 폭을
186px 넘기는 건 진짜 레이아웃 버그이므로 release 여부와 무관하게 고쳐야 한다.

## 확정 원인 (2026-07-30 세션에서 특정)

`lib/features/navigation/presentation/nav_screen.dart:2564-2581` — `_GasStationSheet`
(주유소 바텀시트) 제목 Row:

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
  child: Row(
    children: [
      Icon(Icons.local_gas_station, color: cs.primary, size: 20),
      const SizedBox(width: 8),
      Text(
        '근처 최저가 주유소',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
      ),                                    // ← Expanded/Flexible 없음, overflow 처리 없음
      const Spacer(),
      _FuelChip(label: '휘발유', ...),
      const SizedBox(width: 6),
      _FuelChip(label: '고급휘발유', ...),   // ← 5글자, 폭이 큼
    ],
  ),
)
```

폭 계산: 좌우 패딩 40px + 아이콘 28px + 제목 텍스트(~170px, 9글자 볼드) + 칩 2개(~160px,
"고급휘발유"가 특히 넓음) = 최소 약 400px. 표준폭(~360dp) 화면에서도 빠듯한데, 폴드형 특유의
좁은 화면 폭이나 One UI 기본 폰트 스케일이 조금만 커져도 바로 넘친다.

**참고 — 같은 파일 안의 올바른 패턴**: 바로 아래 `_GasStationSelectionCard`(주유소 선택 후
하단 카드, 2718줄~)는 제목 Row에서 `Expanded`+`maxLines: 1`+`overflow: TextOverflow.ellipsis`를
정확히 쓰고 있다. 즉 이번 버그는 같은 파일에서 한쪽만 빠뜨린 실수 — 수정 시 이 카드의 패턴을
그대로 따라 하면 된다.

## 작업 내용

### 1. 확정 수정 — `_GasStationSheet` 제목 Row

- 제목 `Text('근처 최저가 주유소', ...)`를 `Expanded` + `maxLines: 1` +
  `overflow: TextOverflow.ellipsis`로 감쌀 것.
- `Spacer()` + 칩 2개 조합이 폭 부족 시 어떻게 반응할지 결정 필요 — 후보:
  (a) 제목을 `Expanded`로 우선 줄이는 것만으로 충분한지 먼저 확인,
  (b) 그래도 좁으면 칩 두 개를 `Wrap`으로 감싸 두 번째 줄로 넘어가게 하거나,
  (c) 칩 padding을 줄여 폭을 확보.
  좁은 화면 시뮬레이션(아래 검증 방법)으로 실제로 넘치는지 확인하면서 최소 변경으로 결정할 것.

### 2. 동일 패턴 전수 감사

`nav_screen.dart` 및 2026-07-22 이후 추가된 바텀시트/카드류(웨이포인트 관리 시트,
코스 시트, 스킨 선택 UI, `_GasStationSheet`가 있는 파일 전체 등)에서 같은 실수
(Row에 고정폭 Text/버튼/칩을 `Expanded`/`Flexible`/`overflow` 처리 없이 나열)가 더 있는지
grep 기반으로 훑을 것. 발견되면 같이 수정.

### 3. 검증 방법

실제 Flip 계열 기기가 없으므로, Flutter DevTools의 커스텀 디바이스 프리뷰 또는
`flutter run` 후 창 리사이즈로 **폭 340~360dp + 텍스트 스케일 1.15~1.3배** 조합을 재현해
오버플로 경고(노란/검정 줄무늬)가 뜨는지 확인 → 수정 후 같은 조건에서 사라지는지 재확인.

## 실행 순서 (CLAUDE.md 표준 루프)

```
1. 착수 전 선행조건(위 ⚠️) 확인
2. 원인 Row 수정 → flutter-coder
3. 동일 패턴 전수 감사 및 추가 수정 → flutter-coder
4. 좁은 폭 시뮬레이션 검증
5. code-auditor
6. flutter analyze PASS 확인 후 커밋
```

## 완료 기준

- [ ] `_GasStationSheet` 제목 Row가 좁은 폭(340~360dp)+텍스트 스케일 1.3배 조건에서 오버플로
  없이 정상 렌더링
- [ ] 동일 패턴 전수 감사 완료, 발견된 것 전부 수정
- [ ] `flutter analyze` PASS
- [ ] code-auditor PASS
- [ ] 로드맵 14번 섹션에 완료 기록 (커밋 해시 포함)

---

## 건드리지 말아야 할 것

- `git push`
- 선행조건 미충족 시(스킨/레이아웃 작업 진행 중) 착수 자체를 하지 말 것.
