import 'package:flutter/material.dart';

abstract class AppSkin {
  String get id;
  String get displayName;
  bool get isPremium;

  SkinColors get colors;
  SkinTypography get typography;
  SkinMotion get motion;
  SkinShapes get shapes;

  ThemeData toThemeData();
}

abstract class SkinColors {
  // 브랜드
  Color get brand;
  Color get onBrand;
  Color get brandLight;

  // 배경/표면
  Color get background;
  Color get surface;
  Color get surfaceVariant;

  // 텍스트
  Color get onSurface;
  Color get onSurfaceVariant;

  // 시맨틱
  Color get danger;
  Color get warning;
  Color get success;

  // 내비 전용
  Color get routeLine;
  Color get structureAlert;
  Color get curveAlert;
  Color get speedometerBg;

  /// 코스 인덱스별 경로선 색 (0: 시골길/scenic, 1: 지방도/regional, 2: 국도/fast).
  /// 레거시 최상위 courseLineColor map과 동일한 키 규약.
  Map<int, Color> get courseLineColor;
}

abstract class SkinTypography {
  String get fontFamily;

  TextStyle get headlineXL;   // 38px bold — 내비 거리 숫자
  TextStyle get headlineL;    // 22px bold
  TextStyle get headlineM;    // 20px bold
  TextStyle get bodyL;        // 16px
  TextStyle get bodyM;        // 14px
  TextStyle get labelM;       // 13px
  TextStyle get labelS;       // 12px
  TextStyle get mono;         // 속도계 숫자
}

abstract class SkinMotion {
  Duration get fast;       // 150ms
  Duration get standard;   // 300ms
  Duration get slow;       // 600ms
  Duration get pulse;      // 700ms — nav 펄스
  Curve get defaultCurve;
  Curve get emphasizedCurve;
}

abstract class SkinShapes {
  double get radiusXS;   // 8
  double get radiusS;    // 14
  double get radiusM;    // 16
  double get radiusL;    // 20
  double get radiusXL;   // 24
}
