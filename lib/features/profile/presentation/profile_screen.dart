import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/bike_profile.dart';
import '../../../models/user_profile.dart';
import '../../../providers/app_providers.dart';
import '../../auth/providers/auth_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _instaCtrl;

  @override
  void initState() {
    super.initState();
    final p = ref.read(userProfileProvider).value ?? UserProfile.empty;
    _nicknameCtrl = TextEditingController(text: p.nickname);
    _instaCtrl = TextEditingController(text: p.instagramHandle);
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _instaCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current = ref.read(userProfileProvider).value ?? UserProfile.empty;
    await ref
        .read(userProfileProvider.notifier)
        .save(
          current.copyWith(
            nickname: _nicknameCtrl.text.trim(),
            instagramHandle: _instaCtrl.text.trim().replaceFirst('@', ''),
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('프로필이 저장되었습니다')));
    }
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final docsDir = await getApplicationDocumentsDirectory();
    final ext = p.extension(picked.path);
    final savedPath = p.join(
      docsDir.path,
      'avatar_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await File(picked.path).copy(savedPath);
    final current = ref.read(userProfileProvider).value ?? UserProfile.empty;
    await ref
        .read(userProfileProvider.notifier)
        .save(current.copyWith(avatarPath: savedPath));
  }

  Future<void> _addBike() async {
    final result = await showModalBottomSheet<BikeProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BikeEditSheet(),
    );
    if (result == null) return;
    final current = ref.read(userProfileProvider).value ?? UserProfile.empty;
    await ref
        .read(userProfileProvider.notifier)
        .save(current.copyWith(bikes: [...current.bikes, result]));
  }

  Future<void> _removeBike(int index) async {
    final current = ref.read(userProfileProvider).value ?? UserProfile.empty;
    final bikes = [...current.bikes]..removeAt(index);
    await ref
        .read(userProfileProvider.notifier)
        .save(current.copyWith(bikes: bikes));
  }

  Future<void> _selectBike(int index) async {
    final current = ref.read(userProfileProvider).value ?? UserProfile.empty;
    await ref
        .read(userProfileProvider.notifier)
        .save(current.copyWith(selectedBikeIndex: index));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value ?? UserProfile.empty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필 설정'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('저장', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── 아바타 ────────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primary,
                    backgroundImage: profile.avatarPath != null
                        ? FileImage(File(profile.avatarPath!))
                        : null,
                    child: profile.avatarPath == null
                        ? const Icon(
                            Icons.person,
                            size: 56,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.edit,
                        size: 18,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ── 계정 (Google 로그인) ──────────────────────────
          const _AccountSection(),
          const SizedBox(height: 28),

          // ── 닉네임/인스타 ─────────────────────────────────
          const _SectionTitle(title: '기본 정보'),
          const SizedBox(height: 12),
          _LabeledField(
            label: '닉네임',
            controller: _nicknameCtrl,
            hint: '라이더 닉네임을 입력하세요',
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: '인스타그램',
            controller: _instaCtrl,
            hint: '@username',
            svgIcon: 'assets/images/instagram_icon.svg',
            prefixText: '@',
          ),
          const SizedBox(height: 28),

          // ── 바이크 목록 ───────────────────────────────────
          Row(
            children: [
              const _SectionTitle(title: '내 바이크'),
              const Spacer(),
              TextButton.icon(
                onPressed: _addBike,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('추가'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (profile.bikes.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  '등록된 바이크가 없습니다',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...profile.bikes.asMap().entries.map((e) {
              final i = e.key;
              final bike = e.value;
              final isSelected = i == profile.selectedBikeIndex;
              return _BikeCard(
                bike: bike,
                isSelected: isSelected,
                onSelect: () => _selectBike(i),
                onDelete: () => _removeBike(i),
              );
            }),
        ],
      ),
    );
  }
}

// ── 바이크 카드 ───────────────────────────────────────────────

class _BikeCard extends StatelessWidget {
  final BikeProfile bike;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _BikeCard({
    required this.bike,
    required this.isSelected,
    required this.onSelect,
    required this.onDelete,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('바이크 삭제'),
        content: const Text('등록한 바이크 정보가 삭제됩니다'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.two_wheeler,
              color: isSelected ? AppColors.primary : Colors.grey,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${bike.brand} ${bike.model}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isSelected
                          ? AppColors.primary
                          : const Color(0xFF222222),
                    ),
                  ),
                  Text(
                    '${bike.displacement}cc · ${bike.year}년',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 20,
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _confirmDelete(context),
              child: Icon(
                Icons.delete_outline,
                color: Colors.red.shade300,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 바이크 추가 카드 (바텀시트) ──────────────────────────────────

class _BikeEditSheet extends StatefulWidget {
  const _BikeEditSheet();

  @override
  State<_BikeEditSheet> createState() => _BikeEditSheetState();
}

class _BikeEditSheetState extends State<_BikeEditSheet> {
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _ccCtrl = TextEditingController();
  int _selectedYear = DateTime.now().year;

  @override
  void dispose() {
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _ccCtrl.dispose();
    super.dispose();
  }

  Future<void> _openYearPicker() async {
    const minYear = 1970;
    const maxYear = 2027;
    final years = List<int>.generate(maxYear - minYear + 1, (i) => minYear + i);
    var picked = _selectedYear;
    final yearScrollCtrl = FixedExtentScrollController(
      initialItem: _selectedYear - minYear,
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(
                height: 200,
                child: CupertinoPicker(
                  itemExtent: 40,
                  scrollController: yearScrollCtrl,
                  onSelectedItemChanged: (i) => picked = years[i],
                  children: years
                      .map((y) => Center(child: Text('$y년')))
                      .toList(),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: const Text('확인'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    yearScrollCtrl.dispose();
    if (mounted) setState(() => _selectedYear = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 핸들 바 ─────────────────────────────────────────
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── 헤더 ───────────────────────────────────────────
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '바이크 추가',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF222222),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── 필드 + 버튼 (스크롤 가능: 작은 화면/키보드 대응) ──
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            _LabeledField(
                              label: '브랜드',
                              controller: _brandCtrl,
                              hint: '혼다, 베스파 ...',
                              icon: Icons.branding_watermark,
                            ),
                            const SizedBox(height: 10),
                            _LabeledField(
                              label: '모델명',
                              controller: _modelCtrl,
                              hint: '슈퍼커브, 프리마베라 ...',
                              icon: Icons.two_wheeler,
                            ),
                            const SizedBox(height: 10),
                            _LabeledField(
                              label: '배기량 (cc)',
                              controller: _ccCtrl,
                              hint: '125',
                              icon: Icons.speed,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 10),
                            _YearField(
                              year: _selectedYear,
                              onTap: _openYearPicker,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── 취소/추가 버튼 ────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF333333),
                                  side: BorderSide(color: Colors.grey.shade300),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: const Text('취소'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () {
                                  final cc =
                                      int.tryParse(_ccCtrl.text.trim()) ?? 0;
                                  if (_brandCtrl.text.trim().isEmpty ||
                                      _modelCtrl.text.trim().isEmpty) {
                                    return;
                                  }
                                  Navigator.pop(
                                    context,
                                    BikeProfile(
                                      id: DateTime.now().millisecondsSinceEpoch
                                          .toString(),
                                      brand: _brandCtrl.text.trim(),
                                      model: _modelCtrl.text.trim(),
                                      displacement: cc,
                                      year: _selectedYear,
                                    ),
                                  );
                                },
                                child: const Text('추가'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 연식 필드 (탭하면 모달 휠피커) ────────────────────────────

class _YearField extends StatelessWidget {
  final int year;
  final VoidCallback onTap;

  const _YearField({required this.year, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('연식', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                Text('$year년', style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 계정 섹션 (Google 로그인) ─────────────────────────────────
// 로컬 닉네임/바이크(userProfileProvider)와는 완전히 독립적인 블록.

class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  bool _signingIn = false;

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('로그인에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('로그아웃에 실패했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: '계정'),
        const SizedBox(height: 12),
        authState.when(
          data: (user) =>
              user == null ? _buildSignedOut() : _buildSignedIn(user),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => _buildSignedOut(),
        ),
      ],
    );
  }

  Widget _buildSignedOut() {
    return OutlinedButton(
      onPressed: _signingIn ? null : _signIn,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        side: BorderSide(color: Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _signingIn
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/images/google_g_logo.svg',
                  width: 20,
                  height: 20,
                ),
                const SizedBox(width: 10),
                const Text('Google로 로그인'),
              ],
            ),
    );
  }

  Widget _buildSignedIn(User user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary,
            backgroundImage: user.photoURL != null
                ? NetworkImage(user.photoURL!)
                : null,
            child: user.photoURL == null
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName ?? '이름 없음',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF222222),
                  ),
                ),
                if (user.email != null)
                  Text(
                    user.email!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
          TextButton(onPressed: _signOut, child: const Text('로그아웃')),
        ],
      ),
    );
  }
}

// ── 공통 위젯 ─────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Color(0xFF333333),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final String? svgIcon;
  final String? prefixText;
  final TextInputType? keyboardType;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.icon,
    this.svgIcon,
    this.prefixText,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefixText,
            prefixIcon: svgIcon != null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SvgPicture.asset(
                      svgIcon!,
                      colorFilter: const ColorFilter.mode(
                        AppColors.primary,
                        BlendMode.srcIn,
                      ),
                    ),
                  )
                : Icon(icon, size: 18, color: AppColors.primary),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
      ],
    );
  }
}
