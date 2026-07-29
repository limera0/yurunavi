import '../skin.dart';
import 'cub_buddy_skin.dart';
import 'retro_motoring_skin.dart';
import 'yurucam_skin.dart';

/// 사용자가 설정 화면에서 고를 수 있는 무료 스킨 3종의 레지스트리.
/// 설정 화면 목록 렌더링과, 영속화된 스킨 id로부터 [AppSkin] 인스턴스를 복원할
/// 때 공용으로 쓰인다. [DefaultSkin]은 [SkinLoader]의 에러 폴백/JSON 기본값
/// 전용이라 사용자가 고를 수 있는 목록에는 포함하지 않는다.
const kAvailableSkins = <AppSkin>[
  YuruCamSkin(),
  RetroMotoringSkin(),
  CubBuddySkin(),
];
