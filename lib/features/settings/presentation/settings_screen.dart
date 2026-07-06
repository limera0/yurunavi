import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';
import '../../../models/map_language.dart';
import '../../profile/presentation/profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: const Color(0xFF008080),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // ── 프로필 ────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('프로필 편집'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          const Divider(height: 1),

          // ── 지도 표기 언어 ────────────────────────────────────────
          const _SectionHeader(title: '지도 표기 언어'),
          _LanguageSelector(),

          // ── Phase 2 이후 항목 (미구현) ────────────────────────────
          const _SectionHeader(title: '주행 설정'),
          // TODO Phase 2: 도로 선호도
          // TODO Phase 2: 내비뷰 설정
          // TODO Phase 2: 안내 음성 / 안내 언어

          const _SectionHeader(title: '앱 설정'),
          // TODO Phase 2: 다크모드
          // TODO Phase 2: 지도 다운로드

          const _SectionHeader(title: '기타'),
          // TODO Phase 2: 약관 / 오픈소스 라이선스
        ],
      ),
    );
  }
}

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
      data: (lang) => RadioGroup<MapLanguage>(
        groupValue: lang,
        onChanged: (v) => ref.read(mapLanguageProvider.notifier).setLanguage(v!),
        child: Column(
          children: MapLanguage.values.map((option) {
            final label = option == MapLanguage.korean ? '한국어' : 'English';
            return ListTile(
              title: Text(label),
              leading: Radio<MapLanguage>(
                value: option,
                activeColor: const Color(0xFF008080),
              ),
              onTap: () =>
                  ref.read(mapLanguageProvider.notifier).setLanguage(option),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
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
