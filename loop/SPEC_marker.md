# SPEC_marker — nav 목적지 마커 화면고정 버그

근거: RECON_marker.md. nav가 MapLibre 지도 위에 투명 FlutterMap 오버레이를 얹고
거기에 Marker를 다는데, FlutterMap이 initialCenter 고정(MapController 없음)이라
MapLibre 카메라가 움직여도 마커가 안 따라가 화면 한 점에 고정됨(라이딩 실측 확인).

## 채택안: 옵션 A — FlutterMap 오버레이 제거, MapLibre 네이티브 Symbol로
main_map_screen이 이미 쓰는 방식과 동일하게:
- 목적지/경유지 마커를 MapLibre Symbol(addSymbol/updateSymbol)로 생성.
- nav의 _onStyleLoaded(또는 동등 콜백)에서 이미지 등록(pointer_red 등) + Symbol 생성.
- 기존 _locMarker(현위치) Symbol 방식 참고(이미 nav에 있을 것).
- FlutterMap 위젯 트리 + MarkerLayer 제거.

## 곁다리(RECON_marker §C): 스타일 재주입 후 마커 소멸
main_map_screen onStyleLoadedCallback에서 _ensureLocationMarker 직후
목적지/경유지 마커 재생성 누락 → dest != null이면 _ensureDestMarker 재호출 추가.
(별도 커밋으로 분리 가능. nav 수정과 독립이면 후순위로)

## 커밋 분할(가능하면 단일파일·단계)
- 커밋1 nav_screen.dart: 목적지/경유지 마커를 MapLibre Symbol로 전환, FlutterMap 오버레이 제거.
  (한 파일 내 변경이지만 크면 '마커 추가'와 'FlutterMap 제거'로 나눠도 됨)
- 커밋2(곁다리) main_map_screen.dart: 스타일 재주입 후 dest 마커 재생성.

## 주의
- nav의 카메라/지도 본체는 MapLibre(_mlCtrl). 그건 건드리지 말 것.
- 마커 좌표는 widget.destination(LatLng) → ml.LatLng 변환(_toMl 등 기존 헬퍼 사용).
- 스타일 리로드 시 nav도 마커 재생성 필요한지 확인(main_map과 동일 패턴).

## 검증
- 객관(analyze): 컴파일 통과, FlutterMap import 제거 후에도 빌드.
- 라이딩(필수, main 머지 전): 주행 중 목적지 마커가 지도에 고정 추종(화면 고정 아님).
