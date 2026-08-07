// 상단 회전 안내 카드(카드1) — 순수 데이터만 받아 스스로 렌더링하는 독립
// 컴포넌트(DaylightBar/RearCameraGauge와 동일 패턴, nav_screen.dart 전체를
// 마운트하지 않고도 위젯 테스트로 검증할 수 있다).
//
// §5(HANDOFF_0807_S8): 원래 SizedBox(width: 화면폭 * 0.62)라는 고정폭이었는데,
// 남은거리("10.0km" 이상 4자리+)와 도로명이 길어지면 줄바꿈됐다. 마스터
// 우선 해법대로 ConstrainedBox(minWidth: 기존 62%, maxWidth: 화면 밖으로
// 안 나가는 상한) + IntrinsicWidth로 컨텐츠에 맞춰 늘어나되 기본값보다는
// 작아지지 않게 바꿨다. 안쪽 콘텐츠 Column을 감싸던 Expanded는
// IntrinsicWidth(가변폭 부모) 안에서 동작하지 않아(Flutter 레이아웃 제약 —
// Expanded는 폭이 확정된/bounded 부모가 필요) Flexible + Row/Column
// mainAxisSize.min으로 교체했다.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class NavTopCard extends StatelessWidget {
  const NavTopCard({
    super.key,
    required this.svgAsset,
    required this.minWidth,
    required this.maxWidth,
    this.arrivalBannerVisible = false,
    this.arrivalDurationText,
    this.distMain = '',
    this.distUnit = '',
    this.streetName,
    this.onTap,
  });

  /// 다음 회전 안내 아이콘(비도착 상태에서만 쓰임).
  final String svgAsset;

  /// 카드의 최소 폭(기존 고정폭 — 화면폭 * 0.62). 컨텐츠가 이보다 좁아도
  /// 이 밑으로는 줄어들지 않는다.
  final double minWidth;

  /// 카드가 늘어날 수 있는 상한(화면 밖으로 안 나가게 호출측이 계산해서 넘김).
  final double maxWidth;

  /// true면 "목적지 도착" 배너 콘텐츠로 전환.
  final bool arrivalBannerVisible;

  /// 도착 배너에서만 쓰는 소요시간 문자열(이미 포맷된 값, 예: "소요시간 12분").
  /// null이면 표시하지 않음.
  final String? arrivalDurationText;

  /// 남은거리 숫자부(예: "10.0") — RichText로 단위와 폰트 크기를 분리해 표시.
  final String distMain;

  /// 남은거리 단위부(예: "km"/"m").
  final String distUnit;

  /// 다음 안내 지점 도로명(없으면 표시 안 함).
  final String? streetName;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
        child: IntrinsicWidth(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              top: false,
              child: IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 아이콘박스: 폭 80 (30% 축소) — 도착 중엔 깃발 아이콘
                    SizedBox(
                      width: 80,
                      child: ColoredBox(
                        color: cs.surface,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: arrivalBannerVisible
                              ? Icon(Icons.flag_rounded, size: 44, color: cs.tertiary)
                              : SvgPicture.asset(svgAsset, width: 60, height: 60),
                        ),
                      ),
                    ),
                    // 콘텐츠: 도착 중엔 "목적지 도착" + 소요시간, 평소엔 거리 + 도로명.
                    // Expanded가 아니라 Flexible — IntrinsicWidth 부모 안에서
                    // Expanded는 폭 확정 오류를 낸다(위 파일 헤더 주석 참고).
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: arrivalBannerVisible
                              ? [
                                  Text(
                                    '목적지 도착',
                                    style: TextStyle(
                                      color: cs.onSurface,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                    ),
                                  ),
                                  if (arrivalDurationText != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        arrivalDurationText!,
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ]
                              : [
                                  if (distMain.isNotEmpty || distUnit.isNotEmpty)
                                    RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: distMain,
                                            style: TextStyle(
                                              color: cs.onSurface,
                                              fontSize: 53,
                                              fontWeight: FontWeight.w800,
                                              height: 1.1,
                                            ),
                                          ),
                                          TextSpan(
                                            text: distUnit,
                                            style: TextStyle(
                                              color: cs.onSurface,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w700,
                                              height: 1.1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (streetName != null && streetName!.isNotEmpty)
                                    Text(
                                      streetName!,
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
