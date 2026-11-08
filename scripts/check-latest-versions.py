#!/usr/bin/env python3
"""Check upstream releases for tools pinned in versions.env."""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.request

SOURCES = {
    # GitHub releases
    "MULTICA_CLI_VERSION": ("github", "multica-ai/multica"),
    "GH_CLI_VERSION": ("github", "cli/cli"),
    "YQ_VERSION": ("github", "mikefarah/yq"),
    "HELM_VERSION": ("github", "helm/helm"),
    "TERRAFORM_VERSION": ("github", "hashicorp/terraform"),
    "KUBECTL_VERSION": ("github", "kubernetes/kubernetes"),
    "POETRY_VERSION": ("github", "python-poetry/poetry"),
    "RUFF_VERSION": ("github", "astral-sh/ruff"),
    "UV_VERSION": ("github", "astral-sh/uv"),

    # NPM packages
    "CLAUDE_CODE_VERSION": ("npm", "@anthropic-ai/claude-code"),
    "OPENCODE_VERSION": ("npm", "opencode-ai"),
    "CODEX_VERSION": ("npm", "@openai/codex"),
    "PNPM_VERSION": ("npm", "pnpm"),
    "YARN_VERSION": ("npm", "yarn"),
    "TYPESCRIPT_VERSION": ("npm", "typescript"),
    "PLAYWRIGHT_VERSION": ("npm", "playwright"),
    "PLAYWRIGHT_MCP_VERSION": ("npm", "@playwright/mcp"),
    "VITEST_VERSION": ("npm", "vitest"),
    "ESLINT_VERSION": ("npm", "eslint"),
    "PRETTIER_VERSION": ("npm", "prettier"),
    "SERVE_VERSION": ("npm", "serve"),
    "WRANGLER_VERSION": ("npm", "wrangler"),
    "NEWMAN_VERSION": ("npm", "newman"),

    # PyPI packages
    "MYPY_VERSION": ("pypi", "mypy"),
    "PYTEST_VERSION": ("pypi", "pytest"),
    "REQUESTS_VERSION": ("pypi", "requests"),
    "HTTPX_VERSION": ("pypi", "httpx"),
    "PILLOW_VERSION": ("pypi", "pillow"),
    "FONTTOOLS_VERSION": ("pypi", "fonttools"),
    "CAIROSVG_VERSION": ("pypi", "cairosvg"),
}


def fetch_latest_version(source_type: str, target: str, current_val: str) -> str:
    """Fetch latest release tag/version for a source."""
    headers = {"User-Agent": "multica-version-watcher"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token and source_type == "github":
        headers["Authorization"] = f"Bearer {token}"

    if source_type == "github":
        url = f"https://api.github.com/repos/{target}/releases/latest"
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            tag = data.get("tag_name", "").strip()
            if current_val.startswith("v"):
                return tag if tag.startswith("v") else f"v{tag}"
            return tag.lstrip("v")

    if source_type == "npm":
        url = f"https://registry.npmjs.org/{target}/latest"
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            return str(data.get("version", "")).strip()

    if source_type == "pypi":
        url = f"https://pypi.org/pypi/{target}/json"
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            return str(data.get("info", {}).get("version", "")).strip()

    raise ValueError(f"Unknown source type: {source_type}")


def parse_versions_env(content: str) -> dict[str, str]:
    versions = {}
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, val = line.split("=", 1)
            versions[key.strip()] = val.strip()
    return versions


def update_versions_content(content: str, updates: dict[str, str]) -> str:
    lines = []
    for line in content.splitlines():
        matched = False
        for key, new_val in updates.items():
            if re.match(rf"^{key}=.*", line):
                lines.append(f"{key}={new_val}")
                matched = True
                break
        if not matched:
            lines.append(line)
    return "\n".join(lines) + ("\n" if content.endswith("\n") else "")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", default="versions.env", help="Path to versions.env")
    parser.add_argument("--update", action="store_true", help="Update env-file with latest versions")
    parser.add_argument("--fail-on-outdated", action="store_true", help="Exit non-zero if updates available")
    args = parser.parse_args()

    env_path = Path(args.env_file)
    if not env_path.is_file():
        print(f"Error: {env_path} not found", file=sys.stderr)
        return 1

    content = env_path.read_text(encoding="utf-8")
    current_versions = parse_versions_env(content)

    updates = {}
    errors = 0

    print(f"Checking {len(SOURCES)} pinned tools...")
    for key, (src_type, target) in SOURCES.items():
        if key not in current_versions:
            continue
        curr = current_versions[key]
        try:
            latest = fetch_latest_version(src_type, target, curr)
            if latest and latest != curr:
                updates[key] = latest
                print(f"  UPDATE: {key}: {curr} -> {latest}")
            else:
                print(f"  ok:     {key} is up to date ({curr})")
        except Exception as exc:
            errors += 1
            print(f"  WARN:   {key} ({target}): {exc}", file=sys.stderr)

    if updates and args.update:
        new_content = update_versions_content(content, updates)
        env_path.write_text(new_content, encoding="utf-8")
        print(f"\nUpdated {len(updates)} versions in {env_path}")

    if updates and args.fail_on_outdated:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
