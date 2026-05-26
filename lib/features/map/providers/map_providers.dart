import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/poi.dart';
import '../../../models/saved_route.dart';
import '../../../models/user_profile.dart';
import '../../../services/daylight_service.dart';
import '../../../services/poi_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/route_service.dart';

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

final currentLocationProvider =
    NotifierProvider<_LatLngNotifier, LatLng?>(_LatLngNotifier.new);

class _LatLngNotifier extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;
  void set(LatLng loc) => state = loc;
}

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
  final List<LatLng> routePolyline; // 계산된 경로 좌표
  final int selectedRouteIdx; // 0: 시골길, 1: 지방도로, 2: 국도

  const MapInteractionState({
    this.mode = MapInteractionMode.idle,
    this.destination,
    this.waypoints = const [],
    this.distanceKm = 0,
    this.isLoading = false,
    this.routePolyline = const [],
    this.selectedRouteIdx = 2,
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
    int? selectedRouteIdx,
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
      selectedRouteIdx: selectedRouteIdx ?? this.selectedRouteIdx,
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

  void setSelectedRouteIdx(int idx) =>
      state = state.copyWith(selectedRouteIdx: idx);

  void reset() => state = const MapInteractionState();
}

// ── Daylight ──────────────────────────────────────────────────────────────────

final daylightProgressProvider = Provider<double>((ref) {
  final loc = ref.watch(currentLocationProvider);
  if (loc == null) return 0.5;
  return DaylightService.daylightProgress(
    lat: loc.latitude,
    lng: loc.longitude,
    now: DateTime.now(),
  );
});

final daylightTimesProvider =
    Provider<({DateTime bmnt, DateTime eent})?> ((ref) {
  final loc = ref.watch(currentLocationProvider);
  if (loc == null) return null;
  return DaylightService.calculate(
    lat: loc.latitude,
    lng: loc.longitude,
    date: DateTime.now(),
  );
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
