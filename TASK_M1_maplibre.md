# TASK M1 — main_map_screen 빈 MapLibre 지도 + osm_liberty 스타일

브랜치: `feat/maplibre-migration`
실행: tmux 안에서 `claude --permission-mode auto`
스코프: **`lib/features/map/presentation/main_map_screen.dart` 한 파일.**
목표: 기존 FlutterMap(664~803행)을 MapLibreMap 하나로 교체. osm_liberty 스타일이
      실제로 적용되어 고속도로 숨김·국도 강조된 지도가 뜨는지 확인.
      폴리라인·마커·Circle·POI는 **이번엔 넣지 않는다** (M2~M3에서).

---

## 사전 확인

```bash
cd /data/projects/yurunavi
git branch                  # * feat/maplibre-migration
git status                  # clean (M0 커밋 b818496 이후)
flutter analyze             # No issues (시작점 확인)
```

---

## 핵심 방침 — LatLng 충돌 처리 (방침 A)

flutter_map 은 latlong2 의 `LatLng`, maplibre_gl 은 자체 `LatLng` 를 쓴다 (동명이클래스).
**maplibre 만 `as ml` 별칭**으로 들여오고, latlong2 는 별칭 없이 그대로 둔다.
→ 기존 `LatLng`(= latlong2) 변수·메서드는 한 글자도 안 바꾼다. 새 MapLibre 타입만 `ml.` 접두사.

파일 상단 import 에 추가 (기존 flutter_map / latlong2 import 는 유지):
```dart
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
```

좌표 변환 헬퍼를 State 클래스 안(또는 파일 상단 함수)에 추가:
```dart
// latlong2.LatLng → maplibre_gl.LatLng 변환 (지도에 넘길 때만 사용)
ml.LatLng _toMl(LatLng p) => ml.LatLng(p.latitude, p.longitude);
```

---

## STEP 1 — MapLibre 컨트롤러 필드 추가

기존 `final MapController _mapCtrl = MapController();` (78행) **는 지우지 않는다.**
(147·163·171·676행에서 아직 쓰임 — M4에서 정리.) 그 아래/근처에 MapLibre 컨트롤러 추가:

```dart
ml.MaplibreMapController? _mlCtrl; // M1~M4 동안 점진 연결
```

⚠️ maplibre_gl 0.26.1 의 컨트롤러 클래스명이 `MaplibreMapController` 인지
`MapLibreMapController` 인지 패키지 버전에 따라 다를 수 있다. 먼저 확인:
```bash
grep -rn "class MaplibreMapController\|class MapLibreMapController" \
  ~/.pub-cache/hosted/pub.dev/maplibre_gl-*/lib/ 2>/dev/null | head
```
실제 클래스명을 코드에 반영할 것. (이하 지시는 `MaplibreMapController` 가정 — 다르면 치환)

---

## STEP 2 — FlutterMap(664~803행) 교체

664행 `FlutterMap(` 부터 803행 `),` 까지 **통째로 삭제**하고, 그 자리에 아래를 넣는다.
위/아래의 Stack 구조(`body: Stack(children: [` 와 LAYER 2 로딩 오버레이)는 **건드리지 않는다.**

```dart
          // ══════════════════════════════════════════════════════
          // LAYER 1 · MapLibre Map (osm_liberty 스타일)
          // M1: 빈 지도 + 스타일만. 폴리라인·마커는 M2~M3에서 추가.
          // ══════════════════════════════════════════════════════
          ml.MaplibreMap(
            styleString: 'assets/images/osm_liberty_yurunavi.json',
            initialCameraPosition: ml.CameraPosition(
              target: _toMl(_origin ?? _lastKnown ?? kInitialMapView),
              zoom: _currentZoom,
            ),
            // 오토바이 거치 — 회전 잠금 (North-up 고정)
            rotateGesturesEnabled: false,
            // 기울기도 잠금 (2D 유지)
            tiltGesturesEnabled: false,
            compassEnabled: false,
            onMapCreated: (c) => _mlCtrl = c,
            onMapClick: (point, latLng) {
              // 기존 _onMapTap 은 latlong2.LatLng 를 받는다 → 변환해서 호출
              _onMapTap(null, LatLng(latLng.latitude, latLng.longitude));
            },
            onCameraIdle: () {
              final z = _mlCtrl?.cameraPosition?.zoom;
              if (z != null) setState(() => _currentZoom = z);
            },
          ),
```

⚠️ **`_onMapTap` 시그니처 확인 필수.** 기존 onTap 은 flutter_map 의
`(TapPosition, LatLng)` 를 넘긴다. `_onMapTap` 의 실제 매개변수를 grep 해서
첫 인자에 null 을 넣어도 되는지, 아니면 어떻게 호출해야 하는지 확인 후 맞출 것:
```bash
grep -n "_onMapTap" lib/features/map/presentation/main_map_screen.dart
sed -n '/void _onMapTap/,/^  }/p' lib/features/map/presentation/main_map_screen.dart
```
시그니처가 안 맞으면 변환부를 거기 맞게 조정. (억지로 null 넣지 말 것.)

---

## STEP 3 — 미사용 경고 처리 (삭제 금지)

폴리라인·마커·Circle·POI 관련 변수/메서드(`allRoutes`, `routePolyline`, `pois`,
`_buildPoiMarkers`, `_OriginMarker`, `_clusterPois`, `_touchPoint` 등)가 이번 교체로
**일시적으로 미사용**이 되어 analyze 경고가 날 수 있다.

**이것들을 절대 삭제하지 말 것.** M2~M3 에서 다시 쓴다.
- `flutter analyze` 가 무이슈를 요구하므로, 미사용 경고가 뜨면:
  - 변수/메서드 선언 위에 `// ignore: unused_field` 또는 `// ignore: unused_element` 추가
  - 또는 analyze 가 warning 수준이라 통과한다면 그대로 둠
- 어느 쪽이든 **선언 자체는 보존**. 지우면 M2~M3 에서 복구 비용 발생.

`_mapCtrl`(flutter_map 컨트롤러)도 147·163·171행에서 아직 쓰이므로 유지.
단 676행(`_mapCtrl.camera.zoom`)은 FlutterMap 삭제와 함께 사라졌으니,
줌 추적은 STEP 2 의 `onCameraIdle` 로 대체됨.

---

## STEP 4 — 검증

```bash
cd /data/projects/yurunavi
flutter analyze                          # No issues (ignore 처리 후)
flutter build apk --debug 2>&1 | tail -15
```

**합격 기준:**
- analyze 무이슈
- 디버그 빌드 성공
- (실기기 [HUMAN]) 앱 실행 시: 지도가 뜨고, **고속도로가 안 보이고, 국도가 강조**되어
  osm_liberty 스타일이 적용된 게 육안 확인됨. 폴리라인·마커는 아직 없는 게 정상.

빌드는 되는데 지도가 **회색/빈 화면**이면: styleString 경로 문제 가능성.
- asset 경로가 `assets/images/osm_liberty_yurunavi.json` 맞는지
- pubspec 에 등록됐는지 (M0 STEP2 에서 확인됨)
- styleString 에 `assets/` 접두사 형식이 0.26.1 에서 맞는지 (일부 버전은 다른 형식 요구)
  → 안 뜨면 이 세 가지를 로그(`flutter logs`)와 함께 보고.

---

## 절대 금지
- 다른 파일 수정 (M1 은 main_map_screen.dart 단일)
- latlong2 의 LatLng 를 maplibre 것으로 바꾸기 (방침 A 위반 — 기존 변수 그대로)
- 미사용이 된 폴리라인/마커/POI 변수·메서드 삭제
- Stack 구조나 LAYER 2 이하 오버레이(로딩·속도계·버튼) 수정
- flutter_map import 제거 (다른 레이어가 M2~M3까지 의존)

---

## 커밋 + 보고

```bash
git add lib/features/map/presentation/main_map_screen.dart
git commit -m "feat(M1): replace FlutterMap with empty MapLibreMap + osm_liberty style [maplibre-M1]"
```

보고:
- MapLibre 컨트롤러 실제 클래스명 (MaplibreMapController vs MapLibreMapController)
- styleString 적용 방식 (asset 경로가 그대로 먹었는지, 형식 조정 필요했는지)
- analyze / build 결과
- 커밋 해시
- [HUMAN] 잔여: 실기기에서 스타일(고속도로 숨김·국도 강조) 육안 확인
- 다음: M2 (경로 폴리라인 — addLine GL API)

---

## 다음 미리보기
- **M2**: routePolyline + allRoutes 를 maplibre 의 line layer(addLine 또는 GeoJSON source)로.
  선택/비선택 색 구분 유지.
- **M3**: 마커 — _OriginMarker 등 커스텀 위젯을 심볼 이미지로 등록 (최난관).
- **M4**: 카메라 — _mapCtrl.move/rotate, CameraFit, 줌버튼을 _mlCtrl 로 이관 후 _mapCtrl 제거.
