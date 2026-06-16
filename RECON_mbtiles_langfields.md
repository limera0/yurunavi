# RECON: Korea/Japan mbtiles 언어 필드 실측
작성일: 2026-06-13 | 상태: 읽기 전용 정찰 완료

---

## 1. mbtiles 파일 위치

```
/data/tiles/data/korea.mbtiles   382M  (생성: 2026-06-04)
/data/tiles/data/japan.mbtiles   1.7G  (생성: 2026-06-05)
```

두 파일 모두 존재 확인. 최대 줌 레벨 14.

---

## 2. metadata.json vector_layers.fields 선언 (1차 확인)

명령어:
```
sqlite3 /data/tiles/data/korea.mbtiles "SELECT value FROM metadata WHERE name='json';"
sqlite3 /data/tiles/data/japan.mbtiles "SELECT value FROM metadata WHERE name='json';"
```

### Korea mbtiles metadata 선언 (place/poi 레이어 기준)
선언된 name 계열 필드:
`name`, `name:cs`, `name:de`, `name:el`, `name:en`, `name:es`, `name:fa`, `name:fr`,
`name:hi`, `name:id`, `name:it`, `name:ja`, `name:kn`, `name:ko`, `name:ko-Latn`,
`name:latin`, `name:nonlatin`, `name:pl`, `name:pt`, `name:ru`, `name:th`, `name:tr`,
`name:vi`, `name:zh`, `name:zh-Hans`, `name:zh-Hant`, `name_de`, `name_en`, `name_int`

→ `name:ko`, `name:ja`, `name:en` **모두 선언됨** (단, 선언 ≠ 실제 데이터 보장)

### Japan mbtiles metadata 선언
`name`, `name:ar`, `name:cs`, `name:de`, `name:en`, `name:es`, `name:fr`, `name:id`,
`name:it`, `name:ja`, `name:ja-Hira`, `name:ja-Latn`, `name:ko`, `name:latin`,
`name:nonlatin`, `name:pl`, `name:pt`, `name:ru`, `name:th`, `name:tr`, `name:uk`,
`name:vi`, `name:zh`, `name:zh-Hans`, `name:zh-Hant`, `name_de`, `name_en`, `name_int`

→ `name:ja`, `name:ja-Hira`, `name:ja-Latn`, `name:ko` **모두 선언됨**

---

## 3. 실제 타일 피처 실측 (권위 있는 검증)

### 방법
```bash
docker run --rm -v /data/tiles/data:/d python:3.11-slim bash -c "
pip install -q mapbox-vector-tile && python3 - <<'PY'
...zoom14, 서울(lon=126.98, lat=37.57) ±5타일 121개 디코딩
PY"
```
Korea: 서울 주변 zoom14 121타일 디코딩 완료  
Japan: 도쿄 주변 zoom14 121타일 디코딩 완료

---

### 3-A. Korea mbtiles 실측 결과 (서울 주변 zoom14, 121타일)

| 필드 | 등장 횟수 | 예시값 | 스크립트 타입 |
|---|---|---|---|
| `name_int` | 218,296 | `'Wangjaesan (Mt.)'` | 로마자 (국제명) |
| `name:latin` | 218,278 | `'Wangjaesan (Mt.)'` | 로마자 |
| `name_de` | 218,228 | `'왕재산'` | 한글(fallback¹) |
| `name_en` | 218,207 | `'Wangjaesan (Mt.)'` | 로마자(fallback¹) |
| `name` | 215,801 | `'왕재산'` | 한글 |
| `name:nonlatin` | 205,467 | `'왕재산'` | 한글 |
| **`name:en`** | **59,880** | `'Wangjaesan (Mt.)'` | 로마자 |
| **`name:ko`** | **59,357** | `'왕재산'` | 한글 |
| `name:ko-Latn` | 19,111 | `'Gwangmyeong-si'` | 로마자(한국어) |
| **`name:ja`** | **14,001** | `'光明市'` | 한자² |
| `name:zh` | 7,049 | `'光明市'` | 한자 |
| `name:zh-Hant` | 4,313 | `'光明市'` | 한자(번체) |
| `name:el` | 3,751 | `'Γκουάνγκμιονγκ'` | 그리스어 |
| `name:zh-Hans` | 2,729 | `'光明市'` | 한자(간체) |
| `name:ru` | 536 | `'Кванмён'` | 키릴 |
| 기타 언어 | 각 10~350 | — | — |

> ¹ `name_de` / `name_en` / `name_int`는 OpenMapTiles planetiler가 생성한 가상 필드.  
>   `name_de`는 `name:de` 없으면 `name`으로 fallback → 예시가 한글인 이유.  
>   `name_en`은 `name:en` 없으면 `name:latin`으로 fallback → 로마자 예시.  
> ² Korea mbtiles의 `name:ja`는 한자 기반 행정명(光明市, 서울 등)으로, 일부 주요 지명에만 존재.

**커버리지 비율 (name:latin 기준=100%):**
- `name:latin`: 100% (218,278)
- `name:nonlatin`: 94% (205,467)
- `name:en`: 27% (59,880)
- `name:ko`: 27% (59,357)
- `name:ja`: 6.4% (14,001)

---

### 3-B. Japan mbtiles 실측 결과 (도쿄 주변 zoom14, 121타일)

| 필드 | 등장 횟수 | 예시값 | 스크립트 타입 |
|---|---|---|---|
| `name_int` | 260,682 | `'hotaruno lǐ'` | 로마자 |
| `name:latin` | 260,668 | `'hotaruno lǐ'` | 로마자 |
| `name_de` | 260,500 | `'ホタルの里'` | 일본어(fallback) |
| `name_en` | 260,496 | `'ホタルの里'` | 일본어(fallback) |
| `name` | 256,834 | `'ホタルの里'` | 일본어 |
| `name:nonlatin` | 226,530 | `'ホタルの里'` | 일본어 |
| **`name:en`** | **119,368** | `'Miyamae Ward'` | 영문 |
| **`name:ja`** | **92,994** | `'宮前区'` | 일본어(한자) |
| `name:ja-Hira` | 36,038 | `'みやまえく'` | 히라가나 |
| `name:ja-Latn` | 16,293 | `'Tama-ku'` | 로마자(일본어) |
| **`name:ko`** | **13,273** | `'미야마에다이라'` | 한글 |
| `name:fr` | 11,688 | `'Arrondissement de Tama'` | 프랑스어 |
| `name:zh` | 3,590 | `'狛江市'` | 한자 |
| `name:ru` | 2,349 | `'Миямиэдайра'` | 키릴 |

---

## 4. 결론

### 4-A. 한국어 모드 필드 확정

| 후보 | 커버리지 | 판정 |
|---|---|---|
| `name:nonlatin` | 94% (205k) | **채택** — 현 스타일과 동일, 커버리지 최대 |
| `name:ko` | 27% (59k) | 기각 — 커버리지 3.5배 열위 |

→ **한국어 모드 = `{name:nonlatin}`** (현재 스타일의 두 번째 줄 필드와 동일)

### 4-B. 영어 모드 필드 확정

| 후보 | 커버리지 | 판정 |
|---|---|---|
| `name:latin` | 100% (218k) | **채택** — 커버리지 최대 |
| `name:en` | 27% (60k) | 기각 — 커버리지 3.5배 열위 |

→ **영어 모드 = `{name:latin}`** (현재 스타일의 첫 번째 줄 필드와 동일)

### 4-C. 日本語 선택지 출시 가능 여부

| 타일 | `name:ja` 커버리지 | 예시 | 판정 |
|---|---|---|---|
| Korea mbtiles | 6.4% (14k) | `'光明市'` — 주요 도시 한자명만 | ⚠️ 제한적 |
| Japan mbtiles | 36% (93k) | `'宮前区'` — 정상 일본어 | ✅ 충분 |

→ **Korea 타일에서 日本語 라벨 커버리지 6%에 불과.**  
한국 지도에서 일본어 선택 시 대부분 피처가 라벨 없음(빈칸) 상태가 됨.  
**日本語 선택지: 조건부 출시 가능** — Japan 타일에서는 정상, Korea 타일 단독으로는 사용 불가 수준.  
마스터 결정 필요 (→ 아래 미확인 목록 U1).

### 4-D. 실측 기반 스타일 표현식 매핑

| 언어 설정 | text-field 표현식 | 근거 |
|---|---|---|
| 한국어 | `{name:nonlatin}` | 94% 커버리지, 현 스타일 동일 필드 |
| English | `{name:latin}` | 100% 커버리지, 현 스타일 동일 필드 |
| 日本語 | `{name:ja}` | Korea 6% / Japan 36% 커버리지 |

현재 병기 표현식 `{name:latin}\n{name:nonlatin}`은 영어+한국어 동시 표기.  
단일 선택으로 전환 시 위 표에 따라 해당 단일 필드로 교체하면 됨.

---

## 5. 미확인 · 마스터 결정 필요 항목

| # | 항목 | 근거 |
|---|---|---|
| U1 | Korea 타일에서 日本語 선택지 제공 여부 — 6% 커버리지를 허용할지, 한국 지도에선 日本語 비활성화할지 | 실측 결과(6% vs Japan 36%) |
| U2 | MapLibre Flutter SDK `setLayoutProperty`로 `text-field` 표현식 문자열 교체 가능 여부 | pubspec에서 maplibre_gl 버전 미확인, 기존 호출 코드 없음 |
| U3 | Japan mbtiles 공존 시 언어 설정 스코프 — 앱 전역 1개 설정인지, 타일 파일별 독립 설정인지 | config.json에 korea+japan 두 data source 존재(CLAUDE.md TODO 항목) |
