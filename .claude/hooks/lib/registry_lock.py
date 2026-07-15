"""registry_lock — registry.json 원자적 read-modify-write

왜 필요한가 (2026-07-15 감사):
    훅 16개가 registry.json을 read-modify-write 하는데 락이 0개였다.
    settings.json은 Stop/SubagentStop 이벤트에 훅 2개(on-agent-complete, meta-review)를
    동시에 건다 → 둘 다 registry를 쓴다 → 나중에 쓴 쪽이 상대 변경을 통째로 덮어쓴다.
    이슈 유실은 조용히 일어나며 탐지 수단이 없었다.

    실제로 터진 기록:
      87d498e "registry 데이터 손상 복구"
      5df926c "손상 registry.json 격리 후 계속"

    역설: hermes-escalate.sh:201 에는 이미 락이 있었다. 락이 필요하다는 걸
    알면서 정작 핵심 경로(on_complete/on_fail/dispatch-ready)엔 안 넣었다.

설계:
    - flock(1)은 macOS에 없다 → POSIX 공통인 python fcntl 사용
    - 별도 .lock 파일에 배타 락 (registry.json 자체를 잠그면 rename과 충돌)
    - 쓰기는 tmp + os.replace 로 원자화 (부분 기록된 JSON 방지)
    - 타임아웃 초과 시 예외 — 조용히 진행해서 덮어쓰는 것보다 실패가 낫다

사용법:
    from registry_lock import registry_txn

    with registry_txn(path) as reg:      # 읽기+락
        reg["issues"].append(new_issue)  # 수정
    # 블록 종료 시 원자적 저장 + 락 해제
"""

import fcntl
import json
import os
import tempfile
import time
from contextlib import contextmanager


class RegistryLockTimeout(Exception):
    """락 획득 실패. 조용히 덮어쓰느니 명시적으로 실패한다."""


@contextmanager
def registry_txn(path, timeout=10.0, poll=0.05):
    """registry.json을 락 걸고 읽어서 yield → 블록 종료 시 원자적 저장.

    블록 안에서 예외가 나면 저장하지 않는다(롤백).
    """
    lock_path = f"{path}.lock"
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)

    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o644)
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RegistryLockTimeout(
                        f"registry 락 획득 실패 ({timeout}s): {lock_path}. "
                        f"다른 훅이 쓰는 중일 수 있음."
                    )
                time.sleep(poll)

        with open(path, "r", encoding="utf-8") as f:
            registry = json.load(f)

        yield registry

        # 원자적 쓰기: 같은 디렉터리 tmp → os.replace (POSIX 원자성 보장)
        d = os.path.dirname(os.path.abspath(path))
        tmp_fd, tmp_path = tempfile.mkstemp(dir=d, prefix=".registry.", suffix=".tmp")
        try:
            with os.fdopen(tmp_fd, "w", encoding="utf-8") as tf:
                json.dump(registry, tf, indent=2, ensure_ascii=False)
                tf.flush()
                os.fsync(tf.fileno())
            os.replace(tmp_path, path)
        except Exception:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)
