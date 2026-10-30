# Variants

All variants use the same package and share the base layers:

```
ghcr.io/proreka/multica-runtime:<variant>
```

| Tag | Toolchain | Use for | Architectures |
|---|---|---|---|
| `base` | Node 26 LTS, Python 3, git/gh, Chromium, build tools | general tasks, scripts, docs | amd64, arm64 |
| `node` | pnpm, yarn, TypeScript, Playwright, vitest, eslint, prettier | web frontends, Node services | amd64, arm64 |
| `python` | uv, Poetry, ruff, mypy, pytest | Python services, data work | amd64, arm64 |
| `php` | PHP 8.4, Composer, Laravel, MariaDB, PostgreSQL, Redis | Laravel/Symfony | amd64, arm64 |
| `go` | Go, golangci-lint | Go services, CLIs | amd64, arm64 |
| `flutter` | Flutter, Android SDK, JDK 21, Gradle | mobile and Flutter web | **amd64 only** |
| `devops` | Terraform, AWS CLI, kubectl, Helm, Docker CLI, Wrangler, yq, uv | infrastructure work | amd64, arm64 |
| `qa` | Playwright + MCP, axe-core, newman, k6, pytest | E2E, API, load, accessibility | amd64, arm64 |
| `design` | ImageMagick, librsvg, ghostscript, Playwright, Penpot MCP | UI assets, Penpot automation | amd64, arm64 |

Every variant includes Claude Code, OpenCode, the Multica CLI, git, gh, jq, and
the base OS packages.

## `base`

The default. Enough for a task that mostly reads, writes, reviews, and runs small
scripts. It includes Chromium so a quick screenshot or a docs build works without
extra packages.

Choose `base` unless a task fails for a missing toolchain.

## `node`

Adds the package managers and the frontend test stack. Playwright installs its own
Chromium under `/opt/playwright`, matching the `@playwright/test` version — more
reliable than driving the distro browser.

Includes `@playwright/mcp`, so an agent can use Playwright as an MCP server.

## `python`

Python 3.13 from Debian, plus uv and Poetry. Build headers (`libpq`, `libffi`,
`libxml2`, `libjpeg`, …) are preinstalled so a `pip install` that needs to compile
does not fail halfway through a task.

## `php`

PHP 8.4 with the extensions a Laravel application expects (`pdo_mysql`,
`pdo_pgsql`, `redis`, `intl`, `gd`, `bcmath`, …), Composer, and the Laravel
installer.

MariaDB, PostgreSQL and Redis run **inside the container** and start before the
daemon. This is the one variant where a database is part of the runtime:

- data lives in `/tmp/multica-db` and is recreated on every start;
- all three listen on `127.0.0.1` only;
- no `DB_*` variables are exported, so your app's `.env` stays in charge.

Point the application at `127.0.0.1` (or set `DB_HOST=127.0.0.1` in the repo's
`.env`).

Disable the databases with `MULTICA_START_DATABASES=0` if the task talks to an
external database.

## `go`

Go toolchain in `/usr/local/go`, with `GOPATH`, `GOCACHE` and `GOBIN` under the
runner home. `golangci-lint` is pinned and checksum-verified.

## `flutter`

Flutter stable plus the Android toolchain: JDK 21, Android SDK platform/build
tools, Gradle defaults tuned for containers. `flutter test`, `flutter build web`
and `flutter build apk` work.

**amd64 only.** Google's Android build tools are x86_64 binaries, and the arm64
image deliberately skips the Android SDK (Flutter web/Linux still work). On Apple
Silicon, run the amd64 image under emulation or build in CI.

Flutter is the largest image. Give it at least 4 vCPU / 8 GB and, on ECS, more
than the default 20 GB ephemeral storage.

## `devops`

Terraform, AWS CLI v2, kubectl, Helm, Docker CLI + compose plugin, Cloudflare
Wrangler, yq, and uv (for MCP servers written in Python).

Credentials are **not** baked in. Pass `AWS_*`, `CLOUDFLARE_API_TOKEN`, or a
mounted `~/.aws` at runtime. The container has no Docker daemon; the CLI is there
for compose linting and registry work, not for running nested containers.

## `qa`

Playwright with Chromium, `@playwright/mcp`, axe-core, newman for Postman
collections, k6 for load tests, and pytest for service-level tests.

The intended workflow: the agent writes a test, runs it, reads the trace or the
k6 summary, and fixes the code — not just the test.

## `design`

Image tooling (ImageMagick, librsvg, ghostscript, potrace, webp), Python image
libraries (Pillow, fontTools, cairoSVG), Playwright, and the **official Penpot MCP
server and plugin**, built into the image.

The entrypoint starts:

```
Xvfb :99 ──► Chromium (headed, agent-driven) ──► Penpot web app
                                                   │ plugin
agent ◄── http://127.0.0.1:4401/mcp ◄── MCP server ─┘ ws://127.0.0.1:4402
```

Penpot's MCP only works while a design file is open in a real browser with the
plugin connected, which is why this variant carries a virtual display and a
persistent browser profile at `/workspaces/.penpot-browser`.

Both CLIs get the MCP server registered automatically. Disable with
`MULTICA_PENPOT_MCP=0`.

## Building your own

A variant is a directory under `images/` with a `Dockerfile` that starts with:

```dockerfile
ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}
```

Then add it to `scripts/build.sh` (`context_for`) and to the CI matrix. Version
arguments must come from `versions.env` — no defaults in the Dockerfile. See
[Development](development.md).
