# Security Policy

## Supported versions

Security fixes land on `main` and in the next tagged release. Pin a release tag or
digest in production; `:latest` receives fixes first but moves without notice.

| Version | Supported |
|---|---|
| latest release | ✅ |
| `main` builds | ✅ |
| older tags | best effort |

## Reporting a vulnerability

**Do not open a public issue.**

Use GitHub's private vulnerability reporting:

<https://github.com/ProReka/multica-runtime/security/advisories/new>

Include:

- affected image and tag/digest;
- what an attacker can do (read a secret, escape the container, …);
- reproduction steps, ideally a minimal `Dockerfile` or command;
- whether the issue is in this project or in an upstream component (Claude Code,
  OpenCode, Multica CLI, Debian package, …).

## What to expect

- Acknowledgement within 3 business days.
- An assessment and a remediation plan within 10 business days.
- Credit in the advisory unless you ask otherwise.

If the issue is in an upstream tool, we will still help coordinate, but the fix
may need to land upstream first. We can pin or disable a component in the image
while waiting.

## Scope

In scope:

- secrets leaking into an image layer, logs, or the repository;
- privilege escalation or container escape caused by this project's configuration;
- an image running as root, or requiring a capability it should not;
- supply-chain issues in the build (unpinned download, missing checksum);
- the autoscaler scaling the wrong service or bypassing its guards.

Out of scope:

- prompt injection through task content — the agent executes code by design;
- a compromised AI provider or Multica account;
- vulnerabilities in a task's own code;
- the Docker socket mount in the optional Swarm autoscaler (documented as
  root-equivalent; use the ECS adapter if that is not acceptable).

## Hardening checklist for operators

- Pin images by digest.
- Scope `MULTICA_TOKEN` and `GH_TOKEN` to what the agent needs.
- Restrict egress if your environment allows it.
- Do not mount host directories that contain unrelated credentials.
- Do not mount the Docker socket unless you run the Swarm autoscaler and trust
  every task on that host.
