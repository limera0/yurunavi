import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 투어 상세 화면의 통계 헤더 + 지도를 세로로 합성한 PNG 한 장으로 만들어
/// OS 공유 시트(카카오스토리/인스타/파일저장 등)로 전달한다.
///
/// 지도는 MapLibre 네이티브 플랫폼 뷰라 일반적인 `RepaintBoundary.toImage()`
/// 로는 캡처되지 않을 위험이 있다(별도 텍스처/서피스로 합성되어 빈 화면으로
/// 찍힐 수 있음) — 대신 `maplibre_gl`이 이미 제공하는
/// [ml.MapLibreMapController.takeSnapshot]으로 지도 네이티브 레이어가 직접
/// 반환하는 비트맵을 사용해 이 문제를 우회한다.
///
/// 실기기 렌더링(RepaintBoundary 레이아웃 타이밍, 네이티브 지도 스냅샷,
/// 임시 파일 I/O, 플랫폼 공유 시트)에 걸쳐 있어 각 단계가 개별적으로
/// 실패할 수 있다 — 어떤 단계든 실패하면 예외를 던지지 않고 `false`를
/// 반환한다. 호출부는 `false`를 받으면 스낵바 등으로 사용자에게 실패를
/// 알려야 한다.
Future<bool> shareTourImage({
  required GlobalKey statHeaderKey,
  required ml.MapLibreMapController? mapController,
  required String? memo,
}) async {
  if (mapController == null) return false;

  // headerImage/mapImage/composited는 GPU/네이티브 백업 리소스라
  // 사용이 끝나면 반드시 dispose해야 한다(lib/services/poi_icon_renderer.dart
  // 의 기존 관례). 에러로 중간에 빠져나가도 새는 게 없도록 finally에서
  // 한 번에 정리한다.
  ui.Image? headerImage;
  ui.Image? mapImage;
  ui.Image? composited;
  File? tempFile;
  try {
    final renderObject = statHeaderKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return false;
    // 공유 이미지는 화면 표시용이 아니라 저장/전송용이라, 기기별
    // devicePixelRatio를 따라가기보다 고정된 고배율(3.0)로 캡처해
    // 텍스트가 항상 선명하게 나오도록 한다.
    headerImage = await renderObject.toImage(pixelRatio: 3.0);

    final Uint8List mapBytes;
    try {
      mapBytes = await mapController.takeSnapshot();
    } catch (_) {
      return false;
    }
    mapImage = await _decodeImage(mapBytes);

    composited = await _compositeVertically(headerImage, mapImage);
    final pngData = await composited.toByteData(format: ui.ImageByteFormat.png);
    if (pngData == null) return false;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/tour_share_${DateTime.now().millisecondsSinceEpoch}.png';
    tempFile = File(path);
    await tempFile.writeAsBytes(pngData.buffer.asUint8List(), flush: true);

    // ShareParams는 text가 빈 문자열이면 ArgumentError를 던지므로(공백만
    // 있는 메모 포함), 비어있으면 아예 text를 생략해 이미지만 공유한다.
    final trimmedMemo = memo?.trim();
    final shareText =
        (trimmedMemo != null && trimmedMemo.isNotEmpty) ? trimmedMemo : null;

    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: shareText),
    );
    return true;
  } catch (_) {
    return false;
  } finally {
    headerImage?.dispose();
    mapImage?.dispose();
    composited?.dispose();
    // 공유 시트 호출 성공/실패와 무관하게 임시 파일은 정리한다 — 삭제
    // 실패는 이 함수의 반환값(공유 성공 여부)에 영향을 주지 않는다.
    if (tempFile != null) {
      try {
        await tempFile.delete();
      } catch (_) {
        // 이미 지워졌거나 애초에 쓰기가 실패한 경우 등 — 무시.
      }
    }
  }
}

Future<ui.Image> _decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    // frame.image는 codec과 독립적이라 codec을 먼저 dispose해도 무방하다.
    codec.dispose();
  }
}

/// [containerWidth] 안에서 폭이 [itemWidth]인 이미지를 가로로 가운데
/// 정렬하기 위한 x 오프셋을 계산한다. 위젯/렌더링 없이 순수 계산만
/// 하므로 단위테스트가 가능하도록 컴포지팅 로직에서 분리했다.
double centerHorizontalOffset(int containerWidth, int itemWidth) =>
    (containerWidth - itemWidth) / 2.0;

/// 통계 헤더 이미지를 위에, 지도 스냅샷을 아래에 놓고 세로로 합성한다.
/// 두 이미지의 폭이 다를 수 있으므로(카드형 헤더의 여백 vs 지도 스냅샷의
/// 실제 크기), 어느 쪽도 늘리지 않고 좁은 쪽을 가로로 가운데 정렬한다.
Future<ui.Image> _compositeVertically(ui.Image top, ui.Image bottom) async {
  final width = top.width > bottom.width ? top.width : bottom.width;
  final height = top.height + bottom.height;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.drawImage(
    top,
    Offset(centerHorizontalOffset(width, top.width), 0),
    Paint(),
  );
  canvas.drawImage(
    bottom,
    Offset(centerHorizontalOffset(width, bottom.width), top.height.toDouble()),
    Paint(),
  );

  final picture = recorder.endRecording();
  return picture.toImage(width, height);
}
