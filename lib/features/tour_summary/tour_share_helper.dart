import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 투어 상세 화면의 통계 헤더 + 지도를 세로로 합성한 PNG 한 장으로 만들어
/// OS 공유 시트(카카오스토리/인스타/파일저장 등)로 전달한다. 공유는 항상
/// 이미지만 전달한다(텍스트 필드 없음) — 메모가 있으면 호출부가 그 텍스트를
/// 클립보드로 따로 복사해 알려준다.
///
/// 지도는 MapLibre 네이티브 플랫폼 뷰라 일반적인 `RepaintBoundary.toImage()`
/// 로는 캡처되지 않을 위험이 있다(별도 텍스처/서피스로 합성되어 빈 화면으로
/// 찍힐 수 있음) — 대신 `maplibre_gl`이 이미 제공하는
/// [ml.MapLibreMapController.takeSnapshot]으로 지도 네이티브 레이어가 직접
/// 반환하는 비트맵을 사용해 이 문제를 우회한다.
///
/// 실기기 렌더링(RepaintBoundary 레이아웃 타이밍, 네이티브 지도 스냅샷,
/// 임시 파일 I/O, 플랫폼 공유 시트)에 걸쳐 있어 각 단계가 개별적으로
/// 실패할 수 있다. 네이티브 지도 스냅샷([ml.MapLibreMapController.takeSnapshot])
/// 은 일부 실기기에서 타임아웃/오류가 나도 공유 자체를 포기하지 않고
/// 통계 헤더만으로 폴백해 공유한다 — 그 외 단계(헤더 캡처, 파일 쓰기,
/// 공유 시트 호출)가 실패하면 예외를 던지지 않고 `false`를 반환한다.
/// 호출부는 `false`를 받으면 스낵바 등으로 사용자에게 실패를 알려야 한다.
Future<bool> shareTourImage({
  required GlobalKey statHeaderKey,
  required ml.MapLibreMapController? mapController,
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

    // 일부 실기기에서 네이티브 MapSnapshotter가 스타일을 재해석하다
    // 무한 대기에 빠지는 경우가 확인되어(인라인 JSON 스타일 사용 시)
    // 타임아웃을 두고, 실패해도 공유 자체를 포기하지 않고 헤더만으로
    // 폴백한다.
    Uint8List? mapBytes;
    try {
      mapBytes = await mapController
          .takeSnapshot()
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      mapBytes = null;
    } catch (_) {
      mapBytes = null;
    }

    final ByteData? pngData;
    if (mapBytes != null) {
      mapImage = await _decodeImage(mapBytes);
      composited = await _compositeVertically(headerImage, mapImage);
      pngData = await composited.toByteData(format: ui.ImageByteFormat.png);
    } else {
      // 지도 스냅샷을 얻지 못했다 — 지도 없이 헤더(통계 카드)만이라도
      // 공유해 사용자가 빈손으로 남지 않도록 한다.
      pngData = await headerImage.toByteData(format: ui.ImageByteFormat.png);
    }
    if (pngData == null) return false;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/tour_share_${DateTime.now().millisecondsSinceEpoch}.png';
    tempFile = File(path);
    await tempFile.writeAsBytes(pngData.buffer.asUint8List(), flush: true);

    // 메모가 있어도 공유 시트의 텍스트 필드는 항상 비워둔다 — 메모 텍스트는
    // 호출부(tour_summary_detail_screen._shareTour)에서 클립보드로 따로
    // 복사하고, 여기서는 이미지만 공유한다.
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)]),
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
///
/// 두 이미지의 폭이 다를 수 있다 — 헤더는 항상 고정 배율(`pixelRatio: 3.0`)
/// 로 캡처되는 반면, 지도 네이티브 스냅샷은 기기 자체의 화면 밀도를 따라가서
/// 실효 배율이 서로 어긋날 수 있다. 폭만 다르고 늘리지 않은 채 가운데
/// 정렬만 하면 두 이미지의 실제 스케일이 달라 보이므로, 합성 전에 폭이 더
/// 좁은 쪽을 넓은 쪽 폭에 맞춰 (자신의 종횡비를 유지하며) 확대한다. 헤더
/// 쪽을 확대 대상으로 우선하도록 값을 고르는 게 아니라 항상 "더 좁은 쪽"을
/// 키우므로, 어느 쪽이 좁든 화질 손실 없이 업스케일된다.
Future<ui.Image> _compositeVertically(ui.Image top, ui.Image bottom) async {
  final targetWidth = top.width > bottom.width ? top.width : bottom.width;

  final topScale = targetWidth / top.width;
  final topHeight = (top.height * topScale).round();
  final bottomScale = targetWidth / bottom.width;
  final bottomHeight = (bottom.height * bottomScale).round();

  final height = topHeight + bottomHeight;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, targetWidth.toDouble(), height.toDouble()),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, targetWidth.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.drawImageRect(
    top,
    Rect.fromLTWH(0, 0, top.width.toDouble(), top.height.toDouble()),
    Rect.fromLTWH(0, 0, targetWidth.toDouble(), topHeight.toDouble()),
    Paint(),
  );
  canvas.drawImageRect(
    bottom,
    Rect.fromLTWH(0, 0, bottom.width.toDouble(), bottom.height.toDouble()),
    Rect.fromLTWH(0, topHeight.toDouble(), targetWidth.toDouble(), bottomHeight.toDouble()),
    Paint(),
  );

  final picture = recorder.endRecording();
  // picture는 네이티브 디스플레이리스트를 붙들고 있어 dispose하지 않으면
  // Dart GC 파이널라이저가 돌 때까지 네이티브 메모리가 회수되지 않는다
  // (lib/services/poi_icon_renderer.dart와 같은 관례). toImage() 이후
  // 예외가 나도 새지 않도록 try/finally로 감싼다.
  try {
    return await picture.toImage(targetWidth, height);
  } finally {
    picture.dispose();
  }
}
