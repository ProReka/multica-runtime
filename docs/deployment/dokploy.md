# Dokploy

Dokploy is a self-hosted PaaS that runs compose services with logs, restarts, and
volume management.

1. **Create Project** → **Create Service** → **Compose**.
2. Paste [`deploy/dokploy/docker-compose.yaml`](https://github.com/ProReka/multica-runtime/blob/main/deploy/dokploy/docker-compose.yaml).
3. Fill the Environment tab:

   ```dotenv
   MULTICA_TOKEN=...
   AI_BASE_URL=https://router.example.com
   AI_API_KEY=...
   AI_MODEL=general
   MULTICA_DAEMON_ID=multica-runtime
   ```

4. **Deploy**.

Do **not** add a domain or publish a port. The runtime is outbound-only.

## Logs

The first lines are the startup banner: protocol, auth style, model, session
paths, CLI versions. No token, no key, no full router URL.

## Variants

Change the image tag in the compose file:

```yaml
image: ghcr.io/proreka/multica-runtime:php
```

The PHP image starts its embedded databases automatically.

## Updates

Change the tag and redeploy. `/workspaces` is a named volume, so sessions survive.
Pin a version tag if you want deliberate upgrades.

## Autoscaler

Dokploy does not expose the Swarm API, so the autoscaler cannot scale Dokploy
services. Run one runtime permanently, or move to Swarm/ECS.
