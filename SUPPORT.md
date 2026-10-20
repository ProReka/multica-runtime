# Support

This is a community project. There is no SLA.

## Where to ask

| Kind | Where |
|---|---|
| Bug | [Open an issue](https://github.com/ProReka/multica-runtime/issues/new/choose) |
| Feature request | [Open an issue](https://github.com/ProReka/multica-runtime/issues/new/choose) |
| Configuration help | [Discussions](https://github.com/ProReka/multica-runtime/discussions) or the issue template |
| Security | **Privately**, per [SECURITY.md](SECURITY.md) |

## What to include

- Image tag or digest (`ghcr.io/proreka/multica-runtime:php`).
- The startup banner lines. They contain no secrets.
- The command you ran and what you expected.
- Relevant logs, with tokens and keys redacted.
- Orchestrator (Compose, Swarm, ECS, Kubernetes, Dokploy) and version.

## Before you post

Run the dry run — it catches most configuration mistakes without contacting
Multica:

```bash
docker compose run --rm -e MULTICA_DRY_RUN=1 runtime
```

Then read [Troubleshooting](docs/operations/troubleshooting.md).

Please do not paste real `MULTICA_TOKEN`, `AI_API_KEY`, or `GH_TOKEN` values into
an issue. Redact them; a maintainer cannot un-publish them.
