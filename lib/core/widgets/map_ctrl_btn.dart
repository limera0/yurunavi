import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 지도 위 원형 흰 배경 + 그림자 컨트롤 버튼.
///
/// 줌 인/아웃, 재중심, 설정 등 지도 화면의 원형 버튼과 경유지 관리 카드의
/// 출발지/도착지 `+` 버튼이 공유하는 공용 스타일.
class MapCtrlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool bold;
  final double size;

  const MapCtrlBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.bold = false,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.13),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: size * (bold ? 0.52 : 0.48),
          color: AppColors.secondary,
          weight: bold ? 700 : 400,
        ),
      ),
    );
  }
}
