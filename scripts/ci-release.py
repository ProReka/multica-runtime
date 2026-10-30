#!/usr/bin/env python3
"""Tag existing GHCR manifests, then publish a patch release. Never build images."""

import json
import os
import re
import subprocess

VARIANTS = ("base", "node", "python", "php", "go", "flutter", "devops", "qa", "design", "autoscaler")


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def release_tag(releases, sha):
    existing = [r["tagName"] for r in releases if r["targetCommitish"] == sha]
    if existing:
        return existing[0]
    versions = [tuple(map(int, match.groups())) for r in releases
                if (match := re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", r["tagName"]))]
    major, minor, patch = max(versions, default=(0, 0, 0))
    return f"v{major}.{minor}.{patch + 1}"


def tags(repo, variant, tag):
    if variant == "autoscaler":
        return [f"{repo}:{tag}"]
    result = [f"{repo}:{tag}-{variant}"]
    if variant == "base":
        result.append(f"{repo}:{tag}")
    return result


def main():
    sha = os.environ["GITHUB_SHA"]
    if run("gh", "api", "repos/{owner}/{repo}/git/ref/heads/main", "--jq", ".object.sha") != sha:
        print("Newer main commit exists; release deferred to its build")
        return
    releases = json.loads(run("gh", "api", "repos/{owner}/{repo}/releases?per_page=100",
                             "--jq", '[.[] | select(.draft == false) | {tagName: .tag_name, targetCommitish: .target_commitish}]'))
    git_tags = json.loads(run("gh", "api", "repos/{owner}/{repo}/tags?per_page=100"))
    known = releases + [{"tagName": t["name"], "targetCommitish": ""} for t in git_tags]
    tag = release_tag(known, sha)
    if any(r["tagName"] == tag for r in releases):
        print(f"Release {tag} already exists; leaving immutable tags untouched")
        return
    owner = os.environ["GITHUB_REPOSITORY_OWNER"].lower()
    # Snapshot every source digest before promotion. Unchanged variants reuse
    # their last successful image; release tags always represent a complete set.
    images = []
    for variant in VARIANTS:
        repo = f"ghcr.io/{owner}/multica-" + ("autoscaler" if variant == "autoscaler" else "runtime")
        source = f"{repo}:" + ("latest" if variant == "autoscaler" else variant)
        digest = run("docker", "buildx", "imagetools", "inspect", source, "--format", "{{.Manifest.Digest}}")
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise ValueError(f"Invalid image digest for {variant}")
        images.append((repo + "@" + digest, tags(repo, variant, tag)))
    # Reserve the release number before writing registry tags. A failed promotion
    # consumes a patch number rather than overwriting partially published tags.
    subprocess.run(["gh", "api", "repos/{owner}/{repo}/git/refs", "-f", f"ref=refs/tags/{tag}",
                    "-f", f"sha={sha}"], check=True)
    for source, targets in images:
        args = ["docker", "buildx", "imagetools", "create"]
        for target in targets:
            args.extend(["--tag", target])
        subprocess.run([*args, source], check=True)
    subprocess.run(["gh", "release", "create", tag, "--target", sha, "--title", tag,
                    "--generate-notes", "--notes",
                    "Versioned GHCR images reuse existing manifests; unchanged variants retain their last successful build. OCI version labels identify the original build commit."], check=True)
    print(f"Published {tag} without rebuilding images")


if __name__ == "__main__":
    main()
