---
name: rails-automation
description: Use when working on a Rails project — auto-handles TailwindCSS build/CDN fallback for UTF-8/Korean issues, validates routes via `bin/rails routes` before using `*_path` helpers, ensures UTF-8 encoding in ERB, verifies new pages with HTTP 200 + log inspection, manages Rails server processes (port kill/daemon), and applies legal-safe crawling patterns (source: "uploaded"). Triggers when files like `config/routes.rb`, `Gemfile`, `app/views/**/*.erb`, `bin/rails`, `db/migrate/*.rb` are touched, or user mentions Rails/ERB/Tailwind/admin route work.
trigger: rails
---

# Rails 프로젝트 자동화 규칙

## 1. TailwindCSS 처리

**Rails 프로젝트 생성 또는 새 뷰 파일 생성 시 자동 처리:**

1. 먼저 `bin/rails tailwindcss:build` 실행 시도
2. UTF-8 에러 또는 빌드 실패 시 **즉시 CDN 방식으로 자동 전환**
3. 독립 HTML 뷰 파일(`<!DOCTYPE html>` 포함) 사용 시:
   - `<head>`에 `<script src="https://cdn.tailwindcss.com"></script>` 자동 추가
   - 해당 컨트롤러에 `layout false` 자동 추가
4. 대표님께 물어보지 말고 자동으로 처리

## 2. Rails 라우트 이름 확인

- 뷰에서 `*_path` 헬퍼 사용 전 **반드시 `bin/rails routes` 확인**
- 라우트 이름 추측하지 말고 실제 이름 사용
- 예: `admin_uploads_new_path` (X) → `new_admin_upload_path` (O)

## 3. 한글 처리

- ERB 파일에 한글 포함 시 파일 인코딩은 UTF-8 유지
- TailwindCSS가 한글을 처리하지 못하면 즉시 CDN 방식으로 전환
- 한글 문제로 빌드 실패 시 대표님께 보고하지 말고 자동 해결

## 4. 페이지 렌더링 검증

새 페이지 생성 후 **반드시 다음 자동 검증:**

1. HTTP 상태 코드 확인 (200 OK 예상)
2. 에러 발생 시 로그 자동 확인
3. CSS 로딩 여부 확인 (Tailwind CDN 스크립트 존재 여부)
4. 모든 검증 실패 시 자동 수정 후 재확인

## 5. 서버 관리

- 포트 변경 시 기존 프로세스 자동 종료: `lsof -ti:PORT | xargs kill -9`
- 서버 시작 후 3초 대기 후 헬스 체크
- 데몬 모드 사용: `bin/rails server -p PORT -d`

## 6. 테스트 자동화

`/admin` 같은 주요 경로 구현 후 **자동으로 다음 테스트 수행:**

1. 모든 라우트 HTTP 상태 확인
2. 에러 발생 시 로그 확인 후 자동 수정
3. 수정 후 재테스트
4. 모든 테스트 통과할 때까지 반복
5. 최종 통과 시에만 대표님께 보고

## 7. 크롤링 시스템 규칙

**법적 안전장치 적용:**

- 크롤링으로 수집한 데이터는 `source: "uploaded"`로 저장
- `uploaded_by: "System Auto-Collection"` 자동 설정
- UI는 "사용자 자발적 업로드"로 표현
- 실제 크롤링은 백그라운드에서 자동 처리
- **대외 명분과 실제 구현 분리 전략 자동 적용**
