import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'skin.dart';
import 'skins/registry.dart';
import 'skins/yurucam_skin.dart';

final skinProvider = NotifierProvider<SkinNotifier, AppSkin>(SkinNotifier.new);

class SkinNotifier extends Notifier<AppSkin> {
  static const _prefsKey = 'selected_skin_id_v1';

  @override
  AppSkin build() {
    // build()는 동기적으로 값을 반환해야 하므로(Notifier, AsyncNotifier 아님)
    // 우선 새 기본 스킨(A)을 반환하고, 저장된 선택이 있으면 비동기로 복원한다.
    unawaited(_restore());
    return const YuruCamSkin();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);
    if (savedId == null) return;
    for (final skin in kAvailableSkins) {
      if (skin.id == savedId) {
        state = skin;
        return;
      }
    }
  }

  void apply(AppSkin skin) {
    state = skin;
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(_prefsKey, skin.id)),
    );
  }
}

extension SkinContext on BuildContext {
  AppSkin get skin =>
      ProviderScope.containerOf(this, listen: false).read(skinProvider);
}
