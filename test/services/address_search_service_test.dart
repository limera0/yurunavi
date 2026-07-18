import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/models/address_result.dart';
import 'package:yurunavi/services/address_search_service.dart';

void main() {
  group('AddressResult', () {
    test('address/location 필드를 그대로 보관한다', () {
      const result = AddressResult(
        address: '서울특별시 중구 세종대로 110 (태평로1가)',
        location: LatLng(37.566370785810435, 126.9779183412472),
      );

      expect(result.address, '서울특별시 중구 세종대로 110 (태평로1가)');
      expect(result.location.latitude, 37.566370785810435);
      expect(result.location.longitude, 126.9779183412472);
    });
  });

  group('AddressSearchException', () {
    test('toString()에 message가 포함된다', () {
      const ex = AddressSearchException('status=502');
      expect(ex.toString(), contains('status=502'));
    });
  });

  group('AddressSearchService.search', () {
    // PoiService(test/services/poi_service_test.dart)와 마찬가지로 이 프로젝트는
    // 서비스에 주입 가능한 HTTP 클라이언트를 두지 않으므로 실제 네트워크 목(mock)은
    // 만들지 않는다. 대신 순수 로직(빈/공백 질의는 HTTP 호출 없이 즉시 반환)만
    // 결정론적으로 검증한다 — 백엔드가 죽어 있어도, 오프라인이어도 항상 성립해야 함.
    test('빈 질의는 네트워크 호출 없이 즉시 빈 리스트를 반환한다', () async {
      final service = AddressSearchService();

      final result = await service.search('');

      expect(result, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('공백만 있는 질의도 네트워크 호출 없이 즉시 빈 리스트를 반환한다', () async {
      final service = AddressSearchService();

      final result = await service.search('   ');

      expect(result, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 5)));
  });
}
