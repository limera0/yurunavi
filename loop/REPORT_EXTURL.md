# REPORT_EXTURL — 타일서버 공개도메인 전환 완료

날짜: 2026-06-05  
작업자: Claude Sonnet 4.6  
커밋: 9b31cf8

---

## 0단계 게이트 판정

| 항목 | 판정 |
|------|------|
| JSON 내 `192.168.0.57` 등장 횟수 | **2곳** (L12 `url`, L24 `glyphs`) — 예상과 일치 |
| 교체 대상 | `http://192.168.0.57:8080` → `https://tiles.westinx.com` |
| XML 제거 블록 | `192.168.0.57` domain-config 블록 — 명확 |
| XML 보존 블록 | `ts.net` domain-config 블록 — 명확 |
| **GATE** | **PASS → 구현 진행** |

---

## 변경 diff

### assets/images/osm_liberty_yurunavi.json

```diff
-      "url": "http://192.168.0.57:8080/data/v3.json"
+      "url": "https://tiles.westinx.com/data/v3.json"

-  "glyphs": "http://192.168.0.57:8080/fonts/{fontstack}/{range}.pbf",
+  "glyphs": "https://tiles.westinx.com/fonts/{fontstack}/{range}.pbf",
```

### android/app/src/main/res/xml/network_security_config.xml

```diff
-    <domain-config cleartextTrafficPermitted="true">
-        <domain includeSubdomains="false">192.168.0.57</domain>
-    </domain-config>
```

---

## 검증 결과

| 단계 | 결과 |
|------|------|
| `grep 192.168.0.57` JSON | **0건** — 사라짐 확인 |
| `grep tiles.westinx.com` JSON | L12, L24 — 2곳 정상 교체 |
| XML `192.168.0.57` 블록 | **제거됨** |
| XML `ts.net` 블록 | **보존됨** |
| `flutter analyze` | **No issues found** |
| `flutter build apk --debug` | **✓ Built app-debug.apk** (23.7s) |

---

## 폰 실측 체크리스트 (★ 이번 작업의 목표 = LTE에서 지도 뜨는지)

```
[ ] APK 설치: adb install -r build/app/outputs/flutter-apk/app-debug.apk
[ ] 실내 WiFi에서 지도 타일 정상 로드 (회귀 없음)
[ ] 한글 라벨(글리프) 정상 표시
[ ] ★ WiFi 끄고 LTE로 지도 타일 로드 (= 야외 실측 가능해짐, 이번 작업의 목표)
[ ] 경로 탐색 정상 (valhalla.westinx.com — 기존 동작)
[ ] fun-score 표시 정상 (navi.westinx.com — 기존 동작)
```

### LTE에서 타일 안 뜰 경우 진단

```bash
# adb logcat 필터링
adb logcat | grep -iE "tiles.westinx|cleartext|ssl|tls|certificate|network"

# 예상 에러 유형별 대응
# "CLEARTEXT communication ... not permitted" → xml 변경이 APK에 반영 안 됨 (clean build 필요)
# "CERTIFICATE_VERIFY_FAILED" / SSL 에러 → Cloudflare 인증서 문제 (드물음)
# 타임아웃 → tiles.westinx.com 터널 미동작, 서버 측 확인 필요
```

### clean build 필요 시

```bash
flutter clean && flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

---

## 커밋 내역

```
8f3c417  checkpoint: before tiles domain switch (LAN->tiles.westinx.com)
9b31cf8  feat(map): 타일서버를 tiles.westinx.com(https)로 전환, 192.168.0.57 cleartext 예외 제거
```
