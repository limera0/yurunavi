// S8 §5 — 상단 카드 남은거리 10km+ 줄바꿈 회귀 가드.
//
// 배경: HANDOFF_0807_S8_ui_remainder.md §5. NavTopCard(nav_top_card.dart)로
// 분리된 독립 컴포넌트라 nav_screen.dart 전체(GPS/TTS/MapLibre 채널 모킹)를
// 마운트하지 않고도 검증 가능 — DaylightBar/RearCameraGauge와 동일 패턴
// (test/core/widgets/daylight_bar_test.dart 참고).
//
// 여러 자리수(0~4자리) + 도로명 길이 조합 × 실기기에 가까운 화면 폭에서
// RenderFlex overflow 등 레이아웃 예외가 없는지 경계 테스트한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/presentation/nav_top_card.dart';

/// 실기기 논리 폭 근사값: 갤럭시 플립7 커버(285 높이 화면과 짝인 좁은 폭
/// 기기 근사), 일반 소형 안드로이드(360), 흔한 중형(393/412), 큰 화면(480).
const _screenWidths = <double>[300, 360, 393, 412, 480];

const _distCombos = <(String, String)>[
  ('0', 'm'), // 최소 폭 fallback('' 케이스는 아래 별도 테스트)
  ('50', 'm'),
  ('999', 'm'),
  ('1.0', 'km'),
  ('9.9', 'km'),
  ('10.0', 'km'), // 회귀 대상 — 기존 고정폭에서 줄바꿈되던 경계
  ('88.8', 'km'), // 마스터가 명시한 최악 케이스
  ('100.0', 'km'), // 4자리+소수점
];

const _streetNames = <String?>[
  null,
  '혜화로',
  '서울특별시 강남대로',
  '경기도 평택시 진위면 견산리 산업단지로 123번길', // 긴 도로명 최악 케이스
];

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required String distMain,
  required String distUnit,
  String? streetName,
  bool arrivalBannerVisible = false,
  String? arrivalDurationText,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 900));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              child: SizedBox(
                width: width,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: NavTopCard(
                    svgAsset: 'assets/images/nav_icons/nav_straight.svg',
                    minWidth: width * 0.62,
                    maxWidth: width - 12,
                    distMain: distMain,
                    distUnit: distUnit,
                    streetName: streetName,
                    arrivalBannerVisible: arrivalBannerVisible,
                    arrivalDurationText: arrivalDurationText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('NavTopCard — 남은거리 자릿수 × 도로명 길이 × 화면폭 조합 overflow 없음', () {
    for (final width in _screenWidths) {
      for (final dist in _distCombos) {
        for (final street in _streetNames) {
          testWidgets(
            'width=${width}px dist=${dist.$1}${dist.$2} street=${street ?? "(없음)"}',
            (tester) async {
              await _pump(
                tester,
                width: width,
                distMain: dist.$1,
                distUnit: dist.$2,
                streetName: street,
              );
              await tester.pump();
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('NavTopCard — 도착 배너 분기도 overflow 없음', () {
    for (final width in _screenWidths) {
      testWidgets('width=${width}px 도착 배너 + 긴 소요시간 문구', (tester) async {
        await _pump(
          tester,
          width: width,
          distMain: '',
          distUnit: '',
          arrivalBannerVisible: true,
          arrivalDurationText: '소요시간 3시간 25분 10초',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('컨텐츠가 minWidth보다 좁아도 카드 폭은 minWidth 밑으로 줄지 않는다', (tester) async {
    const width = 400.0;
    await _pump(tester, width: width, distMain: '1', distUnit: 'm');
    await tester.pump();
    expect(tester.takeException(), isNull);

    final renderBox = tester.renderObject<RenderBox>(find.byType(NavTopCard));
    expect(renderBox.size.width, greaterThanOrEqualTo(width * 0.62));
  });

  testWidgets('88.8km + 최장 도로명 조합에서 카드 폭이 화면 밖으로 넘치지 않는다', (tester) async {
    const width = 360.0;
    await _pump(
      tester,
      width: width,
      distMain: '88.8',
      distUnit: 'km',
      streetName: '경기도 평택시 진위면 견산리 산업단지로 123번길',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final renderBox = tester.renderObject<RenderBox>(find.byType(NavTopCard));
    expect(renderBox.size.width, lessThanOrEqualTo(width - 12));
  });
}
