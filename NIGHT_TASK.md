# NIGHT_TASK (3번째 밤, 자정~05:00) — 폰 연결 마무리 + 후속 큐

> 너는 오케스트레이터다. CLAUDE.md 와 이 파일을 읽고, 절대 규칙을 지키며
> **모듈 0 → 1 → 2 → 3** 순서로 진행하라. 코딩은 flutter-coder/rust-coder,
> 검사는 code-auditor 에게 위임하라.
> **각 모듈 시작 전 체크포인트 커밋, PASS 후 커밋.** 막히면 멈추고 MORNING_REPORT.md 에 적어라.
> 사용자는 현장 복귀로 자리에 없다. 절대 범위를 넘지 마라. 추측으로 진행 금지.

---

## 전제 (이미 확정된 사실 — 다시 진단하지 마라)
- 라우팅 주소가 내부망인 `192.168.0.57`로 박혀 있어 폰에서 접속 불가였다. 이게 "경로를 불러오지 못했습니다"의 원인.
- 해결책: Tailscale MagicDNS 호스트명 `westinx.tail2172f6.ts.net` 사용.
- 서버 검증 완료: `http://westinx.tail2172f6.ts.net:8002`(Valhalla, 393.588km/대안2개),
  `http://westinx.tail2172f6.ts.net:8003`(Rust, health ok) **둘 다 외부에서 응답 정상.**
- 서버 바인딩 `0.0.0.0` 확인됨. 폰 Tailscale 온라인 확인됨.
- Android cleartext(평문 HTTP) 설정이 **전혀 없음** → 이것 때문에 폰에서 http 호출이 차단됨.
- 수정 대상 파일:
  - `lib/services/routing_service.dart` (현재 `http://192.168.0.57:8002`)
  - `lib/services/native_engine.dart` (현재 `http://192.168.0.57:8003`)

---

## 모듈 0 — 라우팅 주소를 MagicDNS로 교체 (최우선, 작음)
**목표:** localhost → `westinx.tail2172f6.ts.net` 로 두 파일 수정.

할 일:
1. 시작 전 체크포인트 커밋 (`git add -A && git commit -m "checkpoint: before module 0"` — 변경 없으면 생략).
2. 아래 2개 치환 수행:
   - `routing_service.dart`: `http://localhost:8002` → `http://westinx.tail2172f6.ts.net:8002`
   - `native_engine.dart`: `http://localhost:8003` → `http://westinx.tail2172f6.ts.net:8003`
3. `grep -rn "localhost:800" lib/` 로 **남은 localhost가 없는지** 확인. 있으면 다 바꿔라.
4. 하드코딩이 걸리지만, 이번엔 동작 우선이므로 호스트명 상수는 그대로 둔다.
   단, MORNING_REPORT 에 "추후 .env 로 빼는 게 좋다"고 1줄 남겨라.

완료 기준: 두 파일에 localhost가 없고 MagicDNS 호스트명만 남음. `flutter analyze` 통과.
건드리지 말 것: 라우팅 로직, 포트 번호, 그 외 파일.

---

## 모듈 1 — Android cleartext 허용 (이게 안 되면 폰 연결 실패 지속)
**목표:** `.ts.net` 도메인에만 평문 HTTP를 허용하는 network security config 추가.

할 일:
1. 체크포인트 커밋.
2. 폴더/파일 생성: `android/app/src/main/res/xml/network_security_config.xml`
   내용:
   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <network-security-config>
       <domain-config cleartextTrafficPermitted="true">
           <domain includeSubdomains="true">ts.net</domain>
       </domain-config>
   </network-security-config>
   ```
3. **`android/app/src/main/AndroidManifest.xml` 을 먼저 READ 하라.**
   `<application ...>` 태그를 찾아서, 그 태그에 속성 하나를 추가하라:
   `android:networkSecurityConfig="@xml/network_security_config"`
   - **주의:** 기존 `<application>` 속성(android:label, android:icon 등)을 절대 삭제·변경하지 마라.
     속성 하나만 **추가**하는 것이다. 매니페스트 XML 문법이 깨지지 않게 정확히 편집하라.
   - 편집 후 매니페스트 전체를 다시 READ 해서 태그가 올바른지 육안 확인하라.
4. 만약 `<application>` 에 이미 `networkSecurityConfig` 가 있으면 → 건드리지 말고 보고만 하라.

완료 기준: xml 파일 존재 + 매니페스트에 속성 1개 추가 + 매니페스트 XML 유효.
건드리지 말 것: 매니페스트의 권한(uses-permission), activity, 기타 기존 속성.

---

## 모듈 2 — 빌드 & 정적 검증 (실제 폰 설치는 사용자가 아침에)
**목표:** 위 수정으로 앱이 정상 빌드되는지까지 확인. (실기기 설치·실행은 사용자 몫)

할 일:
1. `flutter clean`
2. `flutter analyze` → 0 issues 확인.
3. `flutter build apk --debug` → 빌드 성공 확인.
   - APK 경로: `build/app/outputs/flutter-apk/app-debug.apk`
   - 빌드 실패 시: 에러 원문을 MORNING_REPORT 에 그대로 붙이고, 원인 추정까지만 적어라.
     **3회 시도 후에도 실패하면 멈춰라.** 다른 걸 임의로 고치지 마라.
4. 성공 시 커밋: `feat: phone connectivity via tailscale magicdns + android cleartext config`

완료 기준: analyze 0 issues + APK 빌드 성공 + 커밋 완료.
건드리지 말 것: 빌드 실패해도 라우팅 로직/UI 로직을 임의 수정하지 마라. 보고만.

---

## 모듈 3 — (시간 남으면) 내비게이션 화면 버그 조사 — **조사만, 수정 금지**
**목표:** 사용자가 보고한 내비 화면 버그 3건의 **원인 위치를 코드에서 찾아 보고서에 정리**.
이번 밤엔 **고치지 마라.** 잘못 고치면 동작하는 내비까지 깨질 위험이 크다. 원인 파악까지만.

사용자 보고 버그:
1. 내비 실행 시 화면이 **출발지(내 위치)가 아니라 목적지** 중심으로 뜬다.
2. **현위치 버튼**을 눌러도 현위치로 안 돌아온다.
3. 카드 거리(예: 54~83km)와 내비 거리(23.4km)가 **다르다**
   → 내비 화면이 카드와 **다른 경로 소스**를 쓰는지 의심. (예: 아직 OSRM 잔재? 별도 호출?)

할 일 (READ-ONLY 조사):
1. `lib/features/navigation/` 와 `lib/screens/driving_screen.dart` 를 읽어라.
2. 각 버그의 원인으로 의심되는 **파일명:줄번호** 와 짧은 설명을 보고서에 적어라.
3. 특히 버그 3: 내비 화면이 어떤 경로를 받아 쓰는지(카드에서 넘겨받는지, 자체 호출하는지) 추적해 적어라.
4. **코드를 수정하지 마라. 커밋도 만들지 마라.** 순수 조사.

완료 기준: 3개 버그 각각에 대해 "의심 위치 + 이유"가 보고서에 정리됨.

---

## 멈춤/한도 대응
- 한도로 멈출 것 같으면 **반드시 "깨끗한 커밋 직후"에 멈춰라.**
- 모듈 0·1·2 가 진짜 목표다. **모듈 0·1 을 무조건 끝내라** (폰 연결 복구).
- 모듈 2 빌드가 3회 실패하면 멈추고 보고. 모듈 3은 시간/토큰 남을 때만.

## 아침 보고서 (MORNING_REPORT.md) — 반드시 한국어, 비개발자용
1. 완료 모듈 + 각 커밋 해시.
2. 완료 기준 체크 결과(모듈별 체크리스트 그대로).
3. 막힌 것/건너뛴 것 + 이유 (빌드 에러는 원문 포함).
4. **사용자가 아침에 직접 할 일** (순서대로):
   - APK 를 폰으로 옮겨 설치하는 법, 또는 `flutter run -d <기기>` 안내.
   - 폰에서 확인할 것: "목적지 찍으면 경로 선 3개가 지도에 그려지는가",
     "카드 거리와 지도 선이 일치하는가".
5. 모듈 3 조사 결과 (내비 버그 3건의 의심 위치) — 다음 밤 수정 후보.
6. 토큰/한도 메모.
7. 전문용어는 풀어서.

## 시작 지시 (오케스트레이터 첫 프롬프트로 줄 것)
> CLAUDE.md 와 이 NIGHT_TASK.md 를 읽어라. 너는 오케스트레이터다.
> 모듈 0 → 1 → 2 → 3 순서로, 절대 규칙을 지키며 진행하라.
> 모듈 0·1(폰 연결 복구)을 최우선으로 반드시 끝내라.
> 각 모듈: 체크포인트 커밋 → 위임 → 검증 → 감사 → PASS면 커밋 → 다음.
> 모듈 3은 조사만 하고 코드를 고치지 마라.
> 멈출 땐 깨끗한 커밋 직후에 멈추고 MORNING_REPORT.md 를 써라.
> 범위 밖은 건드리지 마라. 막히면 멈추고 보고서에 적어라. push 는 하지 마라.
