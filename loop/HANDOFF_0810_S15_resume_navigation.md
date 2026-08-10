GOAL: 앱이 비정상 종료(강제 종료/OOM kill)로 중단된 투어를 다음 앱 시작 시 자동으로 감지해 "이어서 안내할까요?" 제안을 띄우고, 수락 시 현재위치→원목적지 재탐색으로 내비게이션을 재개하며, 중단 전/재개 후 두 구간을 히스토리에 하나의 투어로 병합 표시한다.

- 작성 2026-08-10 · 근거: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S15 (741~754행)
- 마스터 확인 완료 사항(2026-08-10 인터랙티브 세션):
  - **재개 트리거: 앱 (재)시작 시 자동 제안** (수동재개 아님, 기존 확정 유지)
  - **오탐 방지 임계치**: 설정 화면에서 사용자가 시간 단위로 선택. 기본값 **2시간**, 최대 **24시간**.
  - **재개 방식**: 원경로 유지 아님 — **현재위치 → 원목적지 재탐색**으로 확정(`RoutingService.fetchRoutes` 재사용, `feedback_prefer_simple_reuse` 근거).
  - **원목적지 확보 방식**: 기존 데이터로는 불가능(아래 §0) — **신규 직접 저장**으로 확정(추천안 채택). 네비게이션 시작 시점에 목적지를 사이드카 파일로 즉시 저장한다.
  - **착수 순서 예외**: 확정 원칙상 P0~P2 잔여 5건(S1b·S9·S11·S13·S14) 완료 후 P3 착수였으나 S11(고급휘발유 미표시)만 미완료 상태에서 마스터가 S15를 오늘 먼저 진행하라고 명시 지시. S11은 별도로 남아 있다 — 완료된 것으로 착각하지 말 것.
- 이 항목은 원인 조사가 아니라 **신규 기능 설계**. 아래 §0은 이 세션에서 이미 끝낸 코드 조사(Explore 서브에이전트 + 직접 확인) 결과이고, §1~§4는 그 위에 구축한 4청크 구현 설계다.

## §0. 코드 조사 결과 (2026-08-10 확인) — 반드시 읽고 시작할 것

- **`TourRecoveryService`** (`lib/services/tour_recovery_service.dart`, 231행 전체): `tours/*.jsonl` 중 `TourLogService`에 없는 id를 "고아"로 판정(`recoverOrphans()`:75-109), `_recoverOne(id, file)`(:111-206)이 파일을 읽어 `TourLog`로 변환·저장한다. **트랙 파일에는 `[epochMs, lat, lng, speedKmh]`만 기록되고(`tour_track_writer.dart:47-56`) 목적지는 어디에도 없다** — `TourLog`(`lib/models/tour_log.dart`)에도 목적지 필드가 없다. 이미 있는 `RecentRoute`(`lib/models/saved_place.dart:63-80`, `places_service.dart` 키 `recent_routes_v1`, 최근 5건만 보관)로 시간 상관관계 추정도 가능은 했지만 신뢰도가 낮아 채택하지 않음(마스터 확인 완료).
- **id 스킴**: `TourLog.id` = `startedAt.millisecondsSinceEpoch.toString()`(`tour_log.dart:5` 주석), 고아 파일명 `tour_<id>.jsonl`의 id와 동일(`_idPattern`, :58). **`TourRecorder.start(pos, at)`(`lib/features/navigation/tour_recorder.dart:36-61`)가 내부에서 `_id = at.millisecondsSinceEpoch.toString()`를 만든다(:41)** — 호출부가 넘긴 `at` 인스턴스가 곧 id의 근거다.
- **이미 코드에 적힌 경합 경고** (`tour_recovery_service.dart:66-74`): "향후 자동 재개... 기능이 생기면 이 메서드와 경합(활성 투어를 고아로 오인해 조기 종료 처리)할 수 있다." — §2에서 이 경고를 **해소**한다: `recoverOrphans()`가 "재개 가능" 판정이 서는 고아는 스킵하고 건드리지 않도록 바꾼다(새 세션은 항상 새 파일로 시작하므로 기존 파일을 다시 붙잡는 일 자체가 없어 경합 여지가 사라진다).
- **`TourLogService`** (`lib/services/tour_log_service.dart`, 83행): SharedPreferences 키 `tour_logs_v1`(:12), `loadAll()`(:14-27) / `add()`(:29-36, 무제한 누적) / `update()`(:38-51, id로 매칭) / `delete()`(:53-81).
- **히스토리 화면**: `lib/features/tour_summary/presentation/tour_summary_list_screen.dart` — `TourSummaryListScreen`(:11-60)이 `tourLogListProvider` watch, `groupTourLogsByDay(logs)`(:31, 정의는 `tour_log_format.dart:32-41`)로 **달력 날짜별** 그룹만 함. **두 `TourLog`를 하나로 병합 표시하는 개념 자체가 없다** — §4에서 신설. 카드 위젯 `_TourLogCard`(:62-164). provider: `lib/features/tour_summary/providers/tour_log_providers.dart`의 `tourLogListProvider`(`AsyncNotifierProvider<TourLogListNotifier, List<TourLog>>`, :8-10).
- **설정 화면**: `lib/features/settings/presentation/settings_screen.dart`(268행). **Slider/NumberPicker/Stepper가 코드베이스에 전혀 없음.** 재사용할 패턴은 `DropdownButton<T>` — `_LanguageSelector`(:119-152), `_IdeographFontSelector`(:165-220). 설정 저장은 `lib/features/settings/providers/settings_providers.dart`의 개별 `AsyncNotifierProvider<T>` + 단일 shared_prefs 키 패턴(예: `MapNightDimEnabledNotifier`, `_key = 'map_night_dim_enabled_v1'`, :36-50). `pubspec.yaml`에 `sqflite` 없음 — file+shared_prefs만 사용하는 기존 방침과 일치.
- **`RoutingService.fetchRoutes`** (`lib/services/routing_service.dart:276-280`):
  ```dart
  static Future<List<RouteResult>> fetchRoutes({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  })
  ```
  3개 `RouteResult`(시골길/지방도로/국도, `_courseNames`:165) 반환, 실패 시 `RoutingException`(:24) throw. 재탐색에 그대로 재사용.
- **경로 계산 → 내비 시작 호출 체인**: `lib/features/map/presentation/main_map_screen.dart`의 `_startNavigation()`(:1657-1697)이 `RecentRoute` 기록(:1662-1674) 후 `Navigator.of(context).push(MaterialPageRoute(builder: (_) => NavScreen(destination: dest, waypoints: state.waypoints, routePolyline: state.routePolyline, maneuvers: _selectedManeuvers, durationMin: durationMin)))`(:1684-1693). `NavScreen` 생성자(`nav_screen.dart:112-127`)는 전부 optional param — `RouteResult` 하나만 있으면 바로 구성 가능.
- **`NavScreen` 내 투어 기록·목적지 접점**:
  - `_tourRecorderStarted` 게이트 안(`nav_screen.dart:575-578`): `_navStartedAt = DateTime.now();` 바로 다음 줄에서 **별도로** `DateTime.now()`를 다시 호출해 `_tourRecorder.start(loc, DateTime.now())`에 넘기고 있다 — 두 시각이 이론상 어긋날 수 있는 느슨한 지점. §1에서 `_tourRecorder.start(loc, _navStartedAt!)`로 통일해 목적지 사이드카 id와 100% 일치시킨다(부수적으로 기존 로직도 더 정확해짐).
  - 목적지 좌표: `widget.destination`. 목적지 이름: `ref.read(mapInteractionProvider).destinationName`(nav_screen.dart:2457에서 이미 이런 식으로 읽음).
  - 투어 종료·저장: `_finalizeAndPersistTour()`(:1070-이후) — `_tourRecorder.finish(...)`(:1083) 후 `finalLog = tourLog.copyWith(startAddress: ..., endAddress: ...)`(:1098) 지점에서 `TourLogService().add(finalLog)`(:1104 부근). **`resumedFromId` 연결은 바로 이 `copyWith` 호출에 인자 하나 추가**하면 된다.
- **스플래시/부팅 시퀀스**: `lib/features/auth/presentation/splash_screen.dart`. `main.dart:38`에 `unawaited(TourRecoveryService().recoverOrphans());`가 fire-and-forget으로 있음(완료를 아무도 기다리지 않음) — **재개 프롬프트는 완료를 기다려야 하므로 이 호출을 스플래시로 옮긴다.** `_SplashScreenState._runSequence()`(:146-195)는 이미 위치 선확보를 `bootLocationProvider`에 채워 넣고(`_acquireBootLocation`:200-210), `_goToMain()`(:228-242, `MainMapScreen`으로 `pushReplacement`)으로 끝난다. **재탐색 origin은 새로 GPS를 뜨지 않고 `ref.read(bootLocationProvider)`(이미 확보된 값, `LatLng?`)를 그대로 재사용**한다(main_map_screen.dart:267과 동일 패턴) — 값이 없으면(권한 거부/실패) 재개 프롬프트 자체를 건너뛴다.
- **탭-액션 프롬프트 하우스 스타일**: `lib/services/nav_floating_overlay.dart:107-136`의 `checkPermissionAndMaybePrompt()` — title/body + `TextButton` 2개(취소/확인) `showDialog<void>` 패턴. S15 프롬프트도 이 톤을 따른다.

## §1. 청크1 — 목적지 스냅샷 저장 + `TourLog` 연결 필드

**신규 파일** `lib/services/active_tour_destination_store.dart`:
```dart
import 'dart:convert';
import 'dart:io';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

/// 내비게이션 시작 시점의 목적지를 `tours/tour_<id>.dest.json`에 즉시 저장한다.
/// TourRecoveryService의 orphan id 스킴과 동일 id를 공유해, 프로세스가
/// 중간에 죽어도(트랙 .jsonl과 마찬가지로) 목적지 정보가 함께 남는다.
class ActiveTourDestinationStore {
  Future<void> record({
    required String id,
    required double destLat,
    required double destLng,
    String? destName,
    List<LatLng> waypoints = const [],
    Directory? baseDirOverride,
  }) async {
    final baseDir = baseDirOverride ?? await getApplicationDocumentsDirectory();
    final toursDir = Directory('${baseDir.path}/tours');
    if (!await toursDir.exists()) await toursDir.create(recursive: true);
    final f = File('${toursDir.path}/tour_$id.dest.json');
    await f.writeAsString(jsonEncode({
      'destLat': destLat,
      'destLng': destLng,
      if (destName != null) 'destName': destName,
      'waypoints': waypoints.map((w) => [w.latitude, w.longitude]).toList(),
    }));
  }

  Future<Map<String, dynamic>?> read(String id, {Directory? baseDirOverride}) async {
    final baseDir = baseDirOverride ?? await getApplicationDocumentsDirectory();
    final f = File('${baseDir.path}/tours/tour_$id.dest.json');
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null; // 손상된 파일 — 없는 것과 동일하게 취급
    }
  }

  Future<void> delete(String id, {Directory? baseDirOverride}) async {
    final baseDir = baseDirOverride ?? await getApplicationDocumentsDirectory();
    final f = File('${baseDir.path}/tours/tour_$id.dest.json');
    if (await f.exists()) {
      try { await f.delete(); } catch (_) {}
    }
  }
}
```
- `.jsonl`만 보는 기존 `_idPattern`(`tour_recovery_service.dart:58`)은 `.dest.json`을 자동으로 무시하므로 orphan 스캔 로직과 충돌 없음.

**`nav_screen.dart` 수정**:
- :577-578을 아래로 교체 — `DateTime.now()` 중복 호출 제거 + 목적지 즉시 기록:
  ```dart
  _tourRecorderStarted = true;
  _navStartedAt = DateTime.now();
  unawaited(_tourRecorder.start(loc, _navStartedAt!));
  final dest = widget.destination;
  if (dest != null) {
    unawaited(ActiveTourDestinationStore().record(
      id: _navStartedAt!.millisecondsSinceEpoch.toString(),
      destLat: dest.latitude,
      destLng: dest.longitude,
      destName: ref.read(mapInteractionProvider).destinationName,
      waypoints: widget.waypoints,
    ));
  }
  ```
- 생성자에 `final String? resumedFromId;` 필드 + `this.resumedFromId,` 파라미터 추가(:113/122 부근, 다른 optional 필드와 동일 스타일).
- `_finalizeAndPersistTour()`의 `finalLog = tourLog.copyWith(startAddress: results[0], endAddress: results[1])`(:1098)를 `finalLog = tourLog.copyWith(startAddress: results[0], endAddress: results[1], resumedFromId: widget.resumedFromId)`로 확장. **주의**: `resumedFromId`가 null일 수도 있는 정상 케이스(일반 신규 투어)이므로 `TourLog.copyWith`도 다른 nullable 필드(`startAddress` 등)와 동일하게 `_unset` sentinel 패턴을 따라야 한다 — `resumedFromId: widget.resumedFromId`처럼 그냥 넘기면 sentinel 로직상 "명시적으로 null 지정"과 "미지정"이 구분되어야 하는데, 여기서는 항상 명시적으로 넘기는 것이 맞다(§1 `TourLog.copyWith` 시그니처도 `Object? resumedFromId = _unset`로 추가).
- 파일 상단 `import '../../../services/active_tour_destination_store.dart';` 추가.

**`TourLog` 모델 수정** (`lib/models/tour_log.dart`):
- `final String? resumedFromId;` 필드 추가(중단 전 원래 구간의 id, 없으면 일반 투어).
- `toJson`/`fromJson`/생성자/`copyWith`(기존 `_unset` sentinel 패턴 그대로, `startAddress`/`endAddress`/`memo`와 동일하게) 갱신.

**`TourRecoveryService` 리팩터**:
- `_recoverOne(String id, File file)`을 `_recoverOne(String id, File file, List<String> lines)`로 바꿔 파일을 두 번 읽지 않게 한다(재개 판정에도 마지막 줄 시각이 필요하므로 `recoverOrphans()` 루프에서 한 번만 `readAsLines()`한다).
- `recoverOrphans({Directory? baseDirOverride, int? resumeThresholdHours})` — `resumeThresholdHours`가 null이면 기존 동작 그대로(전부 즉시 finalize, 테스트/구버전 호출부 호환). 값이 있으면: 각 orphan에 대해 마지막 줄 epochMs 파싱 → `DateTime.now().difference(lastPointAt) <= Duration(hours: resumeThresholdHours)` **그리고** `ActiveTourDestinationStore().read(id)`가 non-null이면 **스킵**(finalize하지 않고 파일 그대로 둠). 그 외에는 기존처럼 `_recoverOne` 호출.
  - 클래스 헤더 주석(:66-74)의 "향후... 경합할 수 있으니 주의" 문단을 "재개 가능 판정된 고아는 여기서 스킵하고 §2 `findResumableOrphan`/`finalizeAsInterrupted`만 건드린다 — 새 재개 세션은 항상 새 id로 시작하므로 이 파일을 다시 열지 않아 경합 없음"으로 갱신.
- 신규 `Future<ResumableOrphan?> findResumableOrphan({required int thresholdHours, Directory? baseDirOverride})`: `tours/*.jsonl` 재스캔, 위와 동일한 재개-가능 판정을 통과하는 것들 중 `lastPointAt`이 가장 최근인 1건을 골라 `ResumableOrphan(id, lastPos, lastPointAt, destLat, destLng, destName, waypoints)`로 반환(없으면 null). 작은 데이터 클래스 `ResumableOrphan`을 같은 파일에 정의.
- 신규 `Future<TourLog?> finalizeAsInterrupted(String id, {Directory? baseDirOverride})`: 해당 id의 `.jsonl`을 찾아 기존 `_recoverOne` 로직으로 확정 저장(호출부에서 성공/실패 무관하게 사용할 수 있도록 반환값 제공), 완료 후 `ActiveTourDestinationStore().delete(id)`로 사이드카 정리. 스플래시의 수락/거절 양쪽 경로에서 호출.

## §2. 청크2 — 설정: 재개 임계치

**`settings_providers.dart`**: `MapNightDimEnabledNotifier`(:36-50)와 동일 패턴으로 신규:
```dart
class ResumeThresholdHoursNotifier extends AsyncNotifier<int> {
  static const _key = 'resume_threshold_hours_v1';
  static const _default = 2;

  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? _default;
  }

  Future<void> set(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, hours);
    state = AsyncData(hours);
  }
}

final resumeThresholdHoursProvider =
    AsyncNotifierProvider<ResumeThresholdHoursNotifier, int>(
        ResumeThresholdHoursNotifier.new);
```

**`settings_screen.dart`**: `_LanguageSelector`(:119-152)와 동일한 `DropdownButton<int>` 위젯 `_ResumeThresholdSelector` 신설, 옵션 `[1, 2, 3, 6, 12, 24]`(시간), 라벨 "N시간". "이어서 안내하기" 섹션 제목 아래 배치. 항목 설명 문구 예: "중단된 투어를 재개 제안할 시간 범위".

## §3. 청크3 — 재개 트리거·프롬프트·재탐색·내비 진입

**`main.dart`**: :38 `unawaited(TourRecoveryService().recoverOrphans());` 삭제(스플래시로 이동).

**`splash_screen.dart`**:
- import 추가: `TourRecoveryService`, `ActiveTourDestinationStore`는 직접 안 씀(서비스 내부에서만 사용), `RoutingService`, `NavScreen`, `resumeThresholdHoursProvider`(`settings_providers.dart`).
- `_runSequence()`의 기존 `awaitWithinBudget(...)`(:189-192) 다음, `_goToMain()`(:194) 호출 **직전**에 삽입:
  ```dart
  if (!mounted) return;
  final thresholdHours = await ref.read(resumeThresholdHoursProvider.future);
  await TourRecoveryService().recoverOrphans(resumeThresholdHours: thresholdHours);
  if (!mounted) return;
  final resumable =
      await TourRecoveryService().findResumableOrphan(thresholdHours: thresholdHours);
  final currentPos = ref.read(bootLocationProvider);
  if (resumable != null && currentPos != null && mounted) {
    final navigated = await _offerResume(resumable, currentPos);
    if (navigated) return; // 이미 NavScreen으로 진입 완료, _goToMain() 건너뜀
  }
  if (!mounted) return;
  _goToMain();
  ```
  - `currentPos == null`(위치 미확보)이면 프롬프트 자체를 건너뛴다 — 재탐색 origin이 없으므로. 고아는 다음 실행 때 다시 판정된다(임계치 내라면).
- 신규 메서드 `Future<bool> _offerResume(ResumableOrphan r, LatLng currentPos)`:
  ```dart
  Future<bool> _offerResume(ResumableOrphan r, LatLng currentPos) async {
    final elapsedMin = DateTime.now().difference(r.lastPointAt).inMinutes;
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('이어서 안내할까요?'),
        content: Text('$elapsedMin분 전 중단된 투어가 있어요.\n현재 위치에서 원래 목적지까지 다시 안내할게요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('그만두기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('이어서 안내'),
          ),
        ],
      ),
    );
    if (!mounted) return false;

    if (resume != true) {
      unawaited(TourRecoveryService().finalizeAsInterrupted(r.id));
      return false;
    }

    final oldLeg = await TourRecoveryService().finalizeAsInterrupted(r.id);
    try {
      final routes = await RoutingService.fetchRoutes(
        origin: currentPos,
        destination: LatLng(r.destLat, r.destLng),
        waypoints: r.waypoints,
      );
      if (!mounted || routes.isEmpty) return false;
      final route = routes.first; // MVP: 첫 코스(시골길) 기본 선택, 사용자 재선택 UI는 스코프 밖
      ref.read(pastSplashProvider.notifier).markPastSplash();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => NavScreen(
            destination: LatLng(r.destLat, r.destLng),
            waypoints: r.waypoints,
            routePolyline: route.points,
            maneuvers: route.maneuvers,
            durationMin: route.durationMin,
            resumedFromId: oldLeg?.id,
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('YNAV_RESUME reroute failed: $e');
      return false; // 재탐색 실패 — 중단 구간은 이미 위에서 정상 히스토리로 저장됨, 그냥 홈으로
    }
  }
  ```
- **"그만두기"/재탐색 실패 양쪽 다 `finalizeAsInterrupted`를 호출**해 고아 파일이 무기한 "재개 대기" 상태로 남지 않게 한다. "그만두기"는 unawaited(빠른 진입 우선), 재탐색 시도 경로는 awaited(oldLeg id가 다음 단계에 필요).

## §4. 청크4 — 히스토리 병합 표시

- `lib/features/tour_summary/tour_log_format.dart`: 신규 순수 함수 `List<TourLog> mergeResumedPairs(List<TourLog> logs)` 또는 렌더 직전에 "이 log가 `resumedFromId`를 가지면 원본 log를 찾아 함께 표시" 판정 헬퍼. 병합 자체는 데이터를 합치지 않고(원본 두 `TourLog`는 그대로 개별 저장) **표시 시점에만** 묶는다 — 삭제/메모 편집 등 기존 단건 동작을 깨지 않기 위함.
- `TourSummaryListScreen`/`_TourLogCard`(`tour_summary_list_screen.dart:11-164`): 리스트 빌드 시 `resumedFromId`가 채워진 log를 만나면 그 직전에 이미 렌더링된(또는 리스트에서 함께 찾은) 원본 카드와 시각적으로 묶어 "이어서 안내됨" 배지 + 합산 거리/시간을 보여주는 병합 카드로 렌더링. 두 원본이 리스트에서 항상 인접하지 않을 수 있음(날짜 그룹 경계 등) — id로 명시적으로 찾아 연결할 것, 인접 가정 금지.
- 스코프: 병합은 **표시 전용**. 상세 화면(탭 시)까지 두 구간을 하나로 합쳐 보여줄지는 이번 스코프에 포함하지 않음(카드 목록에서 "이어서 안내됨"이 드러나면 §S15 체크리스트의 "병합" 요구는 충족) — 더 깊은 통합이 필요하면 리포트에 남기고 마스터 확인.

## 알려진 리스크·주의사항 (감사 시 반드시 확인)

- **재탐색 실패 시 데이터 유실 없음**: `finalizeAsInterrupted`는 재탐색 성공 여부와 무관하게 먼저 호출되므로, `RoutingService.fetchRoutes`가 실패해도 중단 전 구간은 이미 정상 히스토리에 저장된 뒤다 — 사용자가 재개는 못해도 기존 주행 기록은 잃지 않는다.
- **위치 미확보 시 프롬프트 자체를 건너뛴다** — 재탐색 origin 없이 프롬프트만 띄우면 "이어서 안내" 눌러도 실패하는 UX가 되므로, `currentPos == null`이면 아예 묻지 않는다(§3).
- **경합 재검증**: §1에서 `recoverOrphans()`가 재개-가능 고아를 스킵하도록 바꿨으므로, 기존 코드 주석(:66-74)이 경고하던 시나리오는 발생하지 않는다 — 다만 **새 세션이 옛 파일을 재사용하지 않고 항상 새 id로 시작**한다는 전제가 깨지지 않도록, 구현 중 "기존 트랙 파일에 이어쓰기" 같은 최적화 유혹이 생기더라도 하지 말 것.
- **`resumeThresholdHours=null` 호환 경로**를 `recoverOrphans()`에 반드시 유지**할 것 — 기존 단위테스트/호출부가 있다면 깨지지 않아야 한다(청크1 감사 시 기존 테스트 확인).
- **다중 워치포인트 코스**: `RouteResult.first`를 기본 선택하는 MVP 단순화를 명시적으로 문서/리포트에 남길 것(원래 어떤 코스로 달리고 있었는지는 저장하지 않음 — 스코프 밖).

## 검증 요구

- 단위테스트:
  - `TourLog.toJson`/`fromJson`/`copyWith`에 `resumedFromId` 왕복 확인(null↔값 양쪽).
  - `ActiveTourDestinationStore`: record→read 왕복(임시 디렉터리 override 사용, 기존 `tour_recovery_service_test.dart` 등의 `baseDirOverride` 패턴 재사용), 파일 없을 때 read가 null.
  - `TourRecoveryService.recoverOrphans` 확장: (a) `resumeThresholdHours: null`이면 기존 동작 그대로(회귀 없음), (b) 임계치 내 + dest.json 있음 → 스킵(TourLog로 저장 안 됨, 파일 그대로 남음), (c) 임계치 초과 → 기존처럼 즉시 finalize, (d) dest.json 없으면 임계치 내여도 finalize(재개 불가 판정).
  - `findResumableOrphan`: 여러 orphan 중 가장 최근 것만 선택, 조건 불충족 시 null.
  - `finalizeAsInterrupted`: 정상 finalize + dest.json 정리 확인.
  - `ResumeThresholdHoursNotifier`: 기본값 2, set 후 영속 확인(shared_prefs mock).
- `splash_boot_location_test.dart` 기존 테스트 회귀 없는지 확인(순수 함수 `acquireBootLocation`/`awaitWithinBudget`은 이번 변경과 무관해야 함 — `_runSequence()` 내부 흐름만 확장).
- `flutter analyze` 이슈 0, `flutter test` 전건 통과.
- 실기기/가상GPS 검증(마스터 몫, 리포트에 시나리오만 명시): 주행 중 강제 종료 → 2시간 이내 재실행 → 프롬프트 노출 → "이어서 안내" → 현재위치 기준 재탐색 경로로 정상 진입 → 종료 후 히스토리에서 병합 표시 확인. 임계치 초과 케이스(설정 1시간으로 낮추고 1시간+ 대기 후 재실행)도 별도 확인 — 프롬프트 없이 일반 히스토리로 저장되는지.

## 완료 후

- `code-auditor` PASS 후 청크별 커밋(§1~§4 각각), `CHECKLIST_0805_testride0802.md` §S15 세부 체크박스 갱신.
- `loop/MORNING_REPORT_0810_S15_resume_navigation.md`(또는 저녁 세션이므로 `REPORT_` 접두사 — 기존 파일명 관례 확인 후) 작성 — 특히 "재탐색 코스는 자동으로 첫 번째(시골길)만 선택, 사용자 재선택 UI 없음" MVP 스코프 제한을 목표달성 판정에 명시.
