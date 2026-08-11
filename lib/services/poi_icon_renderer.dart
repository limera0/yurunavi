import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/poi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// POI 아이콘 래스터화
// 원격 글리프 서버(AppConfig.instance.tileBaseUrl)는 Noto Sans만 서빙 — Material Icons
// 코드포인트는 없어 SymbolLayer text-field로 직접 렌더링할 수 없다. 그래서
// IconData를 dart:ui로 PNG 비트맵으로 그려 addImage에 등록해 iconImage로 쓴다.
// ─────────────────────────────────────────────────────────────────────────────

// bgColor 원 채우기 + 흰색 원형 테두리 — renderPoiIconPng/renderPlainDotPng가 공유하는
// 시각적 베이스. 두 원의 반지름/선굵기 값은 기존 CircleLayer의
// circleStrokeWidth:2/circleStrokeColor:#FFFFFF와 시각적 일관성을 맞춘 값.
void _drawDotBase(Canvas canvas, double size, Color bgColor) {
  final radius = size / 2;
  canvas.drawCircle(Offset(radius, radius), radius, Paint()..color = bgColor);
  canvas.drawCircle(
    Offset(radius, radius),
    radius - 2,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5,
  );
}

Future<Uint8List> renderPoiIconPng(
  IconData icon,
  Color bgColor, {
  double size = 96,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  _drawDotBase(canvas, size, bgColor);
  // ui. 접두어 명시 — package:intl도 별도의 TextDirection 클래스를 export해
  // 이 파일에서 이름이 충돌한다(intl은 .LTR/.RTL, dart:ui는 .ltr/.rtl).
  final textPainter = TextPainter(textDirection: ui.TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.55,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    )
    ..layout();
  textPainter.paint(
    canvas,
    Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
  );
  final picture = recorder.endRecording();
  // picture는 네이티브 디스플레이리스트를 붙들고 있어 dispose하지 않으면
  // Dart GC 파이널라이저가 돌 때까지 네이티브 메모리가 회수되지 않는다.
  // toImage() 이후 어떤 예외가 나도 새지 않도록 try/finally로 감싼다.
  ui.Image? image;
  try {
    image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    picture.dispose();
    image?.dispose();
  }
}

/// 아이콘 글리프 없이 색이 채워진 원(점)만 그린 PNG — 검색 결과 탭 시 보여주는
/// 임시 위치 미리보기 마커용. `renderPoiIconPng`와 같은 96px 기준/스케일
/// 관례(SymbolLayer에서 iconSize: 0.4로 참조)를 따른다.
Future<Uint8List> renderPlainDotPng(Color color, {double size = 96}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  _drawDotBase(canvas, size, color);
  final picture = recorder.endRecording();
  // renderPoiIconPng와 동일한 이유로 picture/image를 try/finally에서 해제한다.
  ui.Image? image;
  try {
    image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    picture.dispose();
    image?.dispose();
  }
}

/// 경로 진행방향 화살표 PNG — 흰 삼각형·투명 배경 48×48.
/// MapLibre addSymbolLayer(symbolPlacement: 'line')와 함께 쓰인다.
Future<Uint8List> renderRouteArrowPng({double size = 48}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  final path = Path()
    ..moveTo(size / 2, 0)
    ..lineTo(size, size)
    ..lineTo(0, size)
    ..close();
  canvas.drawPath(path, paint);
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    picture.dispose();
    image?.dispose();
  }
}

// POI 카테고리 → 아이콘/배경색 (기존 CircleLayer match 표현식과 동일 색상 유지).
// 이름 규칙 'poi-icon-${PoiType.name}'으로 addImage 등록 및 SymbolLayer에서 참조.
const Map<PoiType, Color> poiIconBgColors = {
  PoiType.cafe: Color(0xFFFF7700),
  PoiType.convenienceStore: Color(0xFF2196F3),
  PoiType.gasStation: Color(0xFFE53935),
  PoiType.supermarket: Color(0xFF8E24AA),
  PoiType.restaurant: Color(0xFFFFB300),
  PoiType.touristSpot: Color(0xFF43A047),
  PoiType.viewpoint: Color(0xFF00ACC1),
};
const Map<PoiType, IconData> poiIcons = {
  PoiType.gasStation: Icons.local_gas_station,
  PoiType.cafe: Icons.local_cafe,
  PoiType.convenienceStore: Icons.local_convenience_store,
  PoiType.supermarket: Icons.shopping_cart,
  PoiType.restaurant: Icons.restaurant,
  PoiType.touristSpot: Icons.landscape,
  PoiType.viewpoint: Icons.visibility,
};
