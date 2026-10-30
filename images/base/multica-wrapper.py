#!/usr/bin/env python3
"""Retry orphaned task checkouts without deleting their files."""
import fcntl
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

REAL = "/usr/local/lib/multica-cli"
ERROR = "worktree path already exists and is not a valid git worktree: "


def recover(stderr, cwd, root):
    """Move only the reported direct-child orphan; never touch Git checkouts."""
    lines = [line for line in stderr.splitlines() if ERROR in line]
    if len(lines) != 1:
        return False
    target = Path(lines[0].split(ERROR, 1)[1])
    if not target.is_absolute() or target.parent != cwd or cwd == root or root not in cwd.parents:
        return False
    if target.is_symlink() or not target.is_dir() or os.path.lexists(target / ".git"):
        return False
    # Reject ancestors/symlink escapes, even if an error contains a crafted path.
    if target.resolve() != target or target.name in ("", ".", ".."):
        return False
    backup_root = root / ".checkout-recovery"
    backup_root.mkdir(mode=0o700, exist_ok=True)
    if backup_root.is_symlink():
        return False
    backup = Path(tempfile.mkdtemp(prefix=target.name + "-", dir=backup_root)) / target.name
    target.rename(backup)
    print(f"[multica] Preserved orphaned checkout at {backup}; retrying checkout", file=sys.stderr)
    return True


def main():
    args = sys.argv[1:]
    if args[:2] != ["repo", "checkout"]:
        os.execv(REAL, [REAL, *args])
    cwd = Path.cwd().resolve()
    root = Path(os.environ.get("MULTICA_WORKSPACES_ROOT", "/workspaces")).resolve()
    if root not in cwd.parents:
        os.execv(REAL, [REAL, *args])
    # Serialize checkout/recovery in this task directory across agent processes.
    locks = root / ".checkout-locks"
    locks.mkdir(mode=0o700, exist_ok=True)
    if locks.is_symlink():
        raise RuntimeError("checkout lock directory must not be a symlink")
    name = hashlib.sha256(str(cwd).encode()).hexdigest()
    fd = os.open(locks / name, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        result = subprocess.run([REAL, *args], stderr=subprocess.PIPE)
        error = result.stderr.decode(errors="replace")
        if result.returncode and ERROR in error:
            try:
                recovered = recover(error, cwd, root)
            except OSError as exc:
                print(f"[multica] Checkout recovery failed: {exc}", file=sys.stderr)
                recovered = False
            if recovered:
                for repo in (root / ".repos").glob("*/*.git"):
                    subprocess.run(["git", f"--git-dir={repo}", "worktree", "prune"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return subprocess.run([REAL, *args]).returncode
        sys.stderr.buffer.write(result.stderr)
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
