import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/poi.dart';
import '../../navigation/providers/nav_state_provider.dart';
import '../../../models/saved_place.dart';
import '../models/route_stop.dart';
import '../../../models/saved_route.dart';
import '../../../models/user_profile.dart';
import '../../../services/daylight_service.dart';
import '../../../services/places_service.dart';
import '../../../services/poi_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/route_service.dart';
import 'package:geolocator/geolocator.dart';

// ── Profile ───────────────────────────────────────────────────────────────────

final profileServiceProvider = Provider((_) => ProfileService());

final userProfileProvider =
    AsyncNotifierProvider<UserProfileNotifier, UserProfile>(
        UserProfileNotifier.new);

class UserProfileNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() async =>
      ref.read(profileServiceProvider).load();

  Future<void> save(UserProfile profile) async {
    state = AsyncData(profile);
    await ref.read(profileServiceProvider).save(profile);
  }
}

// ── Saved Routes ──────────────────────────────────────────────────────────────

final routeServiceProvider = Provider((_) => RouteService());

final savedRoutesProvider =
    AsyncNotifierProvider<SavedRoutesNotifier, List<SavedRoute>>(
        SavedRoutesNotifier.new);

class SavedRoutesNotifier extends AsyncNotifier<List<SavedRoute>> {
  @override
  Future<List<SavedRoute>> build() async =>
      ref.read(routeServiceProvider).loadAll();

  Future<void> add(SavedRoute route) async {
    final next = <SavedRoute>[...(state.value ?? <SavedRoute>[]), route];
    state = AsyncData(next);
    await ref.read(routeServiceProvider).saveAll(next);
  }

  Future<void> remove(String id) async {
    final next =
        (state.value ?? <SavedRoute>[]).where((r) => r.id != id).toList();
    state = AsyncData(next);
    await ref.read(routeServiceProvider).saveAll(next);
  }
}

// ── Location ──────────────────────────────────────────────────────────────────

final locationStreamProvider = StreamProvider<Position>((ref) async* {
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    return;
  }
  ref.keepAlive();
  yield* Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      intervalDuration: const Duration(milliseconds: 1000),
      distanceFilter: 0,
      // 디버그 빌드에서는 classic LocationManager를 강제해 Play Services
      // FusedLocationProviderClient를 우회한다 — 가상 GPS(mock test-provider)로
      // 재생 중에도 FLP가 주기적으로(~60초 간격) 자체 판단의 실측 fix를 섞어
      // 넣는 게 실측 확인됨(고가/지하차도 안내 회귀 테스트 중 발견 — GPS/NETWORK
      // 프로바이더 둘 다 모킹해도 발생, snap이 엉뚱한 shape 인덱스로 튀어
      // 오프루트/오도착을 유발). 릴리스 빌드는 절대 영향 없음(kDebugMode는
      // release에서 컴파일타임 false로 tree-shake됨).
      forceLocationManager: kDebugMode,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: "유루나비 주행 중",
        notificationText: "경로 안내를 위해 위치를 수신하고 있습니다",
        enableWakeLock: true,
      ),
    ),
  );
});

final currentLocationProvider =
    Provider<LatLng?>((ref) => ref.watch(navStateProvider)?.pos);

// ── Map Interaction (pageLayout.md: MapInteractionNotifier) ───────────────────

/// 지도 인터랙션 모드
/// - [idle]                : 초기 상태 (터치 없음)
/// - [destinationSelected] : 목적지 확정, 경로 카드 표시
/// - [waypointSelecting]   : 경유지 선택 대기 중 (다음 탭이 경유지 핀으로 확정)
enum MapInteractionMode { idle, destinationSelected, waypointSelecting }

class MapInteractionState {
  final MapInteractionMode mode;
  final List<RouteStop> stops; // [출발지, 경유지..., 도착지] 통합 리스트
  final double distanceKm;
  final bool isLoading;
  final List<LatLng> routePolyline; // 선택된 카드의 경로 좌표
  final List<List<LatLng>> allRoutes; // 3카드 경로 전체 (Valhalla 3회 병렬 페치)
  final int selectedRouteIdx; // 0: 시골길, 1: 지방도로, 2: 국도
  final List<({double km, int mins, double windingScore})> allRouteMeta; // 각 경로의 거리·시간 메타
  final String? destinationName; // POI 탭 지명 (비동기 해석 전용)

  const MapInteractionState({
    this.mode = MapInteractionMode.idle,
    this.stops = const [],
    this.distanceKm = 0,
    this.isLoading = false,
    this.routePolyline = const [],
    this.allRoutes = const [],
    this.selectedRouteIdx = 2,
    this.allRouteMeta = const [],
    this.destinationName,
  });

  // ── 편의 getter (기존 호출부 호환) ────────────────────────────────────────────

  /// stops[0] — 명시적 출발지 (없으면 null, GPS _origin 로컬변수 사용)
  LatLng? get origin => stops.isEmpty ? null : stops.first.latLng;

  /// stops.last — 도착지 (stops 2개 이상일 때만)
  LatLng? get destination => stops.length < 2 ? null : stops.last.latLng;

  /// stops[1..last-1] — 중간 경유지 좌표 목록
  List<LatLng> get waypoints => stops.length < 3
      ? const []
      : stops.sublist(1, stops.length - 1).map((s) => s.latLng).toList();

  /// stops[1..last-1] — 중간 경유지 지명 목록
  List<String?> get waypointNames => stops.length < 3
      ? const []
      : stops.sublist(1, stops.length - 1).map((s) => s.name).toList();

  /// 단일 경유지 편의 getter (기존 코드 호환)
  LatLng? get waypoint => waypoints.isEmpty ? null : waypoints.last;

  MapInteractionState copyWith({
    MapInteractionMode? mode,
    List<RouteStop>? stops,
    double? distanceKm,
    bool? isLoading,
    List<LatLng>? routePolyline,
    List<List<LatLng>>? allRoutes,
    int? selectedRouteIdx,
    List<({double km, int mins, double windingScore})>? allRouteMeta,
    String? destinationName,
    bool clearStops = false,
    bool clearWaypoints = false,
    bool clearRoute = false,
    bool clearDestinationName = false,
  }) {
    List<RouteStop> resolvedStops;
    if (clearStops) {
      resolvedStops = const [];
    } else if (clearWaypoints && this.stops.length >= 2) {
      // 경유지만 제거: origin + destination 유지
      resolvedStops = [this.stops.first, this.stops.last];
    } else {
      resolvedStops = stops ?? this.stops;
    }
    return MapInteractionState(
      mode: mode ?? this.mode,
      stops: resolvedStops,
      distanceKm: distanceKm ?? this.distanceKm,
      isLoading: isLoading ?? this.isLoading,
      routePolyline: clearRoute ? const [] : routePolyline ?? this.routePolyline,
      allRoutes: clearRoute ? const [] : allRoutes ?? this.allRoutes,
      selectedRouteIdx: selectedRouteIdx ?? this.selectedRouteIdx,
      allRouteMeta: clearRoute ? const [] : allRouteMeta ?? this.allRouteMeta,
      destinationName: clearDestinationName ? null : destinationName ?? this.destinationName,
    );
  }
}

final mapInteractionProvider =
    NotifierProvider<MapInteractionNotifier, MapInteractionState>(
        MapInteractionNotifier.new);

class MapInteractionNotifier extends Notifier<MapInteractionState> {
  @override
  MapInteractionState build() => const MapInteractionState();

  /// 목적지 확정 + 경로 카드 표시 모드로 전환.
  /// [snapshotOrigin]: 목적지 선택 시점의 GPS 위치 — stops[0]으로 고정된다.
  /// stops가 이미 2개 이상이면 기존 출발지(stops[0])를 유지하고 도착지만 교체.
  void setDestination(LatLng dest, double distKm,
      {LatLng? snapshotOrigin, String? name}) {
    final List<RouteStop> newStops;
    if (state.stops.length >= 2) {
      // 출발지 유지, 도착지만 교체
      newStops = [
        ...state.stops.sublist(0, state.stops.length - 1),
        RouteStop(latLng: dest, name: name),
      ];
    } else if (snapshotOrigin != null) {
      // 최초 목적지 선택: GPS 위치를 출발지로 고정
      newStops = [
        RouteStop(latLng: snapshotOrigin, isCurrentLocation: true),
        RouteStop(latLng: dest, name: name),
      ];
    } else {
      // 출발지 미확보 상태 (드물지만 방어)
      newStops = [RouteStop(latLng: dest, name: name)];
    }
    state = state.copyWith(
      stops: newStops,
      mode: MapInteractionMode.destinationSelected,
      distanceKm: distKm,
    );
  }

  /// stops[0]을 명시적으로 설정 (WaypointManagementSheet에서 커스텀 출발지 선택 시)
  void setOrigin(LatLng origin, {String? name}) {
    final stops = [...state.stops];
    final originStop = RouteStop(latLng: origin, name: name, isCurrentLocation: false);
    if (stops.isEmpty) {
      state = state.copyWith(stops: [originStop]);
    } else {
      stops[0] = originStop;
      state = state.copyWith(stops: stops);
    }
  }

  /// 경유지 추가 — stops의 도착지 바로 앞에 삽입
  void addWaypoint(LatLng wp, {String? name}) {
    final stops = [...state.stops];
    final insertIdx = stops.length >= 2 ? stops.length - 1 : stops.length;
    stops.insert(insertIdx, RouteStop(latLng: wp, name: name));
    state = state.copyWith(stops: stops, mode: MapInteractionMode.idle);
  }

  /// 단일 경유지 설정 (기존 API 호환)
  void setWaypoint(LatLng wp) => addWaypoint(wp);

  /// 경유지 선택 대기 모드로 전환
  void startWaypointSelection() {
    state = state.copyWith(mode: MapInteractionMode.waypointSelecting);
  }

  /// 경유지 제거 (idx: waypoints 기준 0-based → stops에서 idx+1)
  void removeWaypoint(int idx) {
    final stops = [...state.stops];
    final stopsIdx = idx + 1; // stops[0]은 출발지
    if (stopsIdx >= stops.length - 1) return; // 도착지는 제거 불가
    stops.removeAt(stopsIdx);
    state = state.copyWith(stops: stops);
  }

  /// stops 전체 순서 변경 (출발지·경유지·도착지 모두 재배치 가능)
  void reorderStop(int oldIdx, int newIdx) {
    final stops = [...state.stops];
    if (oldIdx < 0 || oldIdx >= stops.length) return;
    if (newIdx < 0 || newIdx >= stops.length) return;
    // ReorderableListView delivers newIdx already past the gap when moving downward
    if (newIdx > oldIdx) newIdx -= 1;
    final stop = stops.removeAt(oldIdx);
    stops.insert(newIdx, stop);
    state = state.copyWith(stops: stops);
  }

  void setLoading(bool v) => state = state.copyWith(isLoading: v);

  void setRoutePolyline(List<LatLng> points) =>
      state = state.copyWith(routePolyline: points);

  void setAllRoutes(List<List<LatLng>> routes) =>
      state = state.copyWith(allRoutes: routes);

  void setAllRouteMeta(List<({double km, int mins, double windingScore})> meta) =>
      state = state.copyWith(allRouteMeta: meta);

  void setSelectedRouteIdx(int idx) =>
      state = state.copyWith(selectedRouteIdx: idx);

  void setDestinationName(String? name) => state = state.copyWith(
        destinationName: name,
        clearDestinationName: name == null,
      );

  void reset() => state = const MapInteractionState();
}

// ── Clock tick (drives time-dependent providers) ──────────────────────────────
// Emits DateTime.now() every 30 s so daylight progress + BMNT/EENT labels
// re-render even when the user's GPS position has not changed. Without this
// the daylight gauge was computed once on first location fix and then stuck.
final clockTickProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now(),
  );
});

// ── Daylight ──────────────────────────────────────────────────────────────────

/// API 원격 fetch 트리거 — 위치 변화 시 백그라운드로 nautical twilight 캐시
final _daylightApiFetchProvider = Provider<void>((ref) {
  final loc = ref.watch(currentLocationProvider);
  if (loc == null) return;
  final now = DateTime.now();
  DaylightService.fetchRemote(loc.latitude, loc.longitude, now);
});

final daylightCycleProvider = Provider<DaylightCycleState?>((ref) {
  ref.watch(clockTickProvider);
  ref.watch(_daylightApiFetchProvider); // API 캐시 갱신 연동
  final loc = ref.watch(currentLocationProvider);
  if (loc == null) return null;
  return DaylightService.cycleState(
    lat: loc.latitude,
    lng: loc.longitude,
    now: DateTime.now(),
  );
});

final daylightProgressProvider = Provider<double>((ref) {
  return ref.watch(daylightCycleProvider)?.progress ?? 0.5;
});

final daylightTimesProvider =
    Provider<({DateTime bmnt, DateTime eent})?> ((ref) {
  ref.watch(clockTickProvider); // re-fire on tick
  final loc = ref.watch(currentLocationProvider);
  if (loc == null) return null;
  return DaylightService.calculate(
    lat: loc.latitude,
    lng: loc.longitude,
    date: DateTime.now(),
  );
});

/// 현재 낮/밤 여부 — DaylightBar isNightMode 연동
final isDayProvider = Provider<bool>((ref) {
  return ref.watch(daylightCycleProvider)?.isDay ?? true;
});

// ── POI ───────────────────────────────────────────────────────────────────────

final poiServiceProvider = Provider((_) => PoiService());

final poiListProvider =
    NotifierProvider<_PoiListNotifier, List<Poi>>(_PoiListNotifier.new);

class _PoiListNotifier extends Notifier<List<Poi>> {
  @override
  List<Poi> build() => [];
  void set(List<Poi> pois) => state = pois;
  void clear() => state = [];
}

// ── Places (즐겨찾기 + 최근 경로) ────────────────────────────────────────────

final placesServiceProvider = Provider((_) => PlacesService());

final favoritePlacesProvider =
    AsyncNotifierProvider<FavoritePlacesNotifier, List<FavoritePlace>>(
        FavoritePlacesNotifier.new);

class FavoritePlacesNotifier extends AsyncNotifier<List<FavoritePlace>> {
  @override
  Future<List<FavoritePlace>> build() =>
      ref.read(placesServiceProvider).loadFavorites();

  Future<void> add(FavoritePlace p) async {
    await ref.read(placesServiceProvider).addFavorite(p);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(placesServiceProvider).removeFavorite(id);
    ref.invalidateSelf();
  }
}

/// 즐겨찾기 카테고리 목록(설정 > 즐겨찾기 카테고리 관리에서 편집). 즐겨찾기
/// 등록 시트의 카테고리 선택 칩이 이 목록을 그대로 보여준다.
final favoriteCategoriesProvider =
    AsyncNotifierProvider<FavoriteCategoriesNotifier, List<String>>(
        FavoriteCategoriesNotifier.new);

class FavoriteCategoriesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() =>
      ref.read(placesServiceProvider).loadCategories();

  Future<void> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final current = state.value ?? const <String>[];
    if (current.contains(trimmed)) return;
    final updated = [...current, trimmed];
    await ref.read(placesServiceProvider).saveCategories(updated);
    state = AsyncData(updated);
  }

  Future<void> rename(int index, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final current = [...(state.value ?? const <String>[])];
    if (index < 0 || index >= current.length) return;
    current[index] = trimmed;
    await ref.read(placesServiceProvider).saveCategories(current);
    state = AsyncData(current);
  }

  Future<void> remove(String name) async {
    final current = [...(state.value ?? const <String>[])]..remove(name);
    await ref.read(placesServiceProvider).saveCategories(current);
    state = AsyncData(current);
  }
}

final recentRoutesProvider =
    AsyncNotifierProvider<RecentRoutesNotifier, List<RecentRoute>>(
        RecentRoutesNotifier.new);

class RecentRoutesNotifier extends AsyncNotifier<List<RecentRoute>> {
  @override
  Future<List<RecentRoute>> build() =>
      ref.read(placesServiceProvider).loadRecent();

  Future<void> add(RecentRoute r) async {
    await ref.read(placesServiceProvider).addRecent(r);
    ref.invalidateSelf();
  }
}

// ── Route type filter ─────────────────────────────────────────────────────────

enum RouteTypeFilter { country, provincial, national }

final routeTypeFilterProvider =
    NotifierProvider<_RouteTypeNotifier, RouteTypeFilter>(
        _RouteTypeNotifier.new);

class _RouteTypeNotifier extends Notifier<RouteTypeFilter> {
  @override
  RouteTypeFilter build() => RouteTypeFilter.national;
  void set(RouteTypeFilter t) => state = t;
}
