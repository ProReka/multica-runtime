#!/usr/bin/env python3
"""Select CI image builds from Git changes; emit a JSON build matrix."""

import argparse
import json
from pathlib import Path
import re
import subprocess


VARIANTS = ("node", "python", "php", "go", "flutter", "devops", "qa", "design", "autoscaler")
ALL = {"base", *VARIANTS}
SHARED = {
    "scripts/build.sh", "scripts/test-image.sh", "scripts/test-runtime.sh",
    ".github/workflows/build.yml", "scripts/ci-plan.py",
}
ROOT = Path(__file__).resolve().parent.parent


def plan(changed_paths, changed_version_keys, arg_mapping, variants="auto", full=False):
    """Return a plan; arg_mapping maps image names to their Dockerfile ARG names."""
    direct = None
    if variants == "all":
        selected = set(ALL)
    elif variants != "auto":
        selected = set(variants.split(","))
        if not selected <= ALL:
            raise ValueError("unknown or empty variant name")
    else:
        selected = set(ALL) if full else set()
        for path in changed_paths:
            if path in SHARED:
                selected.update(ALL)
            elif path.startswith("autoscaler/"):
                selected.add("autoscaler")
            elif path.startswith("images/"):
                variant = path.split("/")[1]
                if variant in ALL:
                    selected.add(variant)
        for key in changed_version_keys:
            affected = {name for name, args in arg_mapping.items() if key in args}
            selected.update(affected or ALL)
        direct = selected - {"base"}
        if "base" in selected:
            selected.update(ALL)
    return {
        "pr_variants": [name for name in VARIANTS if name in (direct if direct is not None else selected)],
        "base": "base" in selected,
        "matrix": {"include": [
            {"variant": name, "platforms": "linux/amd64" if name == "flutter"
             else "linux/amd64,linux/arm64"}
            for name in VARIANTS if name in selected
        ]},
        "publish": bool(selected),
    }


def git(*args):
    return subprocess.check_output(
        ["git", *args], cwd=ROOT, stderr=subprocess.DEVNULL
    ).decode("utf-8")


def versions(text):
    return dict(line.strip().split("=", 1) for line in text.splitlines()
                if line.strip() and not line.lstrip().startswith("#"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", required=True)
    parser.add_argument("--after", required=True)
    parser.add_argument("--variants", default="auto")
    args = parser.parse_args()
    try:
        # Validate explicit choices even when the comparison commit is missing.
        plan([], [], {}, args.variants)
        after = git("rev-parse", "--verify", "--end-of-options", args.after + "^{commit}").strip()
        try:
            before = git("rev-parse", "--verify", "--end-of-options", args.before + "^{commit}").strip()
        except subprocess.CalledProcessError:
            before = None
        if args.variants != "auto" or before is None:
            result = plan([], [], {}, args.variants, full=True)
        else:
            paths = git("diff", "--name-only", "--no-renames", "-z", before, after, "--").rstrip("\0").split("\0")
            changed_keys = set()
            mapping = {}
            if "versions.env" in paths:
                old = versions(git("show", before + ":versions.env"))
                new = versions(git("show", after + ":versions.env"))
                changed_keys = {key for key in old.keys() | new.keys() if old.get(key) != new.get(key)}
                for name in ALL:
                    path = "autoscaler/Dockerfile" if name == "autoscaler" else f"images/{name}/Dockerfile"
                    dockerfile = git("show", after + ":" + path)
                    mapping[name] = set(re.findall(r"^\s*ARG\s+([A-Za-z_][A-Za-z0-9_]*)", dockerfile, re.MULTILINE | re.IGNORECASE))
            result = plan(paths, changed_keys, mapping)
    except (subprocess.CalledProcessError, ValueError):
        parser.error("invalid variant selection or unreadable Git revision/build inputs")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
