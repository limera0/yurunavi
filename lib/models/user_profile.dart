import 'dart:convert';
import 'bike_profile.dart';

class UserProfile {
  final String nickname;
  final String instagramHandle; // '@' 없이 저장
  final List<BikeProfile> bikes;
  final int selectedBikeIndex;
  final String? avatarPath; // 앱 문서 디렉토리 내 로컬 파일 경로

  const UserProfile({
    required this.nickname,
    required this.instagramHandle,
    required this.bikes,
    this.selectedBikeIndex = 0,
    this.avatarPath,
  });

  static const UserProfile empty = UserProfile(
    nickname: '',
    instagramHandle: '',
    bikes: [],
  );

  BikeProfile? get selectedBike => bikes.isNotEmpty
      ? bikes[selectedBikeIndex.clamp(0, bikes.length - 1)]
      : null;

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'instagramHandle': instagramHandle,
    'bikes': bikes.map((b) => b.toJson()).toList(),
    'selectedBikeIndex': selectedBikeIndex,
    'avatarPath': avatarPath,
  };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    nickname: j['nickname'] as String? ?? '',
    instagramHandle: j['instagramHandle'] as String? ?? '',
    bikes: (j['bikes'] as List<dynamic>? ?? [])
        .map((e) => BikeProfile.fromJson(e as Map<String, dynamic>))
        .toList(),
    selectedBikeIndex: j['selectedBikeIndex'] as int? ?? 0,
    avatarPath: j['avatarPath'] as String?,
  );

  factory UserProfile.fromJsonString(String raw) =>
      UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());

  UserProfile copyWith({
    String? nickname,
    String? instagramHandle,
    List<BikeProfile>? bikes,
    int? selectedBikeIndex,
    String? avatarPath,
  }) => UserProfile(
    nickname: nickname ?? this.nickname,
    instagramHandle: instagramHandle ?? this.instagramHandle,
    bikes: bikes ?? this.bikes,
    selectedBikeIndex: selectedBikeIndex ?? this.selectedBikeIndex,
    avatarPath: avatarPath ?? this.avatarPath,
  );
}
