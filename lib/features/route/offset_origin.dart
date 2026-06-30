import 'dart:math';

class LatLng2 {
  final double lat, lng;
  const LatLng2(this.lat, this.lng);
}

LatLng2 offsetOrigin(double lat, double lng, double? headingDeg, double meters) {
  if (headingDeg == null) return LatLng2(lat, lng);
  const R = 6371000.0;
  final hdg = headingDeg * pi / 180;
  final dLat = meters * cos(hdg) / R;
  final dLng = meters * sin(hdg) / (R * cos(lat * pi / 180));
  return LatLng2(lat + dLat * 180 / pi, lng + dLng * 180 / pi);
}
