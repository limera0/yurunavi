import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/address_result.dart';
import '../../../services/address_search_service.dart';

/// 경유지 주소 검색 바텀 시트.
///
/// 검색어를 입력하고 결과를 선택하면
/// `({LatLng latLng, String name})` 레코드를 pop한다.
class AddressSearchSheet extends StatefulWidget {
  const AddressSearchSheet({super.key});

  @override
  State<AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<AddressSearchSheet> {
  late final AddressSearchService _service;
  final TextEditingController _controller = TextEditingController();

  List<AddressResult> _results = [];
  bool _isLoading = false;
  bool _hasError = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _service = AddressSearchService();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _searched = true;
    });

    try {
      final results = await _service.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } on AddressSearchException {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _results = [];
        _isLoading = false;
      });
    }
  }

  void _select(AddressResult result) {
    Navigator.of(context).pop<({LatLng latLng, String name})>(
      (latLng: result.location, name: result.address),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 핸들 바 ─────────────────────────────────────────────────────
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
            const SizedBox(height: 12),

            // ── 제목 ────────────────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '경유지 검색',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── 검색 입력 ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: '주소 또는 장소명 입력',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── 로딩 표시기 ─────────────────────────────────────────────────
            if (_isLoading)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),

            // ── 결과 영역 ───────────────────────────────────────────────────
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: _buildBody(),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SizedBox.shrink();
    }
    if (_hasError) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('검색 중 오류가 발생했습니다')),
      );
    }
    if (_searched && _results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('검색 결과가 없습니다')),
      );
    }
    if (_results.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final result = _results[i];
        return ListTile(
          title: Text(
            result.address,
            style: const TextStyle(fontSize: 14),
          ),
          onTap: () => _select(result),
        );
      },
    );
  }
}
