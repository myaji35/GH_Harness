#!/usr/bin/env python3
"""[demo-video-builder 스킬 참고 스크립트] 씬 이미지 생성 — 레터박스+자막+로고 인트로+아웃트로.
재사용 시 바꿀 것: PANELS(캡처 경로) · SCENES(씬 대장) · logo_card의 도메인/태그라인 · 아웃트로 멘트.
아래는 전통시장 데모 예시다.

전통시장 데모 — 로고 인트로 → 전체 조망 → 8카드 설명(우측 Params/Result 프리뷰).

씬 소스 = panels2/ (완료 상태, 1600x1000 와이드, "전체" 뷰).
- intro : 로고 타이틀 카드
- s0    : "전체" 뷰 전체 조망(overview) — 설명 시작점
- s1~s8 : 카드 클릭 화면(판 + 우측 패널 Params/Result 프리뷰)
- outro : 마무리 멘트
build_video_v2.sh 가 나레이션+keyframe강제로 mp4.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SCRATCH = Path("/private/tmp/claude-501/-Volumes-E-SSD-02-GitHub-nosync-0035-XimTier-ENG2/e6bbf34e-573b-4f05-aeac-6918ceee1ce1/scratchpad")
PANELS = SCRATCH / "panels2"
OUT = Path(__file__).resolve().parent / "market_scenes"
OUT.mkdir(exist_ok=True)

CANVAS = (1280, 720)  # 16:9 와이드
FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
sub_font = ImageFont.truetype(FONT, 28)
logo_font = ImageFont.truetype(FONT, 72)
title_font = ImageFont.truetype(FONT, 58)
subt_font = ImageFont.truetype(FONT, 28)

# 씬 = (panels2 파일, 자막). s0=전체 조망이 설명 시작점.
SCENES = [
    ("overview", "s0", "WorkFlow 전체보기 — 28개 카드가 한 흐름으로 이어집니다"),
    ("s1", "s1", "① 데이터 파일 업로드 — 365일치 매출·요인, 5개 시트"),
    ("s2", "s2", "② AI SNS 감성 평가 — 게시글 긍정·부정 분석"),
    ("s3", "s3", "③ AI 전체 알고리즘 학습 — 59종 경쟁 · R² 0.966 랜덤포레스트"),
    ("s4", "s4", "④ 변수 관계 지식그래프 — 무엇이 매출을 움직이나"),
    ("s5", "s5", "⑤ AI 트리거 시뮬레이션 — 연쇄 효과 예측"),
    ("s6", "s6", "⑥ Y변수 5분위 — 매출 구간별 특성"),
    ("s7", "s7", "⑦ 전략별 최적값 — 목표 매출 달성 3가지 길"),
    ("s8", "s8", "⑧ AI 종합의견 — 실행 방안 자동 생성"),
]


def fit(img, bg=(244, 245, 247)):
    """1600x1000 → 1280x720 레터박스. 좌우 여백 최소, 세로 안 잘림."""
    img = img.copy()
    img.thumbnail(CANVAS, Image.Resampling.LANCZOS)
    c = Image.new("RGB", CANVAS, bg)
    c.paste(img, ((CANVAS[0] - img.width) // 2, (CANVAS[1] - img.height) // 2))
    return c


def subtitle(c, text):
    d = ImageDraw.Draw(c, "RGBA")
    l, t, r, b = d.textbbox((0, 0), text, font=sub_font)
    tw, th = r - l, b - t
    px, py = 22, 13
    bw, bh = tw + px * 2, th + py * 2
    bx = (CANVAS[0] - bw) // 2
    by = CANVAS[1] - 22 - bh
    d.rectangle((bx, by, bx + bw, by + bh), fill=(15, 23, 42, 225))
    d.text((bx + px - l, by + py - t), text, font=sub_font, fill=(255, 255, 255))


sign_font = ImageFont.truetype(FONT, 20)


def logo_card(fn):
    """로고 인트로 — 부담 없는 은은한 배경 + XimTier 로고 + 우하단 서명."""
    W, H = CANVAS
    # 은은한 세로 그라디언트 배경 (#0a0e1a → #131a2e, 부담 없는 다크)
    c = Image.new("RGB", CANVAS)
    top, bot = (10, 14, 26), (19, 26, 46)
    px = c.load()
    for y in range(H):
        r_ = top[0] + (bot[0] - top[0]) * y // H
        g_ = top[1] + (bot[1] - top[1]) * y // H
        b_ = top[2] + (bot[2] - top[2]) * y // H
        for x in range(W):
            px[x, y] = (r_, g_, b_)
    d = ImageDraw.Draw(c, "RGBA")
    # 은은한 도트 두 개(브랜드 옐로우/블루) — 부담 없는 포인트
    d.ellipse((-180, -180, 260, 260), fill=(250, 204, 21, 14))
    d.ellipse((W - 300, H - 300, W + 160, H + 160), fill=(30, 58, 138, 40))
    d.rectangle((0, 0, W, 6), fill=(250, 204, 21))
    # 워드마크 + 태그라인
    logo = "XimTier"
    l, t, r, b = d.textbbox((0, 0), logo, font=logo_font)
    d.text(((W - (r - l)) // 2 - l, 270), logo, font=logo_font, fill=(255, 255, 255))
    tag = "설명가능 AI 분석 — 전통시장 상권분석"
    l2, t2, r2, b2 = d.textbbox((0, 0), tag, font=subt_font)
    d.text(((W - (r2 - l2)) // 2 - l2, 380), tag, font=subt_font, fill=(148, 163, 184))
    # 우하단 작게 서명
    sign = "Created by XimTier.com"
    ls, ts, rs, bs = d.textbbox((0, 0), sign, font=sign_font)
    d.text((W - (rs - ls) - 28, H - (bs - ts) - 24), sign, font=sign_font, fill=(120, 132, 156))
    c.save(OUT / fn)


def title_card(main, sub, fn):
    c = Image.new("RGB", CANVAS, (10, 14, 26))
    d = ImageDraw.Draw(c)
    d.rectangle((0, 0, CANVAS[0], 6), fill=(250, 204, 21))
    l, t, r, b = d.textbbox((0, 0), main, font=title_font)
    d.text(((CANVAS[0] - (r - l)) // 2 - l, 290), main, font=title_font, fill=(255, 255, 255))
    if sub:
        l2, t2, r2, b2 = d.textbbox((0, 0), sub, font=subt_font)
        d.text(((CANVAS[0] - (r2 - l2)) // 2 - l2, 385), sub, font=subt_font, fill=(148, 163, 184))
    c.save(OUT / fn)


# 인트로 = 로고 화면
logo_card("scene_intro.png")
print("intro(로고)")

# 본편: 전체 조망(s0) + 8카드
for panel, sid, sub in SCENES:
    img = Image.open(PANELS / f"{panel}.png")
    c = fit(img)
    subtitle(c, sub)
    c.save(OUT / f"scene_{sid}.png")
    print(f"{sid} <- {panel}")

# 아웃트로
title_card("XimTier", "더 나은 솔루션으로 찾아 뵙겠습니다", "scene_outro.png")
print("outro")
print("완료:", OUT)
