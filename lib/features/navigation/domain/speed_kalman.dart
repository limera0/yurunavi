/// 1D GPS+IMU 속도융합 칼만필터 (순수 Dart, 센서·UI 의존 없음).
///
/// 상태 X = [v, b]  — v: 진행방향 속도(m/s), b: 가속도계 바이어스(m/s²).
/// 공분산 P 는 2×2. predict 는 IMU 가속도로 v 를 적분하고(b 는 불변 모델),
/// updateGps 는 도플러 속도로, updateZupt 는 정차(z=0)로 보정한다.
///
/// 모델(DESIGN 섹션2):
///   predict(a, dt):  v += (a - b)*dt;  P = A·P·Aᵀ + Q,  A = [[1,-dt],[0,1]]
///   updateGps(z, r): H=[1,0]; y=z-v; S=P00+r; K=[P00/S, P10/S];
///                    v+=K0·y; b+=K1·y; P=(I-K·H)·P
///   updateZupt():    updateGps(0, 0.01)  // 정차 강제 (r 매우 작게)
class SpeedKalman {
  // 상태
  double v; // 속도 (m/s)
  double b; // 가속도 바이어스 (m/s²)

  // 공분산 P (2×2): [[p00, p01], [p10, p11]]
  double p00, p01, p10, p11;

  // 프로세스 노이즈 Q = diag(qV, qB) (DESIGN 섹션3)
  final double qV;
  final double qB;

  // GPS 측정 노이즈 기본값 R (DESIGN 섹션3)
  final double rDefault;

  /// 초기값: v=0, b=0, P=diag(1,1), Q=diag(0.1, 0.001), R기본=4.0.
  SpeedKalman({
    this.v = 0.0,
    this.b = 0.0,
    this.p00 = 1.0,
    this.p01 = 0.0,
    this.p10 = 0.0,
    this.p11 = 1.0,
    this.qV = 0.1,
    this.qB = 0.001,
    this.rDefault = 4.0,
  });

  /// IMU 가속도 예측 스텝. [aMeas] 측정 가속도(m/s²·부호 포함), [dt] 경과초(s).
  void predict(double aMeas, double dt) {
    if (dt <= 0) return;
    // 상태 전이: v = v + (a - b)*dt, b 불변
    v = v + (aMeas - b) * dt;

    // A = [[1, -dt], [0, 1]] →  P = A·P·Aᵀ + Q
    // A·P:
    final ap00 = p00 - dt * p10;
    final ap01 = p01 - dt * p11;
    final ap10 = p10;
    final ap11 = p11;
    // (A·P)·Aᵀ,  Aᵀ = [[1,0],[-dt,1]]
    final np00 = ap00 - dt * ap01 + qV;
    final np01 = ap01;
    final np10 = ap10 - dt * ap11;
    final np11 = ap11 + qB;
    p00 = np00;
    p01 = np01;
    p10 = np10;
    p11 = np11;
  }

  /// GPS 도플러 보정. [zSpeed] 측정 속도(m/s), [r] 측정 노이즈.
  void updateGps(double zSpeed, double r) {
    final s = p00 + r;
    if (s <= 0) return;
    final k0 = p00 / s;
    final k1 = p10 / s;
    final y = zSpeed - v;
    v += k0 * y;
    b += k1 * y;
    // P = (I - K·H)·P,  H = [1, 0],  K·H = [[k0,0],[k1,0]]
    final np00 = (1 - k0) * p00;
    final np01 = (1 - k0) * p01;
    final np10 = p10 - k1 * p00;
    final np11 = p11 - k1 * p01;
    p00 = np00;
    p01 = np01;
    p10 = np10;
    p11 = np11;
  }

  /// 정차(ZUPT) 보정: z=0, r 매우 작게 → 속도 0으로 강제 끌어내림.
  void updateZupt() => updateGps(0.0, 0.01);

  /// 표시용 속도(km/h). 0~75 m/s clamp 후 km/h 변환 (RECON 외삽식과 동일 범위).
  double get speedKmh => v.clamp(0.0, 75.0) * 3.6;
}
