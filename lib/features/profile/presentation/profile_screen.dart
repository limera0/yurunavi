import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/bike_profile.dart';
import '../../../models/user_profile.dart';
import '../../../providers/app_providers.dart';

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
    await ref.read(userProfileProvider.notifier).save(
          current.copyWith(
            nickname: _nicknameCtrl.text.trim(),
            instagramHandle:
                _instaCtrl.text.trim().replaceFirst('@', ''),
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필이 저장되었습니다')),
      );
    }
  }

  Future<void> _addBike() async {
    final result = await showDialog<BikeProfile>(
      context: context,
      builder: (_) => const _BikeEditDialog(),
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
    final profile =
        ref.watch(userProfileProvider).value ?? UserProfile.empty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필 설정'),
        backgroundColor: const Color(0xFF008080),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _save,
            child:
                const Text('저장', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── 아바타 ────────────────────────────────────────
          Center(
            child: Stack(
              children: [
                const CircleAvatar(
                  radius: 48,
                  backgroundColor: Color(0xFF008080),
                  child: Icon(Icons.person, size: 56, color: Colors.white),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.edit,
                        size: 18, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
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
            icon: Icons.alternate_email,
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
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF008080)),
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
                child: Text('등록된 바이크가 없습니다',
                    style: TextStyle(color: Colors.grey)),
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF008080).withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF008080)
                : Colors.grey.shade200,
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
              color: isSelected ? const Color(0xFF008080) : Colors.grey,
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
                          ? const Color(0xFF008080)
                          : const Color(0xFF222222),
                    ),
                  ),
                  Text(
                    '${bike.displacement}cc · ${bike.year}년',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: Color(0xFF008080), size: 20),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.delete_outline,
                  color: Colors.red.shade300, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 바이크 추가 다이얼로그 ────────────────────────────────────

class _BikeEditDialog extends StatefulWidget {
  const _BikeEditDialog();

  @override
  State<_BikeEditDialog> createState() => _BikeEditDialogState();
}

class _BikeEditDialogState extends State<_BikeEditDialog> {
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _ccCtrl = TextEditingController();
  final _yearCtrl =
      TextEditingController(text: DateTime.now().year.toString());

  @override
  void dispose() {
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _ccCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('바이크 추가'),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LabeledField(
              label: '브랜드',
              controller: _brandCtrl,
              hint: 'Honda, BMW ...',
              icon: Icons.branding_watermark,
            ),
            const SizedBox(height: 10),
            _LabeledField(
              label: '모델명',
              controller: _modelCtrl,
              hint: 'CB650R, R1250GS ...',
              icon: Icons.two_wheeler,
            ),
            const SizedBox(height: 10),
            _LabeledField(
              label: '배기량 (cc)',
              controller: _ccCtrl,
              hint: '650',
              icon: Icons.speed,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            _LabeledField(
              label: '연식',
              controller: _yearCtrl,
              hint: '2024',
              icon: Icons.calendar_today,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF008080),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            final cc = int.tryParse(_ccCtrl.text.trim()) ?? 0;
            final year = int.tryParse(_yearCtrl.text.trim()) ??
                DateTime.now().year;
            if (_brandCtrl.text.trim().isEmpty ||
                _modelCtrl.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(
              context,
              BikeProfile(
                id: DateTime.now()
                    .millisecondsSinceEpoch
                    .toString(),
                brand: _brandCtrl.text.trim(),
                model: _modelCtrl.text.trim(),
                displacement: cc,
                year: year,
              ),
            );
          },
          child: const Text('추가'),
        ),
      ],
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
  final IconData icon;
  final String? prefixText;
  final TextInputType? keyboardType;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.prefixText,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefixText,
            prefixIcon:
                Icon(icon, size: 18, color: const Color(0xFF008080)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
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
              borderSide: const BorderSide(
                  color: Color(0xFF008080), width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
      ],
    );
  }
}
