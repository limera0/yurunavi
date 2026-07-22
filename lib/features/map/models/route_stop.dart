import 'package:latlong2/latlong.dart';

class RouteStop {
  final LatLng latLng;
  final String? name;
  final bool isCurrentLocation;

  const RouteStop({
    required this.latLng,
    this.name,
    this.isCurrentLocation = false,
  });

  RouteStop copyWith({LatLng? latLng, String? name, bool? isCurrentLocation}) =>
      RouteStop(
        latLng: latLng ?? this.latLng,
        name: name ?? this.name,
        isCurrentLocation: isCurrentLocation ?? this.isCurrentLocation,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteStop &&
          runtimeType == other.runtimeType &&
          latLng == other.latLng &&
          name == other.name &&
          isCurrentLocation == other.isCurrentLocation;

  @override
  int get hashCode => Object.hash(latLng, name, isCurrentLocation);
}
