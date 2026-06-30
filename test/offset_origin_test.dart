import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/route/offset_origin.dart';

double _haversine(double aLat,double aLng,double bLat,double bLng){
  const r=6371000.0; double rad(double d)=>d*math.pi/180;
  final dLat=rad(bLat-aLat), dLng=rad(bLng-aLng);
  final h=math.pow(math.sin(dLat/2),2)+math.cos(rad(aLat))*math.cos(rad(bLat))*math.pow(math.sin(dLng/2),2);
  return 2*r*math.asin(math.min(1,math.sqrt(h)));
}

void main() {
  group('offsetOrigin', () {
    test('정북0° 위도↑ 경도=', (){final o=offsetOrigin(37,127,0,50);
      expect(o.lat,greaterThan(37)); expect(o.lng,closeTo(127,1e-6));});
    test('정동90° 경도↑', ()=>expect(offsetOrigin(37,127,90,50).lng,greaterThan(127)));
    test('정남180° 위도↓', ()=>expect(offsetOrigin(37,127,180,50).lat,lessThan(37)));
    test('정서270° 경도↓', ()=>expect(offsetOrigin(37,127,270,50).lng,lessThan(127)));
    test('50m 거리 ±5m', ()=>expect(_haversine(37,127,offsetOrigin(37,127,45,50).lat,offsetOrigin(37,127,45,50).lng),closeTo(50,5)));
    test('heading null 폴백', (){final o=offsetOrigin(37,127,null,50);
      expect(o.lat,37); expect(o.lng,127);});
  });
}
