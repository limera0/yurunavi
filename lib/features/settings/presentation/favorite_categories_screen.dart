import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/saved_place.dart';
import '../../map/providers/map_providers.dart';

/// 즐겨찾기 등록 시트에서 고를 카테고리 이름 목록을 관리하는 화면.
/// [_BikeCard]/[_BikeEditDialog](profile_screen.dart)와 동일한 리스트+다이얼로그
/// 패턴을 그대로 따른다 — 새 위젯 스타일을 만들지 않는다. 단, "추가" 흐름만
/// 인라인 입력으로 전환됨(라운드14) — "이름 변경"은 여전히 다이얼로그 방식.
class FavoriteCategoriesScreen extends ConsumerStatefulWidget {
  const FavoriteCategoriesScreen({super.key});

  @override
  ConsumerState<FavoriteCategoriesScreen> createState() =>
      _FavoriteCategoriesScreenState();
}

class _FavoriteCategoriesScreenState
    extends ConsumerState<FavoriteCategoriesScreen> {
  bool _isAdding = false;
  final TextEditingController _addCtrl = TextEditingController();
  final FocusNode _addFocusNode = FocusNode();

  @override
  void dispose() {
    _addCtrl.dispose();
    _addFocusNode.dispose();
    super.dispose();
  }

  Future<void> _renameCategory(
    BuildContext context,
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

  void _startAdding() {
    setState(() => _isAdding = true);
  }

  void _submitAdd(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      ref.read(favoriteCategoriesProvider.notifier).add(trimmed);
    }
    setState(() {
      _isAdding = false;
      _addCtrl.clear();
    });
  }

  void _cancelAdd() {
    setState(() {
      _isAdding = false;
      _addCtrl.clear();
    });
  }

  /// 카테고리 삭제 확인 다이얼로그 — `tour_summary_list_screen.dart`의
  /// `_confirmDelete` 패턴을 복제하고, 소속 즐겨찾기가 미분류로 이동한다는
  /// 안내 문구를 추가했다. 확인 시 재배정 → 카테고리 삭제 순으로 처리한다.
  Future<void> _confirmRemoveCategory(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('카테고리 삭제'),
        content: const Text(
          '이 카테고리를 삭제할까요?\n'
          "이 카테고리로 등록된 즐겨찾기는 모두 '미분류'로 이동합니다.",
        ),
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
    if (confirmed != true) return;
    await ref
        .read(favoritePlacesProvider.notifier)
        .reassignCategory(name, kUncategorizedFavoriteCategory);
    await ref.read(favoriteCategoriesProvider.notifier).remove(name);
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(favoriteCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('즐겨찾기 카테고리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _startAdding,
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
              // 순서 변경 핸들도 없이 항상 최상단 고정.
              ListTile(
                leading: const Icon(Icons.label_outline,
                    color: Colors.grey),
                title: const Text(kUncategorizedFavoriteCategory),
                subtitle: const Text('카테고리를 지정하지 않은 즐겨찾기의 기본값',
                    style: TextStyle(fontSize: 11)),
              ),
              const Divider(),
              if (categories.isEmpty && !_isAdding)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('등록된 카테고리가 없습니다',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                )
              else if (categories.isNotEmpty)
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorderItem: (oldIndex, newIndex) => ref
                      .read(favoriteCategoriesProvider.notifier)
                      .reorder(oldIndex, newIndex),
                  children: [
                    for (int index = 0; index < categories.length; index++)
                      ListTile(
                        key: ValueKey(categories[index]),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle,
                                  color: Colors.grey),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.label_rounded,
                                color: AppColors.primary),
                          ],
                        ),
                        title: Text(categories[index]),
                        onTap: () => _renameCategory(
                            context, index, categories[index]),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: Colors.red.shade300, size: 20),
                          onPressed: () => _confirmRemoveCategory(
                              context, categories[index]),
                        ),
                      ),
                  ],
                ),
              if (_isAdding)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addCtrl,
                          focusNode: _addFocusNode,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: '예: 집, 회사, 맛집',
                          ),
                          onSubmitted: _submitAdd,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: AppColors.primary),
                        onPressed: () => _submitAdd(_addCtrl.text),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: _cancelAdd,
                      ),
                    ],
                  ),
                ),
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
            backgroundColor: AppColors.primary,
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
