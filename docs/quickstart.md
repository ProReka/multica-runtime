# Quickstart

Five minutes from nothing to a runtime that appears in Multica.

## 1. Create a Multica token

Open <https://multica.ai/settings?tab=tokens> and create a personal access token.
Copy it once — the UI will not show it again.

## 2. Get the configuration

```bash
git clone https://github.com/ProReka/multica-runtime.git
cd multica-runtime
cp .env.example .env
```

Open `.env` and fill in four values:

```dotenv
MULTICA_TOKEN=mul_...
AI_BASE_URL=https://api.anthropic.com
AI_API_KEY=sk-ant-...
AI_MODEL=claude-sonnet-4-5
```

Using a router? See [Configuration → Routers](configuration.md#routers). If your
router is OpenAI-compatible, the image detects it automatically.

## 3. Start it

```bash
docker compose up -d
docker compose logs -f runtime
```

The first log lines tell you what was resolved:

```text
[multica] Multica Runtime v0.2.0 (base)
[multica] Versions  claude=2.1.304 | opencode=1.19.3 | multica=0.6.4 | ...
[multica] AI        protocol=anthropic | provider=multica | model=claude-sonnet-4-5
[multica] Paths     workspaces=/workspaces | claude=/workspaces/.claude | ...
[multica] Logging in to Multica…
[multica] Starting Multica daemon (foreground)…
```

## 4. Check the dashboard

Open Multica → **Runtimes**. You should see one runtime per bundled CLI
(Claude Code and OpenCode) registered under the name from
`MULTICA_AGENT_RUNTIME_NAME`.

Bind an agent to one of them and assign it a task. The container stays in the
foreground; work happens in `/workspaces/<task-id>`.

## 5. Pick the right image (optional)

The base image is enough for most tasks. If your repository needs a toolchain,
switch the tag:

```dotenv
MULTICA_IMAGE=ghcr.io/proreka/multica-runtime:php
```

```bash
docker compose up -d
```

The PHP image starts MariaDB, PostgreSQL and Redis inside the container before
the daemon. See [Variants](variants.md) for the full list.

## Common first-time questions

**Do I need to expose a port?**
No. The runtime is an outbound worker: it connects to Multica and your AI
endpoint. There is no inbound service.

**Where do sessions go?**
`/workspaces/.claude` and `/workspaces/.opencode/data`, on the
`multica-workspaces` volume. Restarting or upgrading the container keeps them.

**Can I run more than one runtime?**
Yes — use a different `MULTICA_DAEMON_ID` and container name per role. Do not run
two containers with the same daemon id; they will compete for tasks.

**Does it work on Apple Silicon?**
Yes. `linux/amd64` and `linux/arm64` images are published. Flutter is amd64-only
because the Android build tools are.

**How do I update?**
`docker compose pull && docker compose up -d`. Pin a version tag if you want
upgrades to be explicit.

## Next

- [Configuration](configuration.md)
- [Autoscaling](autoscaling.md)
- [Troubleshooting](operations/troubleshooting.md)
