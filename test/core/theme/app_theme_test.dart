// S8 §1 — AppBarTheme.systemOverlayStyle이 kSystemBarColor와 어긋나지 않게
// 하는 회귀 가드.
//
// 배경: HANDOFF_0807_S8_ui_remainder.md §1. Flutter의 AppBar는
// systemOverlayStyle을 명시하지 않으면 자기 backgroundColor 밝기에서 스스로
// 계산해 매 빌드마다 SystemChrome.setSystemUIOverlayStyle을 재호출한다 —
// 이게 main.dart/nav_screen.dart가 전역으로 걸어둔 kSystemBarColor 통일을
// 조용히 덮어써 AppBar를 쓰는 5개 화면(히스토리/즐겨찾기 카테고리/프로필/
// 설정/약관)에서 색이 어긋나 보였다. app_theme.dart의 AppBarTheme에
// systemOverlayStyle을 명시해 전 AppBar 화면에 일괄 적용한다.
//
// 구현 메모: AppTheme.light는 GoogleFonts.plusJakartaSans*를 호출한다.
// 네트워크가 없는 이 저장소의 테스트 샌드박스에서는 백그라운드 폰트 로드가
// 실패하는데, 그 실패가 plain test() 하나와 testWidgets() 하나로 이
// AppTheme.light를 각각 따로 호출하는 두 테스트로 나눠 실행하면(둘 다 같은
// 파일 = 같은 isolate 안에서 실행되어 google_fonts 내부 전역 상태를
// 공유한다) 타이밍이 겹쳐 서로에게 "테스트 완료 후 예외" 잡음을 유발했다
// (2026-08-07 실측). 하나의 testWidgets() 안에서 AppTheme.light를 단 한
// 번만 평가해 이 교차 오염을 피한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yurunavi/core/theme/app_theme.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets(
    'AppBarTheme.systemOverlayStyle 값이 kSystemBarColor 조합과 일치하고 '
    'AppBar를 쓰는 화면에 실제로 적용된다',
    (tester) async {
      final theme = AppTheme.light;
      final overlayStyle = theme.appBarTheme.systemOverlayStyle;

      expect(overlayStyle, isNotNull);
      expect(overlayStyle!.statusBarColor, kSystemBarColor);
      expect(overlayStyle.statusBarIconBrightness, Brightness.dark);
      expect(overlayStyle.systemNavigationBarColor, kSystemBarColor);
      expect(overlayStyle.systemNavigationBarIconBrightness, Brightness.dark);
      expect(overlayStyle.systemNavigationBarContrastEnforced, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            appBar: AppBar(title: const Text('테스트 화면')),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      final appBarWidget = tester.widget<AppBar>(find.byType(AppBar));
      // AppBar 위젯 자체에 systemOverlayStyle을 안 넘겼으면(화면별 5곳을
      // 패치하는 대신 테마 한 곳에서 일괄 적용하는 게 이번 수정의 핵심이므로)
      // null이어야 하고, 테마의 AppBarTheme가 대신 값을 채운다.
      expect(appBarWidget.systemOverlayStyle, isNull);

      final resolvedTheme = Theme.of(tester.element(find.byType(AppBar)));
      expect(
        resolvedTheme.appBarTheme.systemOverlayStyle?.statusBarColor,
        kSystemBarColor,
      );
      expect(
        resolvedTheme.appBarTheme.systemOverlayStyle?.systemNavigationBarColor,
        kSystemBarColor,
      );
    },
  );
}
