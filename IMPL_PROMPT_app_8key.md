# 구현 프롬프트 — 앱 class_factors 5키 → 0~7 8키 교체

> 환경: Claude Code on Ubuntu(westinx). 코드 수정(Dart). 빌드는 마스터가 별도.
> 목표: `routing_service.dart`의 세 코스(시골길/지방도/국도) class_factors를 5키("1"~"5")에서 **RoadClass 0~7 직결 8키**로 교체. 포크 엔진이 0~7 map을 받으므로 앱도 0~7로 보내야 한다.
> URL은 변경하지 않는다(운영 8002를 포크로 교체하는 2안이라 valhalla.westinx.com 그대로).

## 배경 — 확정된 한국 매핑

0 motorway=고속도로 / 1 trunk=도시고속·자동차전용 / 2 primary=일반국도 / 3 secondary=지방도 / 4 tertiary=시군도 / 5 unclassified=소로 / 6 residential=마을 / 7 service=농로.
★ motorway(0)+trunk(1)은 세 코스 전부 회피(이륜차 부적합). 일반국도=primary(2).

## STEP 0 — 정찰 (읽기전용, 정지)

- `lib/services/routing_service.dart`에서 현재 세 코스 costing_options 블록(정찰 기준 L143~188)을 `view`로 **현재 실제 내용** 확인. 줄번호는 이동했을 수 있으니 실파일 기준으로.
- 세 코스의 class_factors 외 다른 키(use_highways/use_living_streets/use_tracks/top_speed/shortest 등)가 어떻게 들어있는지 그대로 보고.
- **class_factors만 교체**하고 나머지 키는 건드리지 않을 것임을 확인.
- 여기서 정지. 현재 블록 내용 보고 후 마스터 확인 대기.

## STEP 1 — 교체 (class_factors 8키)

각 코스의 class_factors를 아래로 교체. **다른 키(use_highways 등)는 그대로 유지.**

시골길:

```
"class_factors": {"0":100,"1":100,"2":6,"3":2,"4":0.6,"5":0.8,"6":0.9,"7":1.0}
```

지방도:

```
"class_factors": {"0":100,"1":100,"2":2.0,"3":0.5,"4":0.9,"5":1.5,"6":2.0,"7":3.0}
```

국도:

```
"class_factors": {"0":100,"1":100,"2":0.5,"3":1.2,"4":2.0,"5":4.0,"6":5.0,"7":8.0}
```

주의:

- 기존 5키("1"~"5")는 **완전히 제거**하고 8키로 대체(키 의미가 바뀜: 옛 "1"=고속, 새 "0"=고속). 5키가 남아있으면 포크가 키 0,1을 못 받아 고속/자동차전용 회피가 안 된다.
- urban_penalty 키가 있으면 제거(엔진 미구현, 무해하지만 정리).
- Dart 숫자 리터럴 타입 주의: JSON 직렬화 시 정수/실수 섞여도 됨(포크가 GetDouble로 안전 수신). 기존 코드의 Map 타입에 맞춰 작성.

수정 후 `git diff lib/services/routing_service.dart` 보고. **빌드하지 않는다. 정지.**

## STEP 2 — 커밋 (마스터 확인 후)

- diff 이상 없으면 단일 커밋: `feat(routing): class_factors 5키→RoadClass 0~7 8키 (포크 엔진 연동)`
- 한 파일 스코프. 정지.

## 범위 밖

- APK 빌드/설치 — 마스터.
- 운영 docker 교체 — 별도 트랙(마스터 직접).
- nav_screen/2차축 등 — 손대지 않음.
