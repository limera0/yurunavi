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

          const _SectionHeader(title: '앱 설정'),
          _LanguageSelector(),
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
