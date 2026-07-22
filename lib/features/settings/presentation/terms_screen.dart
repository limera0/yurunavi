import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 정적 이용약관 화면. `docs/terms_of_service.md`의 내용을 그대로 옮긴
/// 일회성 화면으로, 마크다운 렌더링 패키지 없이 Dart 문자열로 하드코딩한다.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const List<_Article> _articles = [
    _Article(
      title: '제1조 (목적)',
      body: '본 약관은 유루나비(이하 "회사")가 제공하는 오토바이 투어링 내비게이션 애플리케이션 '
          '"유루나비"(이하 "서비스")의 이용과 관련하여 회사와 이용자의 권리, 의무 및 '
          '책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.',
    ),
    _Article(
      title: '제2조 (용어의 정의)',
      body: '1. "서비스"란 회사가 제공하는 경로 탐색, 재미있는 도로(구불구불한 국도 등) 추천, '
          '실시간 내비게이션 안내 등 일체의 기능을 의미합니다.\n'
          '2. "이용자"란 본 약관에 따라 서비스를 이용하는 자를 의미합니다.\n'
          '3. "콘텐츠"란 서비스 내에서 제공되는 지도 데이터, 경로 정보, 음성 안내 등 일체의 '
          '정보를 의미합니다.',
    ),
    _Article(
      title: '제3조 (약관의 효력 및 변경)',
      body: '1. 본 약관은 서비스 화면에 게시하거나 기타의 방법으로 이용자에게 공지함으로써 효력이 '
          '발생합니다.\n'
          '2. 회사는 관련 법령을 위배하지 않는 범위에서 본 약관을 변경할 수 있으며, 변경 시 '
          '적용일자 및 변경사유를 명시하여 적용일자 7일 전부터 서비스 내 공지 또는 본 문서를 '
          '통해 공지합니다.\n'
          '3. 이용자가 변경된 약관에 동의하지 않는 경우 서비스 이용을 중단하고 앱을 삭제할 수 '
          '있으며, 변경된 약관 공지 후에도 서비스를 계속 이용하는 경우 약관의 변경사항에 '
          '동의한 것으로 봅니다.',
    ),
    _Article(
      title: '제4조 (서비스의 내용)',
      body: '1. 회사는 다음과 같은 서비스를 제공합니다.\n'
          '   • OpenStreetMap(OSM) 등 지도 데이터를 기반으로 한 경로 탐색 및 내비게이션 안내\n'
          '   • 오토바이 투어링에 적합한 도로(굴곡·경치 등 기준)를 우선 고려한 경로 추천\n'
          '   • 주변 관심지점(주유소, 편의점, 식당 등) 검색 및 표시\n'
          '2. 서비스는 현재 별도의 회원가입 절차 없이 제공됩니다. 회원제 기능이 추가될 경우 본 '
          '약관을 통해 별도로 안내합니다.\n'
          '3. 서비스는 무료로 제공되며, 유료 기능이 추가될 경우 사전에 고지합니다.',
    ),
    _Article(
      title: '제5조 (서비스 이용 및 안전운전 책임 — 중요)',
      body: '1. 서비스가 제공하는 경로 및 도로 정보는 참고용이며, 실제 도로 상황(공사, 통제, '
          '노면 상태, 기상 등)과 다를 수 있습니다. 이용자는 서비스의 안내를 맹신하지 않고 '
          '실제 도로 표지판, 신호, 교통법규를 우선하여 준수해야 합니다.\n'
          '2. 이용자는 도로교통법 등 관련 법령이 정하는 제한속도, 신호, 안전장비 착용 의무를 '
          '반드시 준수해야 하며, 서비스의 "재미있는 도로 추천" 기능은 특정 주행 방식(과속, '
          '난폭운전 등)을 권장하거나 유도하는 것이 아닙니다.\n'
          '3. 서비스 이용 중 발생하는 모든 운행상의 판단과 책임은 이용자 본인에게 있으며, '
          '이용자는 자신의 운전 능력과 컨디션, 오토바이의 상태를 스스로 점검할 책임이 '
          '있습니다.\n'
          '4. 이용자는 서비스 이용 중(특히 주행 중) 화면 조작으로 인해 전방 주시가 소홀해지지 '
          '않도록 주의해야 하며, 가능한 경우 음성 안내를 우선 활용해야 합니다.',
    ),
    _Article(
      title: '제6조 (이용자의 의무)',
      body: '1. 이용자는 관련 법령, 본 약관의 규정, 이용안내 및 서비스와 관련하여 공지한 '
          '주의사항을 준수해야 합니다.\n'
          '2. 이용자는 다음 행위를 하여서는 안 됩니다.\n'
          '   • 서비스를 이용하여 얻은 정보를 회사의 사전 승낙 없이 복제, 유통, 상업적으로 '
          '이용하는 행위\n'
          '   • 서비스의 안정적 운영을 방해할 수 있는 일체의 행위(비정상적인 방법으로 서버에 '
          '과도한 부하를 주는 행위 등)\n'
          '   • 타인의 개인정보를 도용하거나 허위 정보를 등록하는 행위',
    ),
    _Article(
      title: '제7조 (회사의 의무 및 면책)',
      body: '1. 회사는 관련 법령과 본 약관이 금지하거나 미풍양속에 반하는 행위를 하지 않으며, '
          '지속적이고 안정적인 서비스 제공을 위해 노력합니다.\n'
          '2. 회사는 GPS 신호 오차, 통신 장애, 지도 데이터(OpenStreetMap 등 오픈소스 데이터 '
          '포함)의 부정확성·최신성 미반영 등으로 인해 발생하는 경로 안내 오류에 대해 고의 또는 '
          '중대한 과실이 없는 한 책임을 지지 않습니다.\n'
          '3. 회사는 천재지변, 서버 장애, 기간통신사업자의 서비스 중지 등 회사가 통제할 수 없는 '
          '사유로 인한 서비스 중단에 대해 책임을 지지 않습니다.\n'
          '4. 회사는 이용자가 서비스를 이용하며 기대하는 수익을 상실한 것에 대해 책임을 지지 '
          '않으며, 그 밖의 서비스를 통해 얻은 자료로 인한 손해에 관하여 책임을 지지 않습니다. '
          '다만 회사의 고의 또는 중대한 과실로 인한 손해에 대해서는 관련 법령이 정하는 바에 '
          '따라 책임을 집니다.',
    ),
    _Article(
      title: '제8조 (지도 데이터 및 저작권)',
      body: '1. 서비스에서 제공하는 지도 데이터는 OpenStreetMap'
          '(https://www.openstreetmap.org/copyright) 및 그 기여자(contributors)의 '
          '저작물로서 Open Data Commons Open Database License(ODbL)'
          '(https://opendatacommons.org/licenses/odbl/)에 따라 이용됩니다.\n'
          '2. 서비스 자체의 소프트웨어, 디자인, 로고 등 회사가 직접 제작한 콘텐츠에 대한 '
          '저작권은 회사에 귀속됩니다.\n'
          '3. 서비스가 이용하는 오픈소스 소프트웨어 목록 및 라이선스 고지는 앱 내 설정 > '
          '오픈소스 라이선스 화면에서 확인할 수 있습니다.',
    ),
    _Article(
      title: '제9조 (서비스의 변경 및 중단)',
      body: '회사는 운영상, 기술상의 필요에 따라 제공하는 서비스의 전부 또는 일부를 변경하거나 '
          '중단할 수 있으며, 이 경우 사전에 서비스 내 공지 등 합리적인 방법으로 이용자에게 '
          '알립니다. 다만 긴급한 보안상의 문제 등 불가피한 경우 사후에 통지할 수 있습니다.',
    ),
    _Article(
      title: '제10조 (개인정보보호)',
      body: '회사는 이용자의 개인정보를 보호하기 위해 별도의 개인정보처리방침을 수립하여 '
          '운영하며, 자세한 내용은 앱 내 개인정보처리방침을 참고하시기 바랍니다.',
    ),
    _Article(
      title: '제11조 (분쟁해결 및 준거법)',
      body: '1. 회사와 이용자 간에 발생한 분쟁에 대해서는 대한민국 법을 준거법으로 합니다.\n'
          '2. 서비스 이용과 관련하여 회사와 이용자 사이에 소송이 제기될 경우 민사소송법상의 '
          '관할 법원에 제기합니다.',
    ),
    _Article(
      title: '제12조 (문의처)',
      body: '서비스 이용과 관련한 문의사항은 아래로 연락해 주시기 바랍니다.\n'
          '   • 담당자: 유루나비 개발자\n'
          '   • 이메일: ceo@westinx.com',
    ),
  ];

  static const String _disclaimer =
      '본 문서는 초안이며, 배포 전 법률 전문가의 최종 검토가 필요합니다. 특히 제5조(안전운전 '
      '책임)와 제7조(면책)는 오토바이 내비게이션 서비스라는 특성상 실제 분쟁 발생 시 회사의 '
      '책임 범위를 좌우하는 핵심 조항이므로, 정식 서비스 오픈 전 반드시 변호사 검토를 받을 '
      '것을 권장합니다.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('이용약관'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '유루나비(YuruNavi) 이용약관',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              '시행일자: 2026-07-13 (최초 제정)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            for (final article in _articles) ...[
              _ArticleBlock(article: article),
              const SizedBox(height: 16),
            ],
            Text(
              _disclaimer,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Article {
  const _Article({required this.title, required this.body});
  final String title;
  final String body;
}

class _ArticleBlock extends StatelessWidget {
  const _ArticleBlock({required this.article});
  final _Article article;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          article.title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          article.body,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
      ],
    );
  }
}
