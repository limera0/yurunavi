# RECON_poi — POI 지명/히스토리 (읽기 전용)
규칙: 읽기 전용, 코드변경 금지, 모호하면 즉시 중단+원문보고. 결과는 본 파일 하단 append.

## A. 현재 상태
- [ ] 터치→목적지 지정 이미 있나? 콜백 file:line
      rg -n "onMapClick|onMapLongClick|onTap" lib/
- [ ] 히스토리/목적지 모델 — 좌표만 저장 중인가? file:line
      rg -n "class .*History|Destination|searchHistory|recent" lib/ --type dart

## B. 지명 소스 (핵심 결정 = 계약 테스트 대상)
- [ ] 좌표→지명: 타일 피처(queryRenderedFeatures) vs 역지오코딩? 어느 쪽인지 확정
      rg -n "queryRenderedFeatures|querySourceFeatures|nominatim|reverseGeocode" lib/
- [ ] maplibre_gl 0.26.1 queryRenderedFeatures 시그니처/반환 props 형태 실측
- [ ] POI 레이어 id + name 필드 키
      rg -n "poi|place|label" assets/images/osm_liberty_yurunavi.json

## C. 단일 소스 검증 (안티패턴 방지)
- [ ] 082d6e5가 이미 name:ko/en/ja 해석 로직 보유? 보유 시 그 순서/시그니처 그대로 기록
      git show 082d6e5 --stat ; rg -n "name:ko|coalesce|textField|name_field" lib/ assets/

## D. 언어 설정 소스 (PoiNameResolver가 읽을 곳)
- [ ] map-language On/Off state/provider file:line
      rg -n "MapLang|languageProvider" lib/

## 출력
A~D 각 file:line + 발견. C에서 기존 해석 발견 시 시그니처 명기(테스트 기대값 확정용).