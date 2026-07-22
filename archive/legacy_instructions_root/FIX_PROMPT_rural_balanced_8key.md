# 보정 — _ruralBalancedOpts 폴백 프로필도 8키로 (5키 잔존 제거)

> 환경: Claude Code on Ubuntu(westinx). 단일 파일 `lib/services/routing_service.dart`, 단일 함수 `_ruralBalancedOpts`(L85 부근)만 수정.
> 배경: 직전 커밋(72c31c1)에서 3코스 class_factors는 0~7 8키로 교체됐으나, 시골길 1.3배 폴백 프로필 `_ruralBalancedOpts`가 옛 5키('1'~'5')를 그대로 사용 중. 포크가 이를 0~7로 해석 → motorway(0)/trunk(1) 회피 누락 → 폴백 발동 시 고속도로·자동차전용도로로 경로가 샐 위험.

## STEP 0 — 정찰 (정지)

- `_ruralBalancedOpts`(L85~95 부근)의 현재 class_factors와 나머지 키를 `view`로 확인해 그대로 보고.
- 이 프로필의 **의도**가 "시골길이 너무 돌아갈 때 지방도를 일부 허용하는 균형 프로필"임을 전제로, 5키가 어떤 값이었는지 보고.
- 정지. 마스터 확인 대기.

## STEP 1 — 교체

`_ruralBalancedOpts`의 class_factors를 0~7 8키로 교체. **balanced = 시골길과 지방도 중간** 성격:

- motorway(0)/trunk(1)은 **반드시 100 회피**(누락이 이번 버그의 핵심).
- 시군도/소로를 선호하되, 시골길보다 지방도(secondary)·국도(primary)를 덜 페널티 → 우회 거리 단축.

```
"class_factors": {"0":100,"1":100,"2":3.0,"3":1.0,"4":0.7,"5":1.0,"6":1.2,"7":2.0}
```

의미: 국도(2)는 시골길의 6보다 완화한 3(폴백이니 일부 허용), 지방도(3)는 중립 1.0, 시군도(4) 선호 0.7. 시골길 순수 프로필(4=0.6, 2=6)과 지방도 프로필(3=0.5) 사이의 중간값.

- class_factors 외 다른 키(use_highways/top_speed 등)는 **그대로 유지**.
- 옛 5키는 완전 제거. urban_penalty 있으면 제거.

수정 후 `git diff lib/services/routing_service.dart` 보고. 빌드하지 않음. 정지.

## STEP 2 — 커밋 (마스터 확인 후)

- `fix(routing): _ruralBalancedOpts 폴백도 0~7 8키로 (motorway/trunk 회피 누락 수정)`
- 단일 파일. 정지.

## 참고

이걸로 routing_service.dart의 5키 잔존이 완전히 제거된다. 이후 grep으로 확인:
`grep -n '"1"\|"2"\|"3"\|"4"\|"5"' lib/services/routing_service.dart` 에 class_factors 관련 5키가 더 없어야 함(다른 용도의 숫자 문자열은 무관).
