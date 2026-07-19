import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/saved_place.dart';
import '../../map/providers/map_providers.dart';

/// 즐겨찾기 등록 시트에서 고를 카테고리 이름 목록을 관리하는 화면.
/// [_BikeCard]/[_BikeEditDialog](profile_screen.dart)와 동일한 리스트+다이얼로그
/// 패턴을 그대로 따른다 — 새 위젯 스타일을 만들지 않는다.
class FavoriteCategoriesScreen extends ConsumerWidget {
  const FavoriteCategoriesScreen({super.key});

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CategoryEditDialog(title: '카테고리 추가'),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(favoriteCategoriesProvider.notifier).add(name);
  }

  Future<void> _renameCategory(
    BuildContext context,
    WidgetRef ref,
    int index,
    String current,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryEditDialog(
        title: '카테고리 이름 변경',
        initialValue: current,
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(favoriteCategoriesProvider.notifier).rename(index, name);
  }

  Future<void> _removeCategory(WidgetRef ref, String name) async {
    await ref.read(favoriteCategoriesProvider.notifier).remove(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(favoriteCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('즐겨찾기 카테고리'),
        backgroundColor: const Color(0xFF008080),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addCategory(context, ref),
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Text('불러오기 실패', style: TextStyle(color: Colors.red)),
        ),
        data: (categories) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 항상 선택 가능한 기본값 — 여기서 편집/삭제할 수 없음을 명시.
              ListTile(
                leading: const Icon(Icons.label_outline,
                    color: Colors.grey),
                title: const Text(kUncategorizedFavoriteCategory),
                subtitle: const Text('카테고리를 지정하지 않은 즐겨찾기의 기본값',
                    style: TextStyle(fontSize: 11)),
              ),
              const Divider(),
              if (categories.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('등록된 카테고리가 없습니다',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                )
              else
                ...categories.asMap().entries.map((e) {
                  final index = e.key;
                  final name = e.value;
                  return ListTile(
                    leading: const Icon(Icons.label_rounded,
                        color: Color(0xFF008080)),
                    title: Text(name),
                    onTap: () => _renameCategory(context, ref, index, name),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Colors.red.shade300, size: 20),
                      onPressed: () => _removeCategory(ref, name),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryEditDialog extends StatefulWidget {
  final String title;
  final String initialValue;

  const _CategoryEditDialog({required this.title, this.initialValue = ''});

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '예: 집, 회사, 맛집',
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('확인'),
        ),
      ],
    );
  }
}
