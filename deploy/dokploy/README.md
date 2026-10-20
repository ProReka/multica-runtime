# Dokploy

[Dokploy](https://dokploy.com) runs compose services on a single host and gives
you logs, restarts, and volume management without writing systemd units.

## Deploy

1. **Create Project** → **Create Service** → **Compose**.
2. Name it `multica-runtime`.
3. Paste [`docker-compose.yaml`](docker-compose.yaml).
4. Open **Environment** and add:

   ```dotenv
   MULTICA_TOKEN=...
   AI_BASE_URL=https://router.example.com
   AI_API_KEY=...
   AI_MODEL=general
   MULTICA_DAEMON_ID=multica-runtime
   ```

5. **Deploy**.

Do not add a domain or publish a port. The runtime is an outbound worker: it
connects to Multica and your AI router. A public port would expose nothing
useful and widen the attack surface.

## Logs

The startup banner is the first thing to read. It prints the resolved protocol,
model, session paths, and CLI versions — never the token or key.

```text
[multica] Multica Runtime dev (base)
[multica] Versions  claude=... | opencode=... | multica=... | node=... | python=...
[multica] AI        protocol=openai | provider=multica | model=general | tiers=...
[multica] Logging in to Multica…
[multica] Starting Multica daemon (foreground)…
```

## Choosing a variant

Change the image tag in the compose file:

```yaml
image: ghcr.io/proreka/multica-runtime:php
```

For the PHP image, the embedded MariaDB/PostgreSQL/Redis start automatically.
Data is ephemeral and lives under `/tmp/multica-db`.

## Updates

Use **Redeploy** after changing the image tag. Sessions survive because
`/workspaces` is a named volume. Pin a version tag (`:v0.2.0-base`) when you want
upgrades to be explicit.

## Autoscaler

Dokploy does not expose the Swarm API, so the autoscaler cannot scale Dokploy
services. Run one runtime continuously, or move to Swarm/ECS if scale-to-zero
matters.
