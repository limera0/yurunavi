import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';
import '../../../models/map_language.dart';
import '../../../core/skin/skin.dart';
import '../../../core/skin/skin_provider.dart';
import '../../../core/skin/skins/registry.dart';
import '../../profile/presentation/profile_screen.dart';
import 'favorite_categories_screen.dart';
import 'terms_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          // ── 프로필 ────────────────────────────────────────────────
          const _SectionHeader(title: '프로필'),
          ListTile(
            visualDensity: VisualDensity.compact,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.person_outline),
            title: const Text('프로필 편집'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          const Divider(height: 1),

          // ── 스킨 ─────────────────────────────────────────────────
          const _SectionHeader(title: '스킨'),
          _SkinSelector(),

          // ── 주행 설정 (야간 디밍만 남음, 지도 방향은 앱 설정으로 이동) ────
          const _SectionHeader(title: '주행 설정'),
          Consumer(builder: (ctx, ref, _) {
            final nightDimEnabled =
                ref.watch(mapNightDimEnabledProvider).value ?? true;
            return SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('야간 지도 어둡게'),
              subtitle: const Text('일몰 후 지도 화면을 어둡게 표시'),
              value: nightDimEnabled,
              onChanged: (v) =>
                  ref.read(mapNightDimEnabledProvider.notifier).set(v),
            );
          }),
          const Divider(height: 1),
          // TODO Phase 2: 안내 음성 / 안내 언어

          const _SectionHeader(title: '이어서 안내하기'),
          _ResumeThresholdSelector(),
          const Divider(height: 1),

          const _SectionHeader(title: '앱 설정'),
          _LanguageSelector(),
          if (Platform.isAndroid) _IdeographFontSelector(),
          Consumer(builder: (ctx, ref, _) {
            final headingUp = ref.watch(navHeadingUpProvider).value ?? true;
            return ListTile(
              leading: const Icon(Icons.navigation_outlined),
              title: const Text('지도 방향'),
              trailing: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('헤딩업')),
                  ButtonSegment(value: false, label: Text('노스업')),
                ],
                selected: {headingUp},
                onSelectionChanged: (s) =>
                    ref.read(navHeadingUpProvider.notifier).set(s.first),
              ),
            );
          }),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('즐겨찾기 카테고리'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FavoriteCategoriesScreen()),
            ),
          ),
          const Divider(height: 1),
          // TODO Phase 2: 다크모드
          // TODO Phase 2: 지도 다운로드

          const _SectionHeader(title: '기타'),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('이용약관'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('오픈소스 라이선스'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: '유루나비',
            ),
          ),
        ],
      ),
    );
  }
}

String _mapLanguageLabel(MapLanguage option) =>
    option == MapLanguage.korean ? '한국어' : 'English';

class _LanguageSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langAsync = ref.watch(mapLanguageProvider);
    return langAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (err, _) => const SizedBox.shrink(),
      data: (lang) => ListTile(
        visualDensity: VisualDensity.compact,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: const Text('지도 표기 언어'),
        trailing: DropdownButton<MapLanguage>(
          value: lang,
          underline: const SizedBox.shrink(),
          items: MapLanguage.values
              .map((option) => DropdownMenuItem(
                    value: option,
                    child: Text(_mapLanguageLabel(option)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              ref.read(mapLanguageProvider.notifier).setLanguage(v);
            }
          },
        ),
      ),
    );
  }
}

const _resumeThresholdOptions = [1, 2, 3, 6, 12, 24];

String _resumeThresholdLabel(int hours) => '$hours시간';

/// 강제종료/OOM으로 중단된 투어를 "이어서 안내"로 제안할지 판단하는 시간
/// 범위(오탐 방지 임계치). 마지막 위치 기록이 이 시간 이내면 재개를
/// 제안하고, 넘으면 일반 히스토리로 확정 저장한다(HANDOFF_0810_S15 §2).
class _ResumeThresholdSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thresholdAsync = ref.watch(resumeThresholdHoursProvider);
    return thresholdAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (err, _) => const SizedBox.shrink(),
      data: (hours) => ListTile(
        visualDensity: VisualDensity.compact,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: const Text('재개 제안 시간 범위'),
        subtitle: const Text('중단된 투어를 이어서 안내할지 제안하는 시간 범위입니다.'),
        trailing: DropdownButton<int>(
          value: hours,
          underline: const SizedBox.shrink(),
          items: _resumeThresholdOptions
              .map((option) => DropdownMenuItem(
                    value: option,
                    child: Text(_resumeThresholdLabel(option)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              ref.read(resumeThresholdHoursProvider.notifier).set(v);
            }
          },
        ),
      ),
    );
  }
}

String _ideographFontLabel(String fontFamily) => fontFamily ==
        MapIdeographFontFamilyNotifier.defaultFamily
    ? '시스템 기본'
    : fontFamily;

/// 지도 한글 폰트 선택 (O1 청크3, Android 전용 — iOS는 런타임 override가 안 돼
/// 이 항목 자체를 노출하지 않는다, 호출부에서 `Platform.isAndroid` 게이팅).
///
/// `localIdeographFontFamily`는 MapView 생성 시점에만 적용되므로, 여기서 값을
/// 바꿔도 이미 열려 있는 지도 화면에는 반영되지 않는다 — 다음에 지도를 새로
/// 열 때부터 적용된다는 점을 서브타이틀에 명시한다.
class _IdeographFontSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAsync = ref.watch(mapIdeographFontFamilyProvider);
    final fontsAsync = ref.watch(koreanFontListProvider);

    if (selectedAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (selectedAsync.hasError) return const SizedBox.shrink();

    final selected =
        selectedAsync.value ?? MapIdeographFontFamilyNotifier.defaultFamily;
    // 열거 실패/로딩 중이면 빈 목록으로 폴백 — "시스템 기본"만 있는 상태로 처리한다.
    final fonts = fontsAsync.value ?? const <String>[];
    final options = <String>{
      MapIdeographFontFamilyNotifier.defaultFamily,
      ...fonts,
    }.toList();
    // 저장된 값이 현재 열거 결과에 없어도(예: 로딩 중이거나 폰트가 사라짐) 드롭다운
    // value가 items에 없는 상태가 되지 않도록 항상 포함시킨다.
    if (!options.contains(selected)) options.add(selected);

    return ListTile(
      visualDensity: VisualDensity.compact,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: const Text('지도 한글 폰트'),
      subtitle: const Text(
        '한글을 지원하는 폰트만 표시됩니다. 변경 사항은 지도 화면을 다시 열 때 적용됩니다.',
      ),
      trailing: DropdownButton<String>(
        value: selected,
        underline: const SizedBox.shrink(),
        items: options
            .map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(_ideographFontLabel(f)),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) {
            ref.read(mapIdeographFontFamilyProvider.notifier).set(v);
          }
        },
      ),
    );
  }
}

class _SkinSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(skinProvider);
    return Column(
      children: kAvailableSkins.map((AppSkin skin) {
        final selected = skin.id == current.id;
        return ListTile(
          visualDensity: VisualDensity.compact,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: CircleAvatar(
            radius: 12,
            backgroundColor: skin.colors.brand,
          ),
          title: Text(skin.displayName),
          trailing: selected
              ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
              : null,
          onTap: () => ref.read(skinProvider.notifier).apply(skin),
        );
      }).toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
