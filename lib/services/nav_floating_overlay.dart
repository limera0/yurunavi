import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ({iconType, distanceText, nextIconType, nextDistanceText}) — nav_screen이
/// _currentGuidance()로 채워 넘긴다. next* 는 2줄 오버레이(현재+다음 안내)용
/// 필드로 nullable — 다음 스텝이 없으면(현재 스텝이 마지막이면) null을 넘겨
/// 네이티브 쪽이 1줄로 접히게 한다.
typedef GuidanceInfo = ({
  String iconType,
  String distanceText,
  String? nextIconType,
  String? nextDistanceText,
});

/// 플로팅 오버레이 Dart 래퍼 (S3b 청크2, 2026-08-06)
///
/// 마스터 결정 2(2026-08-06): 시스템 PIP → 네이버지도/카카오내비 스타일
/// SYSTEM_ALERT_WINDOW 플로팅 아이콘(1탭 → 앱 즉시 복귀)으로 전환.
///
/// API:
/// - [attach] / [detach] — nav_screen initState/dispose에서 호출.
/// - [show] / [update] / [hide] — 라이프사이클 훅(paused/hidden/resumed)에서 호출.
/// - [checkPermissionAndMaybePrompt] — 앱 최초 실행(홈 화면 진입) 시 1회만
///   권한 다이얼로그 표시. main_map_screen initState에서 호출한다.
///
/// Android 전용 — 다른 플랫폼에서는 모든 메서드가 즉시 반환.
class NavFloatingOverlay {
  NavFloatingOverlay._();

  static const MethodChannel _channel =
      MethodChannel('com.westinx.yurunavi/nav_floating');

  // ── 라이프사이클 관리 ──────────────────────────────────────────────────────

  /// initState 마지막에 호출. ref는 현재 Dart 래퍼 레벨에서는 직접 사용하지
  /// 않지만 향후 상태 구독 확장을 위해 서명에 유지한다.
  // ignore: avoid_unused_parameters
  static void attach(WidgetRef ref, BuildContext ctx) {
    // 현재 구현에서 ref/ctx를 저장하지 않음 — 권한 다이얼로그는 nav_screen이
    // addPostFrameCallback에서 checkPermissionAndMaybePrompt(context)로 직접 호출.
  }

  /// dispose 처음에 호출. 오버레이가 남아있으면 숨긴다(좀비 방지).
  static void detach() {
    hide(); // 좀비 방지: 내비 종료 시 오버레이 강제 해제
  }

  // ── 오버레이 표시/갱신/숨김 ────────────────────────────────────────────────

  /// 오버레이를 표시한다. 권한이 없으면 no-op.
  static Future<void> show(GuidanceInfo info) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('show', {
        'iconType': info.iconType,
        'distanceText': info.distanceText,
        'nextIconType': info.nextIconType,
        'nextDistanceText': info.nextDistanceText,
      });
    } on PlatformException catch (e) {
      debugPrint('NavFloatingOverlay.show error: $e');
    } on MissingPluginException catch (e) {
      debugPrint('NavFloatingOverlay.show MissingPlugin: $e');
    }
  }

  /// 표시 중인 오버레이의 내용을 갱신한다.
  static Future<void> update(GuidanceInfo info) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('update', {
        'iconType': info.iconType,
        'distanceText': info.distanceText,
        'nextIconType': info.nextIconType,
        'nextDistanceText': info.nextDistanceText,
      });
    } on PlatformException catch (e) {
      debugPrint('NavFloatingOverlay.update error: $e');
    } on MissingPluginException catch (e) {
      debugPrint('NavFloatingOverlay.update MissingPlugin: $e');
    }
  }

  /// 오버레이를 숨기고 FloatingOverlayService를 종료한다.
  static Future<void> hide() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException catch (e) {
      debugPrint('NavFloatingOverlay.hide error: $e');
    } on MissingPluginException catch (e) {
      debugPrint('NavFloatingOverlay.hide MissingPlugin: $e');
    }
  }

  // ── 권한 조회 및 UX ────────────────────────────────────────────────────────

  /// SYSTEM_ALERT_WINDOW 권한 여부 조회. Android 전용; 다른 플랫폼은 true 반환.
  static Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('canDrawOverlays');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 권한 다이얼로그를 앱 생애주기 통틀어 이미 띄운 적 있는지 기록하는 플래그.
  static const _promptedKey = 'overlay_permission_prompted_v1';

  /// SYSTEM_ALERT_WINDOW 권한이 없으면 안내 다이얼로그를 표시한다.
  ///
  /// Play 정책 준수: 앱이 권한 목적을 사용자에게 명확히 설명해야 한다.
  /// 다이얼로그 문구는 HANDOFF_0806_S3b_floating_and_notif.md §2-C 원문.
  ///
  /// 마스터 결정(2026-08-14): 다이얼로그는 앱 생애주기 통틀어 최대 1회만
  /// 자동 표시한다(첫 앱 실행, main_map_screen에서 호출). 한 번 표시(또는
  /// 표시 시도)됐으면 이후로는 사용자가 어떤 버튼을 눌렀든, 심지어 권한이
  /// 여전히 없어도 다시 자동으로 뜨지 않는다 — 나중에 켜고 싶으면 설정 화면의
  /// "다른 앱 위에 PIP 화면 표시" 토글에서 직접 권한 화면으로 이동한다.
  static Future<void> checkPermissionAndMaybePrompt(BuildContext ctx) async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_promptedKey) ?? false) return; // 이미 1회 표시함 — 재표시 안 함
    final hasPermission = await canDrawOverlays();
    if (hasPermission) {
      await prefs.setBool(_promptedKey, true); // 권한 있으면 다시 확인할 필요 없음
      return;
    }
    // ctx가 이미 unmount됐으면 다이얼로그를 띄울 수 없다 — 이 경우 "표시함"으로
    // 기록하지 않는다(code-auditor 2026-08-14 지적: 여기서 플래그를 세우면
    // 사용자가 다이얼로그를 한 번도 못 본 채 영구히 재시도 기회를 잃는다).
    // 다음 홈 화면 진입에서 다시 시도된다.
    if (!ctx.mounted) return;
    await showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('화면 위에 안내 표시 권한이 필요합니다'),
        content: const Text(
          '라이딩 중 카톡·전화·네이버지도 등을 잠깐 확인할 때, '
          '유루나비 안내 아이콘을 화면 위에 띄워줍니다. '
          '아이콘을 한 번 누르면 앱으로 즉시 돌아옵니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('나중에'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await openOverlaySettings();
            },
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
    // 어느 버튼을 눌렀든(또는 다이얼로그가 어떤 경로로 닫혔든) 다시는 자동으로
    // 띄우지 않는다.
    await prefs.setBool(_promptedKey, true);
  }

  /// 시스템 오버레이 설정 화면을 연다 (ACTION_MANAGE_OVERLAY_PERMISSION).
  /// Android는 SYSTEM_ALERT_WINDOW를 런타임 permission으로 부여하지 않으므로
  /// 반드시 시스템 설정 화면을 통해야 한다. 설정 화면(settings_screen.dart)의
  /// PIP 토글에서도 재사용하기 위해 public으로 노출한다.
  static Future<void> openOverlaySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openOverlaySettings');
    } on PlatformException catch (e) {
      debugPrint('NavFloatingOverlay.openOverlaySettings error: $e');
    } on MissingPluginException catch (e) {
      debugPrint('NavFloatingOverlay.openOverlaySettings MissingPlugin: $e');
    }
  }
}
