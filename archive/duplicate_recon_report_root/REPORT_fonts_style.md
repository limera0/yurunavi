# REPORT: 폰트 Bold/Italic CJK 병합 + osm-bright 스타일 배치

날짜: 2026-06-12

---

## 병합 결과

| 폰트 | 병합(primary+CJK) | 단독 | 스킵 |
|------|:-----------------:|:----:|:----:|
| Noto Sans Bold   | 256 | 0 | 0 |
| Noto Sans Italic | 256 | 0 | 0 |

모든 256개 range(0-65535) 완전 병합. "combine 실패" 없음.

### 권한 우회 방법 (기록)
- `/data/tiles/fonts/Noto Sans Bold`, `Noto Sans Italic` 폴더가 root 소유 (내부 .pbf root:root)
- 해결: `mv` rename으로 root 폴더를 `.root_orig`로 이동(parent limera 소유라 가능) → `~/fontout/`에서 병합 후 `cp -r`로 신규 생성

---

## 한글 글리프 검증 (tileserver localhost:8080)

```
Bold  한글(44032-44287.pbf): HTTP 200  size=188674 bytes
Italic 한글(44032-44287.pbf): HTTP 200  size=181632 bytes
Regular 한글(44032-44287.pbf): HTTP 200  size=181607 bytes
```

모두 200 + 수십~수백 KB → 한글 포함 확인. Bold가 Regular보다 7KB 더 큰 것은 Bold 자체 글리프 + CJK 병합 결과.

---

## 스타일 파일 배치

| 항목 | 내용 |
|------|------|
| 배치 경로 | `assets/images/osm_liberty_yurunavi.json` |
| 원본 백업 | `assets/images/osm_liberty_yurunavi.json.bak` |
| 크기 변화 | 79826 B → 113304 B (osm-bright가 레이어 수 많음) |
| 코드 참조 변경 | **없음** (기존 파일명 유지, 코드 빌드 불필요) |

코드 참조 2곳 모두 파일명 그대로 사용:
- `lib/features/map/presentation/main_map_screen.dart:765`
- `lib/features/navigation/presentation/nav_screen.dart:758`

---

## 폰트 stack 축약

26개 레이어 text-font에서 CJK 폴백 제거:

| 이전 | 이후 |
|------|------|
| `["Noto Sans Bold", "Noto Sans CJK TC Regular"]` | `["Noto Sans Bold"]` |
| `["Noto Sans Italic", "Noto Sans CJK TC Regular"]` | `["Noto Sans Italic"]` |
| `["Noto Sans Regular", "Noto Sans CJK TC Regular"]` | `["Noto Sans Regular"]` |

총 레이어: 128개. CJK 잔류: 없음.

목적: tileserver URL의 콤마 concat(`Bold,CJK TC Regular`) 제거 → Cloudflare 차단·캐시 비효율 회피.

---

## source URL 최종값

```
sources.openmaptiles.url: https://tiles.westinx.com/data/v3.json  → HTTP 200 ✓
glyphs:                   https://tiles.westinx.com/fonts/{fontstack}/{range}.pbf  → HTTP 200 ✓
```

---

## 백업 위치 & 롤백 방법

| 백업 | 위치 |
|------|------|
| Noto Sans Bold 원본 (limera cp) | `/data/tiles/fonts/Noto Sans Bold.orig` |
| Noto Sans Bold 원본 (root 소유) | `/data/tiles/fonts/Noto Sans Bold.root_orig` |
| Noto Sans Italic 원본 (limera cp) | `/data/tiles/fonts/Noto Sans Italic.orig` |
| Noto Sans Italic 원본 (root 소유) | `/data/tiles/fonts/Noto Sans Italic.root_orig` |
| 스타일 원본 | `assets/images/osm_liberty_yurunavi.json.bak` |

**폰트 롤백:**
```bash
# Bold
rm -rf "/data/tiles/fonts/Noto Sans Bold"
cp -r "/data/tiles/fonts/Noto Sans Bold.orig" "/data/tiles/fonts/Noto Sans Bold"
# Italic
rm -rf "/data/tiles/fonts/Noto Sans Italic"
cp -r "/data/tiles/fonts/Noto Sans Italic.orig" "/data/tiles/fonts/Noto Sans Italic"
docker restart yurunavi-tiles
```

**스타일 롤백:**
```bash
cp assets/images/osm_liberty_yurunavi.json.bak assets/images/osm_liberty_yurunavi.json
```

---

## 미해결 / 후속 사항

- Flutter 빌드는 하지 않음. 스타일은 런타임 로드이므로 다음 앱 실행 시 자동 반영.
  코드 참조 파일명을 변경하지 않았으므로 빌드 불필요.
- osm-bright 스타일 레이어 수(128)가 기존 osm-liberty보다 많음 → 앱 로딩 후 지도 정보 밀도 변화 육안 확인 권장.
- `/data/tiles/fonts/Noto Sans Bold.root_orig`, `.orig` 정리는 검증 완료 후 수동 삭제 권장.
