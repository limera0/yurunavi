import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/user_profile.dart';

/// 상단 아이콘 클릭 시 나타나는 플로팅 프로필 카드
class FloatingProfileCard extends StatefulWidget {
  final UserProfile profile;
  final VoidCallback onClose;

  const FloatingProfileCard({
    super.key,
    required this.profile,
    required this.onClose,
  });

  @override
  State<FloatingProfileCard> createState() => _FloatingProfileCardState();
}

class _FloatingProfileCardState extends State<FloatingProfileCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  bool _hearted = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _opacity,
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          child: SizedBox(
            width: 230,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 헤더 ─────────────────────────────────
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.primary,
                        child:
                            Icon(Icons.person, size: 26, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.profile.nickname.isEmpty
                                  ? '닉네임 없음'
                                  : widget.profile.nickname,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.profile.instagramHandle.isNotEmpty)
                              Text(
                                '@${widget.profile.instagramHandle}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // 닫기
                      GestureDetector(
                        onTap: widget.onClose,
                        child: Icon(Icons.close,
                            size: 18, color: Colors.grey.shade400),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // ── 바이크 목록 ──────────────────────────
                  if (widget.profile.bikes.isEmpty)
                    const Text(
                      '등록된 바이크 없음',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    )
                  else
                    ...widget.profile.bikes.map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.two_wheeler,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                b.label,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),

                  // ── 하트 버튼 ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _hearted = !_hearted),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            _hearted
                                ? Icons.favorite
                                : Icons.favorite_border,
                            key: ValueKey(_hearted),
                            color: _hearted ? Colors.red : Colors.grey,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _hearted ? '좋아요!' : '좋아요',
                        style: TextStyle(
                          fontSize: 12,
                          color: _hearted ? Colors.red : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
