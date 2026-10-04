# GH_Harness mods

`mods/.claude-plugin/marketplace.json`은 로컬 Claude Code 마켓 `gh-harness-mods`를 정의합니다. `harness-guard/`는 기존 PreToolUse 가드를 플러그인으로 제공하며 기본값은 `shadow`입니다. `harness-status/`는 하네스 상태를 읽기 전용으로 보여줍니다. 기존 셸 훅도 계속 동작합니다.

## 설치

저장소의 `install.sh`를 실행하면 Claude Code 2.1.287 이상에서 사용자 범위 마켓과 두 플러그인을 자동 설치합니다. 배치 설치에서도 한 번만 처리합니다. 모드 설치를 생략하려면 `./install.sh --no-mods`를 사용하세요. 이미 설치된 플러그인의 설정은 유지됩니다.

수동 설치는 저장소 루트에서 다음 명령을 실행합니다.

```bash
claude plugin marketplace add "$(pwd)/mods"
claude plugin install harness-guard@gh-harness-mods --scope user --config mode=shadow -y
claude plugin install harness-status@gh-harness-mods --scope user -y
```

마켓을 이미 등록했다면 `add` 대신 `claude plugin marketplace update gh-harness-mods`를 실행합니다.

## 끄기와 모드 변경

가드 플러그인만 끄려면 다음을 실행합니다.

```bash
claude plugin disable harness-guard@gh-harness-mods
```

가드가 실제 차단을 수행하도록 바꾸려면 다음을 실행합니다. 현재 값은 `claude plugin configure harness-guard@gh-harness-mods`로 확인할 수 있습니다.

```bash
printf '{"mode":"enforce"}\n' | claude plugin configure harness-guard@gh-harness-mods --values-stdin
```

`shadow`로 되돌릴 때는 같은 명령에서 `enforce`를 `shadow`로 바꿉니다.

## 롤백

우선 `./install.sh --no-mods`로 이후 자동 설치를 피하고, 설치된 플러그인과 마켓을 제거합니다.

```bash
claude plugin uninstall harness-guard@gh-harness-mods --scope user
claude plugin uninstall harness-status@gh-harness-mods --scope user
claude plugin marketplace remove gh-harness-mods
```

이 절차는 기존 GH_Harness 셸 훅 설치를 제거하지 않습니다.
