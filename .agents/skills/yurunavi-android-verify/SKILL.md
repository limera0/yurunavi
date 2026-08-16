---
name: yurunavi-android-verify
description: Build, prepare, or assess YuruNavi Android release, real-device, navigation, lifecycle, overlay, PIP, GPS, rendering, memory, or ride verification. Use when automated tests cannot establish the final behavior.
---

# YuruNavi Android and Ride Verification

1. Read `.ai/TESTING.md` and `.ai/REAL_DEVICE.md` completely; read architecture only for affected components.
2. Complete automated analysis, focused tests, and the appropriate APK build before requesting human observation.
3. Use JDK 21. On the headless server build an APK and use adb when a device is available; do not depend on `flutter run`.
4. Prepare logging and a short reproducible scenario with an observable pass/fail result.
5. Never claim automated PASS as device PASS.
6. If human observation remains, ask in plain Korean for the minimum action and result, not technical diagnosis.
7. Record device/build, scenario, evidence, verdict, and remaining gate.
