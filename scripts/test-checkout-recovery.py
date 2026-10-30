#!/usr/bin/env python3
"""Docker-free checks for checkout recovery boundaries and data preservation."""
import importlib.util
import os
from pathlib import Path
import tempfile

spec = importlib.util.spec_from_file_location("wrapper", Path(__file__).resolve().parents[1] / "images/base/multica-wrapper.py")
wrapper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wrapper)

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp).resolve()
    cwd = root / "workspace/task/workdir"
    cwd.mkdir(parents=True)
    target = cwd / "repo"
    target.mkdir()
    (target / "changes.txt").write_text("uncommitted work")
    error = "checkout failed: create worktree: " + wrapper.ERROR + str(target)
    assert wrapper.recover(error, cwd, root)
    assert not target.exists()
    backups = list((root / ".checkout-recovery").glob("repo-*/repo/changes.txt"))
    assert len(backups) == 1 and backups[0].read_text() == "uncommitted work"
    assert not wrapper.recover(error, cwd, root)
    for kind in ("file", "directory", "broken-link"):
        target.mkdir(exist_ok=True)
        dotgit = target / ".git"
        if kind == "file":
            dotgit.write_text("gitdir: missing")
        elif kind == "directory":
            dotgit.mkdir()
        else:
            dotgit.symlink_to(root / "missing")
        assert not wrapper.recover(error, cwd, root)
        if dotgit.is_dir():
            dotgit.rmdir()
        else:
            dotgit.unlink()
    target.rmdir()
    target.symlink_to(root, target_is_directory=True)
    assert not wrapper.recover(error, cwd, root)
    target.unlink()
    outside = root / "unrelated"
    outside.mkdir()
    assert not wrapper.recover(wrapper.ERROR + str(outside), cwd, root)
    assert not wrapper.recover("different error", cwd, root)
    # Exercise the actual CLI wrapper: fail once, recover, retry successfully.
    fake = root / "multica-real"
    fake.write_text("#!/bin/sh\nif [ -d repo ]; then\n  echo \"checkout failed: worktree path already exists and is not a valid git worktree: $PWD/repo\" >&2\n  exit 1\nfi\nmkdir repo\n")
    fake.chmod(0o700)
    target.mkdir()
    (target / "keep.txt").write_text("preserved")
    import sys
    old_cwd, old_argv = Path.cwd(), sys.argv
    old_root = os.environ.get("MULTICA_WORKSPACES_ROOT")
    try:
        os.chdir(cwd)
        os.environ["MULTICA_WORKSPACES_ROOT"] = str(root)
        sys.argv = ["multica", "repo", "checkout", "https://example.invalid/repo.git"]
        wrapper.REAL = str(fake)
        assert wrapper.main() == 0
        assert target.is_dir() and not (target / "keep.txt").exists()
        assert any(p.read_text() == "preserved" for p in (root / ".checkout-recovery").glob("*/repo/keep.txt"))
    finally:
        os.chdir(old_cwd)
        sys.argv = old_argv
        if old_root is None:
            os.environ.pop("MULTICA_WORKSPACES_ROOT", None)
        else:
            os.environ["MULTICA_WORKSPACES_ROOT"] = old_root
    (root / ".checkout-recovery").rename(root / "saved")
    (root / ".checkout-recovery").symlink_to(root / "saved", target_is_directory=True)
    assert not wrapper.recover(error, cwd, root)
print("Checkout recovery OK.")
