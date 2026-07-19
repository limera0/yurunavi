# RECON — 투어 기록 완전 유실 (실주행 20-30분+ 라이딩, 저장 0건)

## 배경
실제 20-30분+ 라이딩 후 "투어 기록" 화면에 아무것도 남지 않은 사례 조사.
가설 A(역지오코딩 예외로 인한 unawaited silent failure)와 가설 B(dispose()가
프로세스 종료 시 안 불림)를 조사.

## 결론: 가설 B가 유력한 전체 설명, 가설 A는 이미 안전하게 처리돼 있었음(방어 한 겹 추가)

### 가설 A — GeocodingService.reverseGeocode()

`lib/services/geocoding_service.dart`는 이미 전체를 `try/catch`로 감싸고 있고
어떤 실패든 `null`을 반환한다(예외를 던지지 않음). `TourLog.copyWith`도
`startAddress`/`endAddress` null을 정상 처리한다. 즉 이 경로 자체는 이미
안전했다 — 이번 사례의 원인은 아니었을 가능성이 높다.

다만 `_finalizeAndPersistTour()`(`nav_screen.dart`) 안에서 `Future.wait([...])`
결과와 `TourLogService().add(finalLog)` 호출 자체는 try/catch 없이 노출돼
있었다. 이 함수는 `unawaited(...)`으로 호출되므로, **어떤 이유로든**(예:
`shared_preferences` 플러그인 쪽 예외 등) 예외가 나면 크래시도 없고
성공 로그(`YNAV_TOUR saved`)도 없이 조용히 사라진다 — 실패 로그조차 없어
사후 진단이 불가능했다. 이번 커밋에서 지오코딩 블록과 저장 블록을 각각
try/catch로 감싸 (1) 지오코딩 실패해도 주소 없이 저장은 계속 진행하고
(2) 어느 쪽이 실패하든 `debugPrint`로 원인이 로그에 남도록 방어를 추가함.

### 가설 B — dispose()는 프로세스 kill을 잡지 못한다 (구조적 한계, 미해결)

`_NavScreenState`는 `SingleTickerProviderStateMixin`만 mixin하고 있고
`WidgetsBindingObserver`/`didChangeAppLifecycleState`는 **어디에도 구현돼
있지 않다**(코드 내 주석 하나에만 언급됨, 실제 등록 없음). `dispose()`는
Flutter 위젯 트리 차원의 콜백일 뿐 — Android가 프로세스를 통째로 죽이면
(태스크 스와이프, 제조사 배터리 매니저의 강제 종료, 메모리 부족 OOM kill)
Dart VM/Flutter 엔진 자체가 사라지므로 `dispose()`도, 그 안의
"안전망"(`_finalizeAndPersistTour()`)도 절대 실행되지 않는다.

`NavForegroundService`(`android/app/.../NavForegroundService.kt`)가 진짜
Android 포그라운드 서비스로 프로세스를 보호하긴 하지만, `onTaskRemoved()`
오버라이드가 없고 `START_NOT_STICKY`라 OEM 배터리 매니저(MIUI/원플러스/
삼성 등, "Don't kill my app!" 로 유명한 부류)가 태스크 스와이프나 화면 꺼짐
후 앱 프로세스를 강제 종료하면 서비스도 Dart 엔진도 함께 죽는다 — 재시작도
안 된다.

`TourRecorder`(`lib/features/navigation/tour_recorder.dart`)를 확인한 결과:
- **원시 GPS 트랙 포인트는 즉시 디스크에 append된다**(`TourTrackWriter`,
  메모리 버퍼링 없음, 클래스 상단 주석에도 명시).
- 하지만 히스토리 화면에 실제로 표시되는 **요약 레코드(`TourLog`: 거리/시간/
  평균속도/주소)는 오직 `finish()` 호출 시점에만 계산되고, `TourLogService
  .add()`로 저장되는 것도 `_finalizeAndPersistTour()`가 끝까지 실행됐을
  때뿐이다.**

즉 프로세스가 `finish()`/`_finalizeAndPersistTour()` 전에 죽으면: 원시 트랙
.jsonl 파일은 디스크에 남아있지만(고아 파일), `TourLogService`(SharedPreferences
`tour_logs_v1`)에는 아무 항목도 추가되지 않는다. 히스토리 화면은 정확히
이 저장소를 그대로 읽으므로(`tour_log_providers.dart` → `TourLogService
.loadAll()`, 같은 키) — "완전히 아무것도 기록되지 않음"이라는 이번 증상과
정확히 일치한다. (주소만 빠진 게 아니라 항목 자체가 없는 것.)

세 번째 가설(히스토리 화면이 다른/오래된 소스를 읽음)은 기각 — 읽기/쓰기가
동일한 `TourLogService`/동일 키(`tour_logs_v1`)를 사용한다.

## 남은 구조적 한계 (이번 작업 범위 밖)

프로세스가 통째로 죽는 경우에 대한 근본 해결은 다음 중 하나가 필요하며,
둘 다 이번 태스크 범위를 벗어나는 더 큰 작업이다:

1. **주기적 부분 저장**: `TourRecorder.onFix()`가 트랙 포인트를 채택할
   때마다(또는 N초 간격으로) 그 시점까지의 부분 `TourLog`를
   `TourLogService`에 upsert — 프로세스가 죽어도 마지막 체크포인트까지는
   남는다. 되돌리기(dedup)/부분 데이터 UX 처리가 필요.
2. **네이티브 `onTaskRemoved()` 훅 + headless Dart 콜백**으로 종료 시점에
   최종 요약을 강제로 flush — Flutter headless execution 설정이 필요한
   더 무거운 작업.

둘 다 지금 당장 구현하지 않음 — 이번 커밋은 가설 A 계열(unawaited 함수
내부 무방비 예외로 인한 완전 무로그 유실)만 방어적으로 보강했다.
