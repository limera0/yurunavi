GOAL: S1b 백화의 남은 절반(속도계·일출일몰 내용물 소실)의 원인을 확정하고, 지도 퍽/핀 소실 가설(일회성 가드)을 실기기 계측으로 확정 또는 반증한다.

# HANDOFF — S1b 이어받기 (2회차, 조사 전용)

- 작성 2026-08-05 · 브랜치 `verify/ride-0711`
- **선행 세션 기록: [RECON_0805_render_resource.md](RECON_0805_render_resource.md) — 먼저 읽어라. 여기 있는 내용은 반복하지 않는다.**
- 1회차 지시서: [HANDOFF_0805_S1b_render_resource.md](HANDOFF_0805_S1b_render_resource.md)
- 대장: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) S1b

> **여전히 조사다. 원인 확정 전 수정 커밋 금지.** 조사용 임시 `debugPrint`는 허용하되
> 커밋하지 마라. 1회차 지시서 §3(하지 말 것)은 그대로 유효하다.

---

## 0. 1회차에서 확정된 것 (다시 조사하지 마라)

RECON에 전부 있다. 요약만:

1. **백화는 페인트 단계 손실이다.** 링 중심·반지름·알약 좌표가 코드 계산값과
   1px 이내로 일치 → 레이아웃은 완전 정상이었다. 제약 붕괴·PIP 지오메트리·
   ErrorWidget 전부 배제됨.
2. **트리거는 라이프사이클이다.** 알림창을 내린 것만으로
   `inactive` → `PIP enter ok` → `MissingPluginException(source#setGeoJson / camera#move)`가
   **실기기에서 재현됐다.** 프로덕션 로그 567건과 동일 시그니처.
3. **지도 플랫폼뷰가 파괴·재생성된다** (채널 ID `maplibre_gl_2`→`_4`).
4. **"파란 원만 남고 화살표만 소실"은 틀렸다.** 그 파란 원은 퍽이 아니다(색 불일치).
   퍽은 통째로 없다.
5. **`_locLayerReady`/`_destLayerReady`가 리셋되지 않는다** → 재생성 후 퍽·핀
   레이어가 영영 재설치되지 않는 코드 경로가 실재한다(경로선·POI는 가드가 없어 복구됨).
   증거 스크린샷의 지도 상태와 정확히 일치. **단, 실기 계측으로 확정하진 못했다.**
6. **PIP 1회 왕복으로는 영구 백화가 안 남았다** — 복귀 후 3요소 전부 정상 복귀.
7. Impeller 매니페스트 스위치는 Flutter 3.44에서 **여전히 유효**(§6). A/B 가능.
8. S2는 이미 완료. 타일 캐시 1.65GB 실측만 미측정으로 남아 있다.

---

## 1. 기기 상태 (그대로 이어서 쓰면 된다)

- 연결 기기: **SM-M325F(M32) · Android 13 · RAM 3.7GB · 1080×2400 · density 450**
  — A34가 아니다. 저사양 목표 조건에는 오히려 적합.
- 설치본: **현 HEAD 릴리스 빌드(S1+S2 적용)**. 기존 1.0.1 위에 `-r` 설치, **데이터 보존됨.**
- 권한: FINE/COARSE_LOCATION, POST_NOTIFICATIONS 부여 완료.
- `gpsinjector` 설치됨. CSV는 기기에 이미 있음
  (`/sdcard/Android/data/com.westinx.gpsinjector/files/`, 이번엔 `bgnav_route.csv` 365pt/약 6분 사용).
  ⚠️ **1회차 종료 시 목업 위치를 꺼두었다** — 마스터가 그 폰을 실제로 쓸 수 있으므로
  실측 GPS를 되돌려놓은 것이다. 재개하려면 먼저:
  ```bash
  adb shell appops set com.westinx.gpsinjector android:mock_location allow
  ```
  그리고 **세션 끝날 때 반드시 `... deny`로 되돌려라.**
- **주의**: 릴리스 키와 디버그 키가 달라 **debug APK 설치는 서명 충돌 → 데이터 삭제가 필요**하다.
  마스터 투어 히스토리·로그가 날아가므로 **마스터 승인 없이 uninstall 하지 마라.**
  E2E 인텐트 하네스(`--es e2e_dest_lat …`)는 `kDebugMode` 게이트라 릴리스에선 안 먹는다 →
  아래 §2처럼 adb 탭으로 몰아라.

### 내비 진입 재현 절차 (릴리스 빌드, 검증됨)

```bash
adb shell am force-stop com.westinx.gpsinjector
adb shell am start -n com.westinx.gpsinjector/.MainActivity \
    --es routefile bgnav_route.csv --ez autostart true
adb shell am start -n com.westinx.yurunavi/.MainActivity
sleep 15
adb shell input tap 950 1900     # 줌아웃 (필요 횟수만큼 반복)
adb shell input tap 210 516      # 지도 탭 → 선택 위치 시트
adb shell input tap 304 1974     # "여기로 안내"
sleep 12                          # 3코스 계산 대기
adb shell input swipe 156 2110 1000 2110 600   # Slide to Ride
```

### 자동 판정

```bash
adb exec-out screencap -p > shot.png
python3 loop/repro_s1b/detect_whiteout.py shot.png --screen 1080x2400 --density 450
```
베이스라인 정상값: 속도계 ink≈0.145 · 일출일몰 ink≈0.296 · 화살표 파랑 ≈2426px.

---

## 2. 이번 세션이 할 일 (우선순위 순)

### 2-1. PIP 왕복을 **반복**해 영구화 지점을 찾아라 (최우선)

1회 왕복으로는 안 남았다. 다음 축을 하나씩 늘려가며 매회 자동 판정하라.

- **반복 횟수**: 5 → 10 → 20회. 매회 캡처+판정, 몇 회째부터 안 돌아오는지 기록
- **체류 시간**: 프로덕션 실측은 **2분 16초**였다. 1회차는 수 초였다. 늘려라
- **트리거 종류별로 나눠 볼 것** — 마스터는 "하나만/두 개만/셋 다" 사라졌다고 했다.
  요소별로 다르게 깨진다면 트리거별 차이가 단서다:
  - `cmd statusbar expand-notifications` (검증됨)
  - `input keyevent KEYCODE_APP_SWITCH` (최근앱)
  - `input keyevent KEYCODE_HOME` (onUserLeaveHint → 정식 PIP 경로)
  - 스크린샷 촬영 자체 (`KEYCODE_SYSRQ`) — 증거물이 스크린샷이라는 점이 의미심장하다
- **복귀 방법도 변수다**: `am start`로 복귀 vs PIP 창 탭 후 최대화 —
  전자는 액티비티를 새로 띄우는 셈일 수 있다. **1회차의 화살표 2426→9230px 증가가
  이것 때문인지 확인하라** (퍽 레이어 중복 설치 의심)

### 2-2. §3 가드 가설을 직접 계측해 확정/반증하라

`nav_screen.dart`에 **임시** 로깅을 넣고 릴리스 빌드로 재현:

```dart
onMapCreated: (c) { debugPrint('YNAV_MAPDBG created ctrl=${identityHashCode(c)} '
    'loc=$_locLayerReady dest=$_destLayerReady style=$_styleLoaded'); _mlCtrl = c; },
// _onStyleLoaded() 진입부에도 동일 한 줄
```

- `onMapCreated`가 재호출되는가? 그때 `_locLayerReady`가 이미 true인가?
- true라면 §3 확정 — 퍽·핀은 영영 안 돌아온다
- **재호출 자체가 없다면** 가설은 틀렸다. 그때는 컨트롤러가 죽은 채로 남아 있다는
  뜻이므로 `MissingPluginException`이 복귀 후에도 계속 나는지 확인하라
- ⚠️ **이 로깅은 커밋하지 마라.** 조사 끝나면 되돌려라

### 2-3. 속도계·일출일몰 축 (미확정 절반)

이쪽은 아직 아무 메커니즘도 없다. 계측부터:

- PIP 전/중/후 **1초 간격 연속 캡처** → 언제 사라지고 언제 돌아오는지 시간축을 만들어라
- 동시 수집: `dumpsys gfxinfo com.westinx.yurunavi`, `dumpsys meminfo com.westinx.yurunavi`
  (Graphics/GL 항목), `logcat | grep -iE "vulkan|impeller|atlas|glyph|OutOfMemory|GL_OUT_OF_MEMORY|trim"`
- **판별 실험**: 지도 플랫폼뷰가 원인인지 가르려면 —
  코스 시트를 열어 지도 위 위젯 구성을 바꾸거나, 지도가 없는 화면(설정 등)을
  거쳐 돌아왔을 때도 같은 손실이 나는지 본다
- RECON §5에 적은 대로 **글꼴 아틀라스 단순 고갈 가설은 잘 안 맞는다**
  (같은 프레임에서 `Icons.add`/`Icons.remove`와 카드 텍스트는 정상 렌더).
  이 비대칭을 설명하지 못하는 가설은 채택하지 마라

### 2-4. 메모리 압박 축 (마스터 목표 수준)

마스터 지시: *"저사양 폰이든 플립처럼 백그라운드 점유가 큰 폰이든 안정 구동"*.
1회차는 압박을 전혀 걸지 않았다.

- `adb shell am send-trim-memory <pid> RUNNING_MODERATE|RUNNING_LOW|RUNNING_CRITICAL`
- 백그라운드 앱 다수 실행 후 동일 시나리오
- 앱에 `didHaveMemoryPressure()` 대응이 있는지 (1회차 미확인 — 없을 것으로 추정)
- 이미지 캐시(`PaintingBinding.instance.imageCache`) 상한이 기본값인지

### 2-5. Impeller A/B (재현이 안정된 뒤에)

매니페스트 meta-data로 끄고 동일 시나리오. **끄는 것 자체를 해결책으로 커밋하지 마라.**

### 2-6. 곁다리 — 실기기 붙은 김에

- **타일 캐시 1.65GB 실측 배분** (S2가 범위 밖으로 남긴 항목)
- S1의 미검증 항목: `wm size 720x748`로 커버화면 흉내 → 렌더 확인
  (**끝나면 `wm size reset` 필수**)

---

## 3. 산출물

1. `loop/RECON_0805_render_resource.md`에 **이어서** 기록 (새 파일 만들지 말 것)
2. 재현 스크립트를 `loop/repro_s1b/`에 축적 — 회귀 검증에서 재사용 가능한 형태로
3. `loop/MORNING_REPORT_0806_S1b_*.md` — `Goal: X / Met: yes·partial·no — reason` 한 줄 포함
4. **[관측]과 [추론]을 계속 분리 표기하라.** 이 건은 이미 두 번 판정이 뒤집혔다
   (S1이 백화 원인 → 픽셀 실측으로 반증 / "파란 원 = 퍽" → 색 실측으로 반증)

## 4. 커밋 규칙

- `git add -A` 금지. **다른 세션이 같은 브랜치에서 작업 중이다** (1회차 도중에도
  HEAD가 `71380de`→`bb7c4df`로 움직였다). 내 파일만 이름 지정해 스테이징하라
- 조사 산출물(RECON/HANDOFF/repro 스크립트)만 커밋. **앱 코드 수정은 커밋 금지**
