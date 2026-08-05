/// 상한이 하한보다 작으면 하한을 반환하는 안전한 clamp.
///
/// dart:core `num.clamp`는 `upper < lower`일 때 `ArgumentError(lowerLimit)`를
/// 던진다. 렌더·인덱스 경로에서 그 예외는 프레임 전체를 `ErrorWidget`으로
/// 날려버리므로, 값이 뭉개지더라도 던지지 않는 쪽이 옳다.
///
/// 주의: 이건 "의미가 없는 값이라도 던지지만 않으면 되는" 자리에만 쓴다.
/// 리스트가 비어서 인덱싱 자체가 틀린 자리는 조기 반환으로 막아라.
extension SafeClamp on num {
  num clampSafe(num lower, num upper) =>
      upper < lower ? lower : clamp(lower, upper);
}
