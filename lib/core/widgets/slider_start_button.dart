import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slider_button/slider_button.dart';
import 'package:vibration/vibration.dart';

import '../theme/app_theme.dart';

/// "Start your Engine" 슬라이드 버튼
/// 와이어프레임 하단 스와이프 CTA
class SliderStartButton extends StatelessWidget {
  final VoidCallback onSlideComplete;

  const SliderStartButton({super.key, required this.onSlideComplete});

  Future<void> _triggerHaptic() async {
    await HapticFeedback.heavyImpact();
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 80, 60, 120], intensities: [0, 200, 0, 255]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SliderButton(
            action: () async {
              await _triggerHaptic();
              onSlideComplete();
              return true;
            },
            label: Text(
              'Start your Engine',
              style: AppTextStyles.labelLG.copyWith(
                color: AppColors.secondary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            icon: Container(
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.double_arrow_rounded, color: Colors.white, size: 26),
            ),
            width: constraints.maxWidth,
            buttonWidth: 52,
            radius: 14,
            buttonColor: AppColors.primary,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            highlightedColor: AppColors.primary.withValues(alpha: 0.25),
            baseColor: AppColors.primary,
            buttonSize: 52,
            shimmer: true,
          );
        },
      ),
    );
  }
}
