# RECON — TTS 볼륨/가청성 (고가도로·터널 소음 대비 안 들림)

읽기전용 조사. 코드 변경 없음.

## 1. TTS 발화 구현체
- 패키지: `flutter_tts: ^4.2.0` (pubspec.yaml:33), 실제 설치본 4.2.5 (`~/.pub-cache/hosted/pub.dev/flutter_tts-4.2.5`)
- 초기화: `lib/features/navigation/presentation/nav_screen.dart:332-341` `_initTts()`
  - `FlutterTts()` 생성 → `setLanguage('ko-KR')` → `setSpeechRate(0.5)` → `setVolume(1.0)` → `VoicePackService.load(...)`
- 실제 발화 호출: `lib/services/voice_pack_service.dart:36` `await _tts.speak(text);` — **`focus` 인자 없이 호출** (기본값 `false`, 아래 4번 참조)
- 호출 지점(트리거): `nav_screen.dart:225` (도착), `nav_screen.dart:246` (스텝 접근), `nav_screen.dart:318` (재탐색), `nav_screen.dart:349` (출발)

## 2. 볼륨 설정 여지
- `nav_screen.dart:336` `_tts!.setVolume(1.0)` — 이미 명시적으로 최대값(1.0) 설정 중. **볼륨 자체는 이미 상한.**
- flutter_tts API (`flutter_tts.dart:393-396`): `setVolume(double volume)` → Android 네이티브 `TextToSpeech.Engine.KEY_PARAM_VOLUME` 번들 파라미터로 전달 (`FlutterTtsPlugin.kt:533-539`, `0.0~1.0` 범위 검증). 이 파라미터는 TTS 엔진이 자체 스트림에 상대적으로 적용하는 값이라, **스트림 자체 볼륨(미디어/알람 등)을 넘어서지 못함** — 즉 setVolume(1.0)은 "그 스트림 안에서 최대"일 뿐, 스트림이 낮은 우선순위/낮은 실제 게인이면 여전히 작게 들림.

## 3. 오디오 스트림/채널 (usage)
- 현재 코드에서 `setAudioAttributesForNavigation()` **호출 안 함** (grep 결과 nav_screen.dart/voice_pack_service.dart 어디에도 없음).
- 즉 Android TTS 엔진 기본 스트림(대개 `STREAM_MUSIC` 계열, 미디어 볼륨 슬라이더에 종속)으로 발화 중 — 사용자가 "볼륨 최대"라고 해도 그게 미디어 볼륨 슬라이더 최대치일 뿐, 내비게이션 전용 게인은 아님.
- flutter_tts는 이 문제를 위한 API를 **이미 제공**: `flutter_tts.dart:665-666` `setAudioAttributesForNavigation()` → 네이티브 구현 `FlutterTtsPlugin.kt:784-793`
  ```kotlin
  AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
      .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
      .build()
  tts!!.setAudioAttributes(audioAttributes)
  ```
  `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE`는 Android가 내비 안내음성에 쓰라고 만든 usage로, 스트림 라우팅/볼륨 정책이 일반 미디어와 분리되고(내비 볼륨 채널), 보통 카오디오/블루투스에서 더 높은 우선순위·게인으로 처리됨. **현재 미사용 = 개선 여지 확인.**

## 4. 오디오 포커스 / 덕킹(ducking)
- flutter_tts Dart API: `speak(String text, {bool focus = false})` (`flutter_tts.dart:354`) — Android에서만 `focus` 파라미터를 네이티브로 전달, 기본값 `false`.
- 네이티브 쪽: `focus=true`일 때만 `requestAudioFocus()` 호출(`FlutterTtsPlugin.kt:664-670`), 발화 종료 시 `releaseAudioFocus()`.
  - `requestAudioFocus()` (`FlutterTtsPlugin.kt:795-806`): `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` 요청 — 즉 획득해도 배경음을 "완전히 끄기"가 아니라 **덕킹(줄이기)**만 요구. 배경음 재생 앱이 덕킹을 지원하면 배경음량이 낮아지고 TTS가 상대적으로 잘 들림.
  - `voice_pack_service.dart:36`에서 `_tts.speak(text)` 호출 시 `focus` 인자를 안 넘겨서 **기본값 false → 오디오 포커스 요청 자체가 발생하지 않음** → 배경음(음악 등)이 전혀 덕킹되지 않고 TTS와 그대로 섞여 나감.

## 5. pubspec.yaml
- `pubspec.yaml:33`: `flutter_tts: ^4.2.0` — 위 3, 4번 기능(`setAudioAttributesForNavigation`, `speak(focus: true)`)은 모두 이 버전대에서 이미 지원됨(pub 문서/실물 소스 4.2.5 확인). 별도 업그레이드 불필요.

## 계약/사실 정리
- flutter_tts 노출 setter: `setVolume`(0.0~1.0, 소프트/상대값, 절대 게인 아님), `setSpeechRate`, `setPitch`, `setAudioAttributesForNavigation()`(파라미터 없음, usage 고정), `speak(text, {focus})`(focus=true 시 AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK 요청).
- "안드로이드 TTS 볼륨 소프트 상한" 가설 → **확인됨**: `setVolume(1.0)`은 이미 코드에 있으나 여전히 안 들린다는 증상과 일치 — 값 자체가 이미 상한이라 이 파라미터로는 더 키울 여지 없음. 실제 개선 지점은 볼륨 값이 아니라 **usage(스트림 라우팅)**와 **포커스/덕킹**.
- audio usage 지정 가능 여부 → **가능, API 존재, 현재 미호출**.

## 개선 후보 우선순위
1. **(c) 오디오 포커스 요청 + 덕킹** — `voice_pack_service.dart:36`의 `_tts.speak(text)`를 `_tts.speak(text, focus: true)`로 변경. 난이도: 매우 낮음(한 줄, 순수 Dart 설정). 위험: 낮음(포커스 요청 실패해도 speak 자체는 fallback 동작, 다만 실제 동작은 실기 검증 필요). 예상효과: 배경음(음악 등) 있을 때 가장 체감 큰 개선 — 터널/고속도로 소음엔 직접 영향 없지만 "다른 소리에 묻힘" 케이스는 해결.
2. **(b) audio usage를 내비/어시스턴트로 변경** — `_initTts()`에 `await _tts!.setAudioAttributesForNavigation();` 한 줄 추가. 난이도: 낮음(순수 Dart 설정, 네이티브 코드 안 건드림 — 플러그인이 이미 구현). 위험: 낮음~중(기기/OEM별 내비 스트림 볼륨이 사용자가 안 올려놓은 경우 오히려 더 작게 들릴 수 있음 — 실기 여러 대에서 검증 필요). 예상효과: 터널/고속도로 도로소음 상황에서 가장 근본적 개선 후보 — 미디어 볼륨과 분리된 스트림/우선순위 사용.
3. **(a) setVolume 명시 최대** — 이미 적용됨(`nav_screen.dart:336`). 추가로 얻을 게 없음(soft cap 이미 1.0).
4. **(d) 별도 게인/부스트** — 코드 레벨(setVolume)로 불가, 하려면 네이티브 손대야 함(예: `AudioTrack`/이퀄라이저로 후처리 게인, 또는 플랫폼 채널 추가해 `AudioManager.STREAM_ALARM` 등 다른 스트림 사용 + 볼륨 직접 조작). 난이도: 높음(네이티브 Android 코드 신규 작성, flutter_tts 밖의 영역). 위험: 중~높음(왜곡/클리핑, 배터리, OEM 별 동작 차이). 예상효과: 이론상 가장 크지만 구현·유지보수 비용 큼 — 1·2번으로 부족할 때만 고려.

**순수 설정(코드 변경 없이 pub 문서/소스만으로 확인 가능한 범위) vs 네이티브 필요 구분:**
- 순수 Dart 설정 변경만으로 가능: 1(focus:true), 2(setAudioAttributesForNavigation) — 둘 다 flutter_tts 4.2.5에 이미 내장, 네이티브 코드 추가 불필요.
- 네이티브 코드 필요: 4번만 (별도 게인/스트림 커스텀).
