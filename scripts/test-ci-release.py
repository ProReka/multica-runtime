#!/usr/bin/env python3
"""Docker-free release planning checks."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("ci_release", Path(__file__).with_name("ci-release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

releases = [{"tagName": "v0.3.0", "targetCommitish": "old"},
            {"tagName": "v0.4.0-rc1", "targetCommitish": "preview"}]
assert release.release_tag(releases, "new") == "v0.3.1"
assert release.release_tag(releases, "old") == "v0.3.0"
assert release.release_tag([], "first") == "v0.0.1"
assert release.tags("repo", "base", "v0.3.1") == ["repo:v0.3.1-base", "repo:v0.3.1"]
assert release.tags("repo", "qa", "v0.3.1") == ["repo:v0.3.1-qa"]
assert release.tags("repo", "autoscaler", "v0.3.1") == ["repo:v0.3.1"]
print("Release planning OK.")
