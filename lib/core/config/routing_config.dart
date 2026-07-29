import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

/// 원격 서버에서 라우팅 costing 파라미터를 로드한다.
/// 서버 실패 시 [_defaultCostingOptions]로 폴백.
class RoutingConfig {
  RoutingConfig._();

  static List<Map<String, dynamic>> _costingOptions = _defaultCostingOptions;

  static List<Map<String, dynamic>> get costingOptions =>
      List.unmodifiable(_costingOptions);

  static Future<void> loadRemote(String naviBaseUrl) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$naviBaseUrl/routing-config'),
            headers: {'X-Api-Key': AppConfig.instance.naviApiKey},
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final profiles =
            (data['profiles'] as List).cast<Map<String, dynamic>>();
        if (profiles.length == 3) {
          _costingOptions = profiles;
        }
      }
    } catch (_) {
      // 실패 시 _defaultCostingOptions 유지
    }
  }

  static const List<Map<String, dynamic>> _defaultCostingOptions = [
    // 시골길: 생활도로·비포장 선호, top_speed 제한 → 간선도로 자연 회피
    // use_ferry:0.0 — 한국 도선/나룻배는 오토바이 탑승 불가 경우 많음
    // 2026-07-26 실측 조정: '1'(trunk) 제거 — use_highways:0.0이 trunk 회피를
    // 충분히 처리하며, class_factor 100 이중 패널티가 580km 우회의 원인이었음.
    // primary 6·secondary 2.5·터널/교량 3.0으로 완화해 305km 실측 달성.
    {
      'use_highways': 0.0,
      'use_ferry': 0.0,
      'use_living_streets': 1.0,
      'use_tracks': 0.15,
      'top_speed': 40,
      'class_factors': {
        '0': 100,   // motorway: 고속도로 회피 (법적 절대 금지)
        '2': 6,     // primary: 일반국도 회피
        '3': 2.5,   // secondary: 지방도 회피
        '4': 0.5,   // tertiary: 시군도 선호
        '5': 1.2,   // unclassified: 소로 약한 회피
        '6': 1.3,   // residential: 마을길 약한 회피
        '7': 1.5,   // service: 농로 약한 회피
      },
      'curvature_penalty': 2.0,
      'long_bridge_factor': 3.0,
      'long_tunnel_factor': 3.0,
      'span_min_length': 300,
      'uturn_penalty': 50,
    },
    // 지방도로: 중간 설정, 주요 국도 의존 낮춤
    // 2026-07-26 실측 조정: '1'(trunk) 제거, 터널/교량 5.0→2.0
    // 서울-호산 323km 달성 (Naver 지방도 309km 대비 +4.5%)
    {
      'use_highways': 0.0,
      'use_ferry': 0.0,
      'use_living_streets': 0.5,
      'use_tracks': 0.2,
      'class_factors': {
        '0': 100,   // motorway: 고속도로 회피
        '2': 2.0,   // primary: 일반국도 약한 회피
        '3': 0.3,   // secondary: 지방도 선호
        '4': 1.1,   // tertiary: 시군도 약한 회피
        '5': 1.8,   // unclassified: 소로 약한 회피
        '6': 2.2,   // residential: 마을길 회피
        '7': 3.0,   // service: 농로 회피
      },
      'curvature_penalty': 0.5,
      'long_bridge_factor': 2.0,
      'long_tunnel_factor': 2.0,
      'span_min_length': 1000,
      'uturn_penalty': 70,
    },
    // 국도: 고속도로만 회피, trunk는 최소 불이익 — 가장 짧은 국도 경로 우선.
    // use_highways:0.0은 수도권에서 trunk급 접근 도로까지 차단해 수원/안산→호산
    // 경로가 393km(서울 동북부 우회)로 폭등하는 문제 발생.
    // 0.2로 완화 시 안산 334km·서울 306km (Valhalla는 OSM access 태그로
    // 자동차전용도로를 별도 차단하므로 법적 금지 도로는 진입 불가).
    {
      'use_highways': 0.2,
      'use_ferry': 0.0,
      'use_tolls': 0.0,
      'class_factors': {
        '0': 100,   // motorway: 고속도로 회피 (법적 절대 금지)
      },
      'curvature_penalty': 0.0,
      'long_bridge_factor': 1.0,
      'long_tunnel_factor': 1.0,
      'uturn_penalty': 120,
    },
  ];
}
