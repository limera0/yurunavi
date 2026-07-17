import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/services/geocoding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 플레인 `flutter test` 환경에는 geocoding 플랫폼 채널 목이 없으므로,
  // 실제 지오코딩 동작은 검증할 수 없다. 이 테스트는 try/catch(또는 타임아웃)로
  // 예외 없이 null을 반환하는지만 확인하는 스모크 테스트다.
  test('reverseGeocode()는 플랫폼 채널이 없을 때 예외 없이 null을 반환한다', () async {
    final service = GeocodingService();

    final result = await service.reverseGeocode(37.0, 127.0);

    expect(result, isNull);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
