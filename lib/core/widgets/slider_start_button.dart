import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import '../theme/app_theme.dart';

/// "Start your Engine" 슬라이드 버튼
/// 와이어프레임 하단 스와이프 CTA
///
/// 순수 position-based slide-to-confirm 위젯 (iOS 밀어서 잠금해제 느낌).
/// 이전에 사용하던 `slider_button` 패키지는 내부적으로 [Dismissible]을 사용해
/// 드래그 거리뿐 아니라 release velocity까지 완료 판정에 반영했고, 이는
/// "느리지만 끝까지 민 드래그"가 튕겨나가는 등 의도치 않은 UX를 유발했다.
/// 이 위젯은 velocity를 전혀 보지 않고 드래그 종료 시점의 위치만으로
/// 완료 여부를 판정한다.
class SliderStartButton extends StatefulWidget {
  final VoidCallback onSlideComplete;

  const SliderStartButton({super.key, required this.onSlideComplete});

  @override
  State<SliderStartButton> createState() => _SliderStartButtonState();
}

class _SliderStartButtonState extends State<SliderStartButton>
    with SingleTickerProviderStateMixin {
  static const double _trackHeight = 70;
  static const double _thumbSize = 52;
  static const double _edgePadding = 9;
  static const double _completionThreshold = 0.85;

  late final AnimationController _animController;
  Animation<double>? _snapAnimation;

  double _dragX = 0;
  double _maxDrag = 0;
  bool _completed = false;
  bool _animatingToComplete = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this)
      ..addListener(() {
        final anim = _snapAnimation;
        if (anim != null) {
          setState(() => _dragX = anim.value);
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && _animatingToComplete) {
          _animatingToComplete = false;
          _onCompletionAnimationFinished();
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _triggerHaptic() async {
    try {
      await HapticFeedback.heavyImpact();
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(pattern: [0, 80, 60, 120], intensities: [0, 200, 0, 255]);
      }
    } catch (_) {
      // 햅틱 실패는 확인 동작 자체에 영향을 주면 안 됨 — 조용히 무시.
    }
  }

  void _onCompletionAnimationFinished() {
    setState(() => _completed = true);
    widget.onSlideComplete();
    unawaited(_triggerHaptic());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_completed) return;
    if (_animController.isAnimating) {
      _animController.stop();
      _animatingToComplete = false;
    }
    setState(() {
      _dragX = (_dragX + details.delta.dx).clamp(0.0, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_completed) return;
    if (_maxDrag <= 0) return;

    // Pure position-based completion check — release velocity is
    // intentionally never consulted here.
    if (_dragX >= _maxDrag * _completionThreshold) {
      _animatingToComplete = true;
      _animateTo(_maxDrag, const Duration(milliseconds: 150));
    } else {
      _animatingToComplete = false;
      _animateTo(0, const Duration(milliseconds: 200));
    }
  }

  void _animateTo(double target, Duration duration) {
    _animController
      ..duration = duration
      ..reset();
    _snapAnimation = Tween<double>(begin: _dragX, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          _maxDrag = (trackWidth - _thumbSize - 2 * _edgePadding).clamp(0.0, double.infinity);

          return GestureDetector(
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: Container(
              width: trackWidth,
              height: _trackHeight,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                children: [
                  const Align(
                    alignment: Alignment(0.15, 0),
                    child: _StartLabel(),
                  ),
                  Positioned(
                    left: _edgePadding + _dragX,
                    top: _edgePadding,
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.double_arrow_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StartLabel extends StatelessWidget {
  const _StartLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Start your Engine',
      style: AppTextStyles.labelLG.copyWith(
        color: AppColors.secondary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}
