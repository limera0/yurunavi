import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/map_language.dart';
import '../../../services/ideograph_font_service.dart';
import '../../../services/language_service.dart';

final languageServiceProvider = Provider((_) => LanguageService());
final ideographFontServiceProvider = Provider((_) => IdeographFontService());

// ── 내비 지도 방향 (헤딩업=true 기본, 노스업=false) ─────────────────────────
final navHeadingUpProvider =
    AsyncNotifierProvider<NavHeadingUpNotifier, bool>(NavHeadingUpNotifier.new);

class NavHeadingUpNotifier extends AsyncNotifier<bool> {
  static const _key = 'nav_heading_up_v1';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool headingUp) async {
    state = AsyncData(headingUp);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, headingUp);
  }
}

// ── 지도 야간 디밍 온/오프 (기본값 on = 기존 상시 온 동작과 동일) ───────────
final mapNightDimEnabledProvider =
    AsyncNotifierProvider<MapNightDimEnabledNotifier, bool>(
        MapNightDimEnabledNotifier.new);

class MapNightDimEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'map_night_dim_enabled_v1';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool enabled) async {
    state = AsyncData(enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

// ── 플로팅 오버레이(다른 앱 위에 PIP 화면 표시) 온/오프 (Android 전용, 기본 on) ─
final floatingOverlayEnabledProvider =
    AsyncNotifierProvider<FloatingOverlayEnabledNotifier, bool>(
        FloatingOverlayEnabledNotifier.new);

class FloatingOverlayEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'floating_overlay_enabled_v1';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool enabled) async {
    state = AsyncData(enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

final mapLanguageProvider =
    AsyncNotifierProvider<MapLanguageNotifier, MapLanguage>(
        MapLanguageNotifier.new);

class MapLanguageNotifier extends AsyncNotifier<MapLanguage> {
  @override
  Future<MapLanguage> build() async =>
      ref.read(languageServiceProvider).load();

  Future<void> setLanguage(MapLanguage l) async {
    await ref.read(languageServiceProvider).save(l);
    state = AsyncData(l);
  }
}

// ── 지도 표의문자(한글) 폰트 (O1 청크3, Android 전용) ───────────────────────
// `localIdeographFontFamily`는 MapView 생성 시점에만 적용되고 런타임 override가
// 안 된다 — 저장값은 다음에 지도 화면을 새로 열 때부터 반영된다.
// 기본값 'sans-serif'는 특정 폰트명이 아니라 OS가 알아서 제조사 기본 한글 폰트로
// 치환해주는 별칭이다(One UI 등 버전마다 실제 폰트명이 바뀌는 문제를 피하기 위함).
final mapIdeographFontFamilyProvider =
    AsyncNotifierProvider<MapIdeographFontFamilyNotifier, String>(
        MapIdeographFontFamilyNotifier.new);

class MapIdeographFontFamilyNotifier extends AsyncNotifier<String> {
  static const _key = 'map_ideograph_font_family_v1';
  static const defaultFamily = 'sans-serif';

  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? defaultFamily;
  }

  Future<void> set(String fontFamily) async {
    state = AsyncData(fontFamily);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, fontFamily);
  }
}

/// 한글 지원 시스템 폰트 후보 목록 — 설정 화면을 열 때마다 새로 조회한다(캐싱 없음).
final koreanFontListProvider = FutureProvider<List<String>>(
  (ref) => ref.read(ideographFontServiceProvider).listKoreanFonts(),
);

// ── "이어서 안내하기" 재개 제안 임계치 (시간 단위, 기본 2시간) ─────────────
final resumeThresholdHoursProvider =
    AsyncNotifierProvider<ResumeThresholdHoursNotifier, int>(
        ResumeThresholdHoursNotifier.new);

class ResumeThresholdHoursNotifier extends AsyncNotifier<int> {
  static const _key = 'resume_threshold_hours_v1';
  static const _default = 2;

  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? _default;
  }

  Future<void> set(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, hours);
    state = AsyncData(hours);
  }
}
