// 후면단속카메라 접근/사후구간 게이지 위젯 (18번 기능 Phase 2 UI).
//
// nav_screen.dart 좌측 속도계(_Speedometer, 88x88)가 카메라 접근 시 이
// 파일의 위젯들로 "변신"한다. 위젯들은 순수하게 원시 데이터(거리·활성여부)만
// 받아 스스로 렌더링하는 독립 컴포넌트라 nav_screen.dart 전체를 마운트하지
// 않고도 위젯 테스트로 검증할 수 있다(DaylightBar와 동일한 패턴,
// lib/core/widgets/daylight_bar.dart 참조).
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 숫자가 바뀔 때만 짧게 깜빡이는 공용 로직 — 접근 게이지의 "남은 거리",
/// 사후구간 게이지의 "카운트다운" 둘 다 이 믹스인을 쓴다. 라벨(단위 텍스트)은
/// 이 애니메이션과 무관하게 항상 고정 표시된다.
mixin _DigitBlinkMixin<T extends StatefulWidget> on State<T>, TickerProvider {
  late final AnimationController blinkCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> blinkAnim = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.2), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 0.2, end: 1.0), weight: 50),
  ]).animate(CurvedAnimation(parent: blinkCtrl, curve: Curves.easeInOut));

  int? _lastShownValue;

  /// 표시할 정수값이 이전 build와 달라졌으면 블링크를 재생한다.
  void triggerBlinkIfChanged(int shownValue) {
    if (_lastShownValue != null && _lastShownValue != shownValue) {
      blinkCtrl
        ..reset()
        ..forward();
    }
    _lastShownValue = shownValue;
  }

  void disposeBlink() => blinkCtrl.dispose();
}

/// 후면단속카메라 접근구간(150m→0m) 게이지 — "SEC." 웨지 스타일 오마주.
///
/// 남은 거리(distanceM)가 150m→0m으로 줄어들수록 붉은 부채꼴이 선형으로
/// 줄어들며(=검정으로 대체) 진행률을 나타낸다. 초록 쐐기·노란 눈금호는
/// 거리와 무관한 고정 장식 요소(크기 변화 없음).
class CameraApproachGauge extends StatefulWidget {
  static const double kThresholdM = 150.0;
  static const double kSize = 176.0;

  /// 다음 카메라까지 남은 거리(m). 음수/threshold 초과 값은 표시 시 clamp된다.
  final double distanceM;

  const CameraApproachGauge({super.key, required this.distanceM});

  @override
  State<CameraApproachGauge> createState() => _CameraApproachGaugeState();
}

class _CameraApproachGaugeState extends State<CameraApproachGauge>
    with SingleTickerProviderStateMixin, _DigitBlinkMixin<CameraApproachGauge> {
  @override
  void didUpdateWidget(covariant CameraApproachGauge old) {
    super.didUpdateWidget(old);
    triggerBlinkIfChanged(_shownM);
  }

  int get _shownM =>
      widget.distanceM.clamp(0.0, CameraApproachGauge.kThresholdM).round();

  @override
  void dispose() {
    disposeBlink();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fraction =
        (widget.distanceM / CameraApproachGauge.kThresholdM).clamp(0.0, 1.0);
    return SizedBox(
      width: CameraApproachGauge.kSize,
      height: CameraApproachGauge.kSize,
      child: CustomPaint(
        painter: _ApproachGaugePainter(fraction: fraction),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: blinkAnim,
                child: Text(
                  '$_shownM',
                  style: const TextStyle(
                    fontFamily: 'DSEG7Classic',
                    fontSize: 40,
                    color: Colors.white,
                    height: 1.0,
                    shadows: [
                      Shadow(color: Color(0xFFFFC107), blurRadius: 10),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'METER.',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApproachGaugePainter extends CustomPainter {
  final double fraction; // 0(0m)~1(150m 이상 남음)
  const _ApproachGaugePainter({required this.fraction});

  // 레퍼런스(speedcam1.webp) 극좌표 분석 결과: 붉은 스타버스트가 실제로 그려진
  // 100°(78°~178°, 화면 중심 기준) 구간 안에서 스포크 간 간격(seam)이 정확히
  // 7개, 피치 14.3°로 검출됨 — 360°로 환산하면 360/14.3≈25개(2026-07-29).
  static const _spokeCount = 25;
  static const _red = Color(0xFFE8231B);
  static const _gold = Color(0xFFFFC107);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // 검정 베이스 디스크
    canvas.drawCircle(center, r - 6, Paint()..color = Colors.black);

    // 방사형 붉은 "스타버스트" 스포크 — 원작(rear_cctv_3)의 부채꼴이 단색
    // 채움이 아니라 중심에서 뻗어나오는 가느다란 광선 다발로 보이는 질감을
    // 근사한다. fraction(남은거리/150)만큼만 12시에서 시계방향으로 스포크가
    // 존재하고, 나머지는 검정 베이스가 그대로 드러나 "붉은색이 검은색으로
    // 줄어드는" 원래 요구사항을 그대로 만족한다.
    final sweepSpokes = (_spokeCount * fraction).ceil();
    final spokePaint = Paint()..color = _red;
    for (int i = 0; i < sweepSpokes; i++) {
      final a0 = -math.pi / 2 + (2 * math.pi * i / _spokeCount);
      final a1 = a0 + (2 * math.pi / _spokeCount) * 0.62; // 스포크 사이 검정 갭
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + (r - 6) * math.cos(a0), center.dy + (r - 6) * math.sin(a0))
        ..lineTo(center.dx + (r - 6) * math.cos(a1), center.dy + (r - 6) * math.sin(a1))
        ..close();
      canvas.drawPath(path, spokePaint);
    }
    // 스포크 안쪽에 은은한 글로우를 더해 단색 삼각형보다 빛나 보이게.
    canvas.drawCircle(
      center,
      r * 0.32,
      Paint()
        ..color = _red.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // 바깥 금색 테두리
    canvas.drawCircle(
      center,
      r - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = _gold,
    );

    // 중앙 판독 박스(노란 테두리 + 위 초록/아래 빨강 분할) — 원작의 "SEC."
    // 박스를 화면 중앙에 재배치한 버전. 항상 고정 표시(거리와 무관한 장식).
    final boxRect = Rect.fromCenter(center: center, width: r * 1.12, height: r * 1.0);
    final boxRRect = RRect.fromRectAndRadius(boxRect, const Radius.circular(10));
    canvas.save();
    canvas.clipRRect(boxRRect);
    canvas.drawRect(
      Rect.fromLTRB(boxRect.left, boxRect.top, boxRect.right, boxRect.top + boxRect.height * 0.68),
      Paint()..color = const Color(0xFF2E7D32).withValues(alpha: 0.55),
    );
    canvas.drawRect(
      Rect.fromLTRB(boxRect.left, boxRect.top + boxRect.height * 0.68, boxRect.right, boxRect.bottom),
      Paint()..color = const Color(0xFFEF6C00).withValues(alpha: 0.55),
    );
    canvas.restore();
    canvas.drawRRect(
      boxRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = _gold,
    );
  }

  @override
  bool shouldRepaint(covariant _ApproachGaugePainter old) =>
      old.fraction != fraction;
}

/// 0m 도달 순간(inPostZone false→true) 전환 플래시 — 게이지 위젯 내부가
/// 빠르게(약 0.3초) 빨강으로 가득 차는 연출. 애니메이션이 끝나면
/// [onComplete]를 호출해 호출자가 이 위젯을 트리에서 제거하게 한다.
class CameraTransitionFlash extends StatefulWidget {
  final double size;
  final VoidCallback onComplete;
  const CameraTransitionFlash({
    super.key,
    this.size = CameraApproachGauge.kSize,
    required this.onComplete,
  });

  @override
  State<CameraTransitionFlash> createState() => _CameraTransitionFlashState();
}

class _CameraTransitionFlashState extends State<CameraTransitionFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          // 확산: 스케일 0.2→1.0, 앞부분에서 빠르게 꽉 찼다가 끝에서 살짝 페이드.
          final scale = Curves.easeOutExpo.transform(_ctrl.value);
          final opacity = _ctrl.value < 0.75
              ? 1.0
              : 1.0 - (_ctrl.value - 0.75) / 0.25;
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.15 + 0.85 * scale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE53935),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 후면단속카메라 사후구간(0m→postZoneM) 게이지 — 점-링 "SLOW" 스타일.
///
/// 중앙 숫자는 postZoneM→0 실거리 기반 카운트다운. 둘레 24개 점은 실거리와
/// 무관한 장식용 애니메이션(1초 주기, 12시 방향부터 반시계로 순차 점등 후
/// 전체소등 반복) — 사후구간에 머무는 동안 계속 반복된다.
class CameraPostZoneGauge extends StatefulWidget {
  static const double kSize = 176.0;

  /// postZoneM - distToNextCameraM (>= 0). 0에 도달하면 사후구간 종료.
  final double remainingM;

  const CameraPostZoneGauge({super.key, required this.remainingM});

  @override
  State<CameraPostZoneGauge> createState() => _CameraPostZoneGaugeState();
}

class _CameraPostZoneGaugeState extends State<CameraPostZoneGauge>
    with TickerProviderStateMixin, _DigitBlinkMixin<CameraPostZoneGauge> {
  late final AnimationController _dotCtrl;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant CameraPostZoneGauge old) {
    super.didUpdateWidget(old);
    triggerBlinkIfChanged(_shownM);
  }

  int get _shownM => widget.remainingM.clamp(0.0, double.maxFinite).round();

  @override
  void dispose() {
    _dotCtrl.dispose();
    disposeBlink();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CameraPostZoneGauge.kSize,
      height: CameraPostZoneGauge.kSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(CameraPostZoneGauge.kSize, CameraPostZoneGauge.kSize),
            painter: _PostZoneFramePainter(),
          ),
          AnimatedBuilder(
            animation: _dotCtrl,
            builder: (context, child) => CustomPaint(
              size: const Size(CameraPostZoneGauge.kSize, CameraPostZoneGauge.kSize),
              painter: _DotRingPainter(progress: _dotCtrl.value),
            ),
          ),
          const _CircularSlowLabel(radius: 34),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FadeTransition(
              opacity: blinkAnim,
              child: Text(
                '$_shownM',
                style: const TextStyle(
                  fontFamily: 'DSEG7Classic',
                  fontSize: 34,
                  color: Colors.white,
                  height: 1.0,
                  shadows: [
                    Shadow(color: Color(0xFFFFC107), blurRadius: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 사후구간 게이지 배경 — 원작(rear_cctv_1)처럼 전체를 붉게 채우고, 중앙에
/// 별도의 초록 원(판독창)을 얹은 뒤, 나침반 방향(N/E/S/W) 마커와 굵은 금색
/// 테두리로 마무리한다. 거리/애니메이션과 무관한 고정 레이어.
class _PostZoneFramePainter extends CustomPainter {
  static const _gold = Color(0xFFFFC107);
  static const _redFill = Color(0xFFE8231B);
  static const _green = Color(0xFF3C9F40);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // 붉은 베이스 디스크 (원작: 화면 전체가 빨강으로 가득 찬 상태)
    canvas.drawCircle(center, r - 6, Paint()..color = _redFill);

    // 은은한 방사형 스포크 텍스처 (검정 반투명 선, 접근 게이지의 스타버스트와
    // 대칭되는 장식)
    final spokePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1.4;
    for (int i = 0; i < 24; i++) {
      final a = 2 * math.pi * i / 24;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * (r * 0.30),
        center + Offset(math.cos(a), math.sin(a)) * (r - 20),
        spokePaint,
      );
    }

    // 나침반 마커 (N/E/S/W, 안쪽을 향한 작은 삼각형)
    final markerPaint = Paint()..color = const Color(0xFFCFE8FF);
    for (final deg in [-90.0, 0.0, 90.0, 180.0]) {
      final a = deg * math.pi / 180;
      final tip = center + Offset(math.cos(a), math.sin(a)) * (r - 14);
      final perp = a + math.pi / 2;
      final baseCenter = center + Offset(math.cos(a), math.sin(a)) * (r - 22);
      final baseA = baseCenter + Offset(math.cos(perp), math.sin(perp)) * 4;
      final baseB = baseCenter - Offset(math.cos(perp), math.sin(perp)) * 4;
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(baseA.dx, baseA.dy)
        ..lineTo(baseB.dx, baseB.dy)
        ..close();
      canvas.drawPath(path, markerPaint);
    }

    // 중앙 초록 판독창 + 방사형 눈금
    final greenCenter = center;
    const greenR = 46.0;
    canvas.drawCircle(greenCenter, greenR, Paint()..color = _green);
    final tickPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..strokeWidth = 1.2;
    for (int i = 0; i < 16; i++) {
      final a = 2 * math.pi * i / 16;
      canvas.drawLine(
        greenCenter + Offset(math.cos(a), math.sin(a)) * (greenR - 10),
        greenCenter + Offset(math.cos(a), math.sin(a)) * greenR,
        tickPaint,
      );
    }
    canvas.drawCircle(
      greenCenter,
      greenR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _gold.withValues(alpha: 0.8),
    );

    // 바깥 금색 테두리 (굵게)
    canvas.drawCircle(
      center,
      r - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..color = _gold,
    );
  }

  @override
  bool shouldRepaint(covariant _PostZoneFramePainter old) => false;
}

/// 둘레 24개 점 — 실거리와 무관한 장식용 스윕. progress(0..1, 1초 1사이클)
/// 기준 12시부터 반시계로 순차 점등, 한 바퀴 완료 직후(다음 사이클 시작)
/// 전체소등 상태로 돌아간다. 개수·점 반경은 원작 레퍼런스(speedcam2.webp)
/// 점-링을 connected-component 분석해 확정(24개, area 기준 삼각형 틱마커와
/// 뚜렷이 분리됨 — 2026-07-29).
class _DotRingPainter extends CustomPainter {
  final double progress;
  const _DotRingPainter({required this.progress});

  static const _dotCount = 24;
  static const _lit = Color(0xFFFFF8E1);
  static const _unlit = Color(0xFF6B1616);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 12;
    final onPaint = Paint()..color = _lit;
    final offPaint = Paint()..color = _unlit;
    final onGlow = Paint()
      ..color = _lit.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (int i = 0; i < _dotCount; i++) {
      final lit = progress >= i / _dotCount;
      // 12시(-90°)에서 시작해 반시계(각도 감소) 방향으로 배치.
      final angle = -math.pi / 2 - (2 * math.pi * i / _dotCount);
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * r;
      if (lit) canvas.drawCircle(pos, 9.5, onGlow);
      canvas.drawCircle(pos, 6.5, lit ? onPaint : offPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotRingPainter old) => old.progress != progress;
}

/// "SLOW" 4글자를 중앙 초록 원 안쪽 아랫변을 따라 곡선으로 배치하는 고정
/// 장식 텍스트(과속단속카메라 "STOP" 대항 컨셉 — 원작 자막 지시사항).
/// 개별 문자를 원 위 등간격 위치에 회전 배치해 곡선 텍스트를 근사한다.
class _CircularSlowLabel extends StatelessWidget {
  final double radius;
  const _CircularSlowLabel({required this.radius});

  static const _text = 'SLOW';
  static const _startDeg = 58.0;
  static const _endDeg = 122.0;

  @override
  Widget build(BuildContext context) {
    final letters = _text.split('');
    final n = letters.length;
    return Stack(
      alignment: Alignment.center,
      children: List.generate(n, (i) {
        final deg = n == 1
            ? _startDeg
            : _startDeg + (_endDeg - _startDeg) * i / (n - 1);
        final rad = deg * math.pi / 180;
        final offset = Offset(math.cos(rad), math.sin(rad)) * radius;
        return Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: rad - math.pi / 2,
            child: Text(
              letters[i],
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// 사후구간 과속 경고 — 화면 전체를 덮는 심장박동형 빨강 오버레이.
/// [active]가 true인 동안(사후구간 && 현재속도 > 제한속도)에만 오파시티가
/// 0.15~0.30 사이를 진동한다. 호출자가 `Positioned.fill(child: ...)`로 Stack
/// 최상단에 배치해야 화면 전체를 덮는다(이 위젯 자신은 Positioned를 쓰지
/// 않아 Stack 없이도 단독으로 위젯 테스트 가능).
class SpeedWarningOverlay extends StatefulWidget {
  final bool active;
  const SpeedWarningOverlay({super.key, required this.active});

  @override
  State<SpeedWarningOverlay> createState() => _SpeedWarningOverlayState();
}

class _SpeedWarningOverlayState extends State<SpeedWarningOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _opacityAnim = Tween<double>(begin: 0.15, end: 0.30).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SpeedWarningOverlay old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _opacityAnim,
        builder: (context, child) => Container(
          color: Colors.red.withValues(alpha: _opacityAnim.value),
        ),
      ),
    );
  }
}
