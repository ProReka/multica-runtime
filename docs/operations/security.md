# Security

## What the container trusts

| Input | Trust level | Why |
|---|---|---|
| `MULTICA_TOKEN` | Secret | Full access to the workspaces the token can reach |
| `AI_API_KEY` | Secret | Billable access to the model endpoint |
| `GH_TOKEN` | Secret | Repository access, often write |
| Task instructions | **Untrusted content** | A prompt injection can ask the agent to exfiltrate anything the container can read |

The agent runs arbitrary code by design. Treat the container as a sandbox for
convenience, **not** as a security boundary against a malicious task. The token
you give it is the blast radius.

Practical consequences:

- Use a Multica token scoped to the workspaces the runtime needs.
- Use a GitHub token scoped to the repositories the agent is allowed to touch.
- Do not mount a host directory that contains unrelated credentials.
- Do not run the autoscaler's Docker socket mount on a host where tasks are
  untrusted; the socket is root-equivalent.

## Secrets handling

- No secret is baked into an image layer. Everything arrives as an environment
  variable or an orchestrator secret at runtime.
- The OpenCode config contains the API key and is written at start with mode
  `0600` under the runner's home.
- The banner never prints a token, key, or full router URL (only scheme + host).
- `.env` is git-ignored; `.env.example` contains empty placeholders.
- ECS task definitions reference Secrets Manager ARNs, not values.

If a key leaks: rotate it at the provider, then restart the runtime. The old key
is not recoverable from the image, but it may be in logs if you printed it
yourself.

## Non-root

Everything runs as `runner` (uid/gid 1000):

- the Multica daemon, both agent CLIs, and every task;
- Xvfb and the Penpot MCP server in the design image;
- MariaDB, PostgreSQL and Redis in the PHP image.

There is no `sudo`, no setuid helper, and no runtime privilege drop. This keeps
the image compatible with Fargate's seccomp profile and with Kubernetes
`runAsNonRoot`.

## Network

- **No inbound port.** The runtime connects out; it does not listen for tasks.
- Egress should be restricted to what the runtime needs: Multica, the AI router,
  your Git host, and the package registries your tasks use. A coding agent needs
  broad egress in practice; an allowlist is a policy decision, not a default.
- The design image binds MCP and plugin servers to `127.0.0.1` by default. Change
  the host variables only if you deliberately want them reachable.

## Supply chain

- Base OS, Node, and every tool are pinned in
  [`versions.env`](https://github.com/ProReka/multica-runtime/blob/main/versions.env).
- Downloads are checksum-verified where upstream publishes a checksum.
- Images are built in GitHub Actions, not on a laptop, and published to GHCR with
  provenance and SBOM attestations.
- Dependencies are updated by Dependabot PRs; a human reviews the diff and the
  resulting image.

For high-assurance deployments:

```bash
docker pull ghcr.io/proreka/multica-runtime@sha256:<digest>
```

Pin the digest, not the tag. Tags are mutable; digests are not.

## What is deliberately not done

- **No auto-update of agent CLIs.** An in-place update would change behaviour
  mid-task and bypass review.
- **No Docker socket** except the Swarm autoscaler. The ECS adapter uses IAM.
- **No privileged mode, no host PID/network, no `--cap-add`.**
- **No secrets in build args.** Build args are visible in image history.

## Reporting a vulnerability

Please do not open a public issue for a security problem. See
[SECURITY.md](https://github.com/ProReka/multica-runtime/blob/main/SECURITY.md)
for the private reporting channel and response expectations.
