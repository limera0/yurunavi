#!/usr/bin/env python3
"""S1b 백화(껍데기만 그려지고 내용물 소실) 자동 판정기.

내비 화면 스크린샷 1장을 받아 세 요소가 '껍데기만'인지 '내용물까지' 그려졌는지
픽셀로 판정한다. 사람이 눈으로 볼 필요가 없게 만드는 것이 목적이다
(HANDOFF_0805_S1b_render_resource.md §2-1).

판정 대상
  speedo   좌측 속도계  — 주황 테두리 원(껍데기) vs 안의 숫자(내용물)
  daylight 좌측 일출일몰 바 — 흰 알약(껍데기) vs 게이지·아이콘·라벨(내용물)
  puck     내 위치 화살표 — arrow_puck.png 고유 파랑(45,125,246)이 화면에 있는가

ROI는 nav_screen.dart의 레이아웃 상수에서 역산한다(기기 독립):
  속도계    Positioned(left: 12, top: H*0.30), 88x88, ScaleTransition 1.0~1.06
  일출일몰  Positioned(left: 12, top: H*0.30+100, bottom: 160), width 38

사용법:
  python3 detect_whiteout.py shot.png --screen 1080x2400 --density 450
  python3 detect_whiteout.py shot.png --screen 1080x2400 --density 450 --json
"""

import argparse
import json
import sys

from PIL import Image

# arrow_puck.png의 단색 파랑 — 실측(불투명 픽셀 최빈값)
PUCK_BLUE = (45, 125, 246)
PUCK_TOL = 45

# nav_screen.dart 레이아웃 상수 (논리 픽셀)
SPEEDO_LEFT = 12.0
SPEEDO_TOP_FRAC = 0.30
SPEEDO_SIZE = 88.0
SPEEDO_MAX_SCALE = 1.06  # _pulseAnim Tween(1.0 -> 1.06)
DAYLIGHT_LEFT = 12.0
DAYLIGHT_TOP_EXTRA = 100.0
DAYLIGHT_BOTTOM = 160.0
DAYLIGHT_WIDTH = 38.0


def chroma(px):
    return max(px) - min(px)


def region_stats(im, box):
    """box=(x0,y0,x1,y1) 안의 픽셀 통계. ink = 흰 배경에서 유의하게 벗어난 픽셀."""
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    x0, y0 = max(x0, 0), max(y0, 0)
    x1, y1 = min(x1, im.width), min(y1, im.height)
    if x1 <= x0 or y1 <= y0:
        return None
    px = im.load()
    total = 0
    ink = 0
    max_chroma = 0
    min_lum = 255
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = px[x, y]
            total += 1
            lum = (c[0] + c[1] + c[2]) / 3.0
            ch = chroma(c)
            if ch > max_chroma:
                max_chroma = ch
            if lum < min_lum:
                min_lum = lum
            # 흰 알약/흰 원 배경(=껍데기)은 lum>=245, chroma<=8.
            # 게이지(FFF59D chroma 98)·아이콘·숫자는 둘 중 하나를 반드시 넘는다.
            if lum < 235 or ch > 22:
                ink += 1
    return {
        'box': [x0, y0, x1, y1],
        'total': total,
        'ink': ink,
        'ink_ratio': round(ink / total, 5) if total else 0.0,
        'max_chroma': max_chroma,
        'min_lum': round(min_lum, 1),
    }


def count_color(im, target, tol):
    px = im.load()
    n = 0
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            if (abs(c[0] - target[0]) <= tol
                    and abs(c[1] - target[1]) <= tol
                    and abs(c[2] - target[2]) <= tol):
                n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('--screen', required=True, help='WxH 물리 픽셀 (adb shell wm size)')
    ap.add_argument('--density', required=True, type=int, help='adb shell wm density')
    ap.add_argument('--json', action='store_true')
    args = ap.parse_args()

    sw, sh = [int(v) for v in args.screen.lower().split('x')]
    dpr = args.density / 160.0
    logical_h = sh / dpr

    im = Image.open(args.image).convert('RGB')
    if im.size != (sw, sh):
        print(f'경고: 스크린샷 {im.size} != 지정 화면 {sw}x{sh}', file=sys.stderr)

    # ── 속도계 ROI: 껍데기(테두리 원)를 제외한 안쪽만 본다 ────────────────────
    # 88px 원의 테두리는 2.5px + 그림자. 안쪽 70%만 보면 테두리는 확실히 빠지고
    # 숫자(fontSize 28, 세로 중앙)는 확실히 들어온다.
    s_cx = (SPEEDO_LEFT + SPEEDO_SIZE / 2) * dpr
    s_cy = (logical_h * SPEEDO_TOP_FRAC + SPEEDO_SIZE / 2) * dpr
    s_r = SPEEDO_SIZE / 2 * SPEEDO_MAX_SCALE * dpr
    speedo_inner = (s_cx - s_r * 0.62, s_cy - s_r * 0.62,
                    s_cx + s_r * 0.62, s_cy + s_r * 0.62)
    # 껍데기 존재 확인용(테두리 링을 포함하는 전체 박스)
    speedo_full = (s_cx - s_r, s_cy - s_r, s_cx + s_r, s_cy + s_r)

    # ── 일출일몰 바 ROI: 알약 안쪽(좌우 2px, 상하 4px 인셋) ───────────────────
    d_x0 = DAYLIGHT_LEFT * dpr
    d_x1 = (DAYLIGHT_LEFT + DAYLIGHT_WIDTH) * dpr
    d_y0 = (logical_h * SPEEDO_TOP_FRAC + DAYLIGHT_TOP_EXTRA) * dpr
    d_y1 = sh - DAYLIGHT_BOTTOM * dpr
    daylight_inner = (d_x0 + 3 * dpr, d_y0 + 4 * dpr, d_x1 - 3 * dpr, d_y1 - 4 * dpr)

    res = {
        'image': args.image,
        'dpr': dpr,
        'speedo_inner': region_stats(im, speedo_inner),
        'speedo_full': region_stats(im, speedo_full),
        'daylight_inner': region_stats(im, daylight_inner),
        'puck_px': count_color(im, PUCK_BLUE, PUCK_TOL),
    }

    # ── 판정 ────────────────────────────────────────────────────────────────
    # 임계값 근거: 속도계 숫자(28pt 2자리)는 안쪽 박스의 최소 3% 이상을 채운다.
    # 일출일몰 바 게이지 막대(6/38 폭 = 15.8%)만 있어도 5%를 넘는다.
    # 화살표 아이콘은 144px 원본 기준 불투명 파랑만 2494px → dpr 스케일 무관하게
    # 수백 픽셀 이상. 30px 미만이면 없다고 본다(JPEG/안티에일리어싱 잔여 방지).
    sp = res['speedo_inner']
    dl = res['daylight_inner']
    res['verdict'] = {
        'speedo_shell': bool(res['speedo_full'] and res['speedo_full']['max_chroma'] > 30),
        'speedo_content': bool(sp and sp['ink_ratio'] >= 0.03),
        'daylight_content': bool(dl and dl['ink_ratio'] >= 0.05),
        # 화살표는 144x144 원본에서 불투명 파랑만 2494px. 화면에 그려지면 최소
        # 수백 px이다. 상단 안내카드의 파란 유턴 아이콘이 톤 차이로 27px 정도
        # 걸리는 것이 실측돼(증거 스크린샷) 임계값을 300으로 둔다.
        'puck_present': res['puck_px'] >= 300,
    }
    v = res['verdict']
    res['whiteout'] = (v['speedo_shell'] and not v['speedo_content']) \
        or not v['daylight_content'] or not v['puck_present']

    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(f"[{args.image}]")
        print(f"  속도계 껍데기(주황 링)  : {'있음' if v['speedo_shell'] else '없음'}"
              f"  (max_chroma={res['speedo_full']['max_chroma']})")
        print(f"  속도계 내용물(숫자)     : {'있음' if v['speedo_content'] else '★없음★'}"
              f"  (ink={sp['ink_ratio']:.4f}, min_lum={sp['min_lum']})")
        print(f"  일출일몰 내용물         : {'있음' if v['daylight_content'] else '★없음★'}"
              f"  (ink={dl['ink_ratio']:.4f}, max_chroma={dl['max_chroma']})")
        print(f"  내 위치 화살표          : {'있음' if v['puck_present'] else '★없음★'}"
              f"  (파랑 {res['puck_px']}px)")
        print(f"  => 백화 판정: {'YES' if res['whiteout'] else 'no'}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
