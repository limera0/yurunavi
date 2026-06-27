import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/poi.dart';
import '../../navigation/providers/nav_state_provider.dart';
import '../../../models/saved_place.dart';
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
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
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
  final LatLng? destination;
  final List<LatLng> waypoints; // 다중 경유지
  final double distanceKm;
  final bool isLoading;
  final List<LatLng> routePolyline; // 선택된 카드의 경로 좌표
  final List<List<LatLng>> allRoutes; // 3카드 경로 전체 (Valhalla 3회 병렬 페치)
  final int selectedRouteIdx; // 0: 시골길, 1: 지방도로, 2: 국도
  final List<({double km, int mins, double windingScore})> allRouteMeta; // 각 경로의 거리·시간 메타

  const MapInteractionState({
    this.mode = MapInteractionMode.idle,
    this.destination,
    this.waypoints = const [],
    this.distanceKm = 0,
    this.isLoading = false,
    this.routePolyline = const [],
    this.allRoutes = const [],
    this.selectedRouteIdx = 2,
    this.allRouteMeta = const [],
  });

  /// 단일 경유지 편의 getter (기존 코드 호환)
  LatLng? get waypoint => waypoints.isEmpty ? null : waypoints.last;

  MapInteractionState copyWith({
    MapInteractionMode? mode,
    LatLng? destination,
    List<LatLng>? waypoints,
    double? distanceKm,
    bool? isLoading,
    List<LatLng>? routePolyline,
    List<List<LatLng>>? allRoutes,
    int? selectedRouteIdx,
    List<({double km, int mins, double windingScore})>? allRouteMeta,
    bool clearDestination = false,
    bool clearWaypoints = false,
    bool clearRoute = false,
  }) {
    return MapInteractionState(
      mode: mode ?? this.mode,
      destination: clearDestination ? null : destination ?? this.destination,
      waypoints: clearWaypoints ? [] : waypoints ?? this.waypoints,
      distanceKm: distanceKm ?? this.distanceKm,
      isLoading: isLoading ?? this.isLoading,
      routePolyline: clearRoute ? [] : routePolyline ?? this.routePolyline,
      allRoutes: clearRoute ? [] : allRoutes ?? this.allRoutes,
      selectedRouteIdx: selectedRouteIdx ?? this.selectedRouteIdx,
      allRouteMeta: clearRoute ? [] : allRouteMeta ?? this.allRouteMeta,
    );
  }
}

final mapInteractionProvider =
    NotifierProvider<MapInteractionNotifier, MapInteractionState>(
        MapInteractionNotifier.new);

class MapInteractionNotifier extends Notifier<MapInteractionState> {
  @override
  MapInteractionState build() => const MapInteractionState();

  /// 목적지 확정 + 경로 카드 표시 모드로 전환
  void setDestination(LatLng dest, double distKm) {
    state = state.copyWith(
      mode: MapInteractionMode.destinationSelected,
      destination: dest,
      distanceKm: distKm,
    );
  }

  /// 경유지 추가 (다중 경유지 지원)
  void addWaypoint(LatLng wp) {
    state = state.copyWith(
      waypoints: [...state.waypoints, wp],
      mode: MapInteractionMode.idle,
    );
  }

  /// 단일 경유지 설정 (기존 API 호환)
  void setWaypoint(LatLng wp) => addWaypoint(wp);

  /// 경유지 선택 대기 모드로 전환
  void startWaypointSelection() {
    state = state.copyWith(mode: MapInteractionMode.waypointSelecting);
  }

  /// 경유지 제거
  void removeWaypoint(int idx) {
    final updated = [...state.waypoints]..removeAt(idx);
    state = state.copyWith(waypoints: updated);
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

// ── Night mode (auto-detect via BMNT/EENT) ────────────────────────────────────

/// 현재 밤 여부 — isDayProvider 의 역수. 야간 UI 연동 시 사용.
final isNightProvider = Provider<bool>((ref) => !ref.watch(isDayProvider));

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

// ── Rider Mode ────────────────────────────────────────────────────────────────

/// Toggles High-Contrast Rider Mode (pitch black / neon green / safety orange).
/// When true the app switches to [AppTheme.rider] and map overlays use
/// [RiderModeColors] for maximum sunlight legibility.
final riderModeProvider =
    NotifierProvider<_RiderModeNotifier, bool>(_RiderModeNotifier.new);

class _RiderModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void set(bool v) => state = v;
}
