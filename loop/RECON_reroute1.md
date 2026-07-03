# RECON_reroute — 재탐색 heading 전달 (읽기 전용)
규칙: 읽기전용, 코드변경 금지, 모호하면 중단+보고. 하단 append.

## A. 클라이언트가 지금 heading을 보내나
- [ ] 재탐색 요청 빌드 지점 file:line
      rg -n "_fetchAndStoreAllRoutes|rerout|locations.*lat|/route" lib/ --type dart
- [ ] Valhalla 요청 JSON에 locations[0].heading / heading_tolerance 있나? 원문
      rg -n "heading|bearing" lib/ --type dart

## B. fork가 heading을 수용하는가 (curl 실측 = 핵심 증거)
- [ ] heading 없이 1회, heading+tolerance 넣고 1회 — U턴 차이 나는지 trip.legs[0].maneuvers[0] 비교
      (아래 §D 명령 실행, 응답의 첫 maneuver type/instruction 기록)

## C. 응답에 진입각 단서 있나
- [ ] maneuvers[0]가 즉시 U턴(type=8/9 등)인지, 출발 직진인지

## D. curl 실측 명령 (port 8002, 실제 좌표 1쌍으로 치환)
curl -s 'http://localhost:8002/route' -d '{
  "locations":[{"lat":LAT,"lon":LON,"heading":HDG,"heading_tolerance":45},
               {"lat":DLAT,"lon":DLON}],
  "costing":"motorcycle","directions_options":{"units":"kilometers"}
}' | python3 -c "import sys,json;d=json.load(sys.stdin);m=d['trip']['legs'][0]['maneuvers'][0];print(m['type'],m.get('instruction'))"
  → 같은 좌표에서 heading 빼고 1회 더. 두 결과 type 비교.
출력: A heading 송신 유무 file:line + B 두 curl의 maneuver type 차이 + C 판정.