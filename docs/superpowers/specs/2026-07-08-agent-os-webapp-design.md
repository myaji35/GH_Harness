# Agent OS 웹앱 — 설계 스펙 (0000_master 흡수)

- 작성일: 2026-07-08
- 방식: 기존 0000_master(Next.js 16) 흡수 → "Agent OS"로 리브랜딩, localhost:3737
- 근거: 대표님이 이미지로 제시한 localhost:3737 "Agentic OS" 화면

## 원칙
0000_master를 재작성하지 않는다. 기존 page.tsx(칸반)·API 12개 유지, 사이드바 셸 + 신규 페이지 3개 + 포트만 얹는다 (Karpathy #3 외과적).

## 재사용 (기존 0000_master 자산)
- Next.js 16.1.6, 칸반 page.tsx, /api/projects·harness·scan·activity·vibe·reviews 등 12개 API
- lib/harness (meta cron, 프로젝트 스캔), lib/projects

## 신규 (얹는 것)
- layout.tsx: 사이드바 셸 (Agent OS 네비: Kanban/Memory/Hermes/Issues/Projects)
- memory/page.tsx + api/memory: 옵시디언 볼트 은하그래프 (graphify-out 제외)
- hermes/page.tsx + api/hermes: 22프로젝트 순회 자문 관제탑
- issues/page.tsx + api/issues: 이슈 등록 폼(POST)/조회(GET)
- package.json dev: next dev -p 3737

## 데이터 소스 통일
웹/CLI/Hermes cron 모두 같은 registry.json 공유. 웹 등록 이슈를 Hermes가 순회 자문.

## 사이드바 항목 (대표님 워크플로우만)
Agent OS 로고 · Kanban · Memory · Hermes 관제탑 · Issues · Projects
(이미지의 SEO/Video/Music/Game/Thumbnails/GLM은 대표님 것 아니므로 제외 — YAGNI)

## 검증
next dev -p 3737 기동 → 4페이지 200. Issues 폼 실제 등록 → registry 반영 + Hermes 순회 포착. Memory 노드수=볼트 노트수. 실제 브라우저 클릭 검증.

## 범위 밖
SEO/Music/Game 등 미사용 메뉴, 3D three.js 은하(2D로 시작).

## 옵시디언 볼트 경로 (확정)
메인: ~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian (📥아카이브 781노트)
⚠️ graphify-out/obsidian(652 자동생성물)은 쓰지 않음.
