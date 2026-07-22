abstract class AppConfig {
  static AppConfig get instance => _instance;
  static late AppConfig _instance;
  static void init(AppConfig cfg) => _instance = cfg;

  String get valhallaBaseUrl;
  String get tileBaseUrl;
  String get naviBaseUrl;
}

class ProdConfig implements AppConfig {
  const ProdConfig();
  @override
  String get valhallaBaseUrl => 'https://valhalla.westinx.com';
  @override
  String get tileBaseUrl => 'https://tiles.westinx.com';
  @override
  String get naviBaseUrl => 'https://navi.westinx.com';
}
