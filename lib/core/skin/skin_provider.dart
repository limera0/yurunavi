import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'skin.dart';
import 'skins/default_skin.dart';

final skinProvider = NotifierProvider<SkinNotifier, AppSkin>(SkinNotifier.new);

class SkinNotifier extends Notifier<AppSkin> {
  @override
  AppSkin build() => const DefaultSkin();

  void apply(AppSkin skin) => state = skin;
}

extension SkinContext on BuildContext {
  AppSkin get skin =>
      ProviderScope.containerOf(this, listen: false).read(skinProvider);
}
