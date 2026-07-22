#!/usr/bin/env node
/**
 * merge_fonts.js — Bold/Italic 글리프에 CJK(한글) 폴백을 미리 합쳐
 * 단일 폰트 폴더로 굽는다. 콤마 concat을 URL에서 제거 → Cloudflare 차단·캐시 비효율 회피.
 *
 * 동작: 각 range(0-255 ... 65280-65535)마다
 *   combine([Bold pbf, CJK pbf]) → 합본 pbf 저장.
 *   배열 순서가 우선순위: 같은 글자는 앞(Bold)이 이김, 없는 글자(한글)는 뒤(CJK)에서 채움.
 *
 * 사용법:
 *   node merge_fonts.js <fontsDir> <primaryName> <fallbackName> <outName>
 * 예:
 *   node merge_fonts.js /data/tiles/fonts "Noto Sans Bold"   "Noto Sans CJK TC Regular" "Noto Sans Bold"
 *   node merge_fonts.js /data/tiles/fonts "Noto Sans Italic" "Noto Sans CJK TC Regular" "Noto Sans Italic"
 *
 * ※ outName을 primary와 같게 주면 기존 Bold 폴더를 "한글 포함 Bold"로 덮어쓴다.
 *   원본 보존을 원하면 outName을 "Noto Sans Bold CJK" 등으로.
 */
const fs = require('fs');
const path = require('path');
const composite = require('@mapbox/glyph-pbf-composite');

const [,, fontsDir, primary, fallback, outName] = process.argv;
if (!fontsDir || !primary || !fallback || !outName) {
  console.error('Usage: node merge_fonts.js <fontsDir> <primaryName> <fallbackName> <outName>');
  process.exit(1);
}

const primaryDir  = path.join(fontsDir, primary);
const fallbackDir = path.join(fontsDir, fallback);
const outDir      = path.join(fontsDir, outName);

for (const d of [primaryDir, fallbackDir]) {
  if (!fs.existsSync(d)) { console.error('없는 폴더:', d); process.exit(1); }
}
fs.mkdirSync(outDir, { recursive: true });

let merged = 0, primaryOnly = 0, skipped = 0;
// 표준 글리프 범위: 0-255 단위, 0 ~ 65535 (256개 파일)
for (let start = 0; start < 65536; start += 256) {
  const range = `${start}-${start + 255}.pbf`;
  const pPath = path.join(primaryDir, range);
  const fPath = path.join(fallbackDir, range);

  const hasP = fs.existsSync(pPath);
  const hasF = fs.existsSync(fPath);
  if (!hasP && !hasF) { skipped++; continue; }

  const bufs = [];
  if (hasP) bufs.push(fs.readFileSync(pPath));  // 우선순위 앞
  if (hasF) bufs.push(fs.readFileSync(fPath));  // 폴백 뒤

  try {
    const out = composite.combine(bufs, null); // fontstack 이름은 null=자동
    fs.writeFileSync(path.join(outDir, range), out);
    if (hasP && hasF) merged++; else primaryOnly++;
  } catch (e) {
    console.error('combine 실패 range', range, e.message);
  }
}
console.log(`완료: ${outName}`);
console.log(`  병합(primary+CJK): ${merged}, 단독: ${primaryOnly}, 빈 range 스킵: ${skipped}`);
console.log(`  출력: ${outDir}`);
