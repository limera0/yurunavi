abstract class AppConfig {
  static AppConfig get instance => _instance;
  static late AppConfig _instance;
  static void init(AppConfig cfg) => _instance = cfg;

  String get valhallaBaseUrl;
  String get tileBaseUrl;
  String get naviBaseUrl;

  /// navi(Rust) 백엔드 인증 헤더(`X-Api-Key`)에 실어 보낼 공유 비밀키.
  /// 빌드 시 `--dart-define-from-file=env.json`(`NAVI_API_KEY`)으로만 주입되며,
  /// 주입되지 않은 빌드(예: 로컬 debug 빌드)에서는 빈 문자열로 해석된다.
  String get naviApiKey;
}

class ProdConfig implements AppConfig {
  const ProdConfig();
  @override
  String get valhallaBaseUrl => 'https://valhalla.westinx.com';
  @override
  String get tileBaseUrl => 'https://tiles.westinx.com';
  @override
  String get naviBaseUrl => 'https://navi.westinx.com';
  @override
  String get naviApiKey => const String.fromEnvironment('NAVI_API_KEY', defaultValue: '');
}
