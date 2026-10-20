# ADR 0003: run everything as a non-root user

**Status:** accepted

## Context

Agent containers are often built as root and then “dropped” to a normal user with
`gosu` or `setpriv` at startup. Both need mechanisms that some runtimes block:

- Fargate's default seccomp profile blocks `ptrace`-based helpers;
- Kubernetes clusters with `runAsNonRoot: true` refuse the image outright;
- a root-owned `/workspaces` volume creates a class of permission bugs that only
  appear in production.

The hard cases were not the agent CLIs. They were:

- **PHP**: MariaDB, PostgreSQL and Redis traditionally want to run as their own
  system users, with data in `/var/lib`.
- **Design**: Xvfb and a headed Chromium traditionally run as root, with a
  privilege drop for the browser.

## Decision

The image declares `USER runner` (uid/gid 1000) and **never regains root at
runtime**.

- **PHP databases** run as `runner`, with data under `/tmp/multica-db`
  (`MULTICA_DB_ROOT`). They listen on `127.0.0.1` only. `initdb` and
  `mariadb-install-db` work fine as a normal user when the data directory is
  writable.
- **Design** runs Xvfb and the Penpot MCP/plugin servers as `runner`. No `gosu`,
  no `setpriv` privilege drop, no setuid helpers.
- **No variant** needs root at runtime. Installation happens at build time as
  root; the final stage switches back.

## Consequences

- Works on Fargate's default seccomp profile and with Kubernetes
  `runAsNonRoot: true`.
- No setuid binaries, no `sudo`, no capability needed.
- A bind-mounted `/workspaces` must be writable by uid 1000. Named volumes inherit
  the image's ownership; bind mounts need a `chown`. This is documented and
  detected at startup (a warning, not a crash).
- The PHP databases cannot bind privileged ports or write to `/var/lib`. Ports are
  configurable (`MULTICA_*_PORT`) and data is ephemeral by design.
- Xvfb writes its socket to `/tmp/.X11-unix`, which is world-writable in the image.
- A task that genuinely needs root cannot get it inside this container. That is
  the intended trade-off: use a purpose-built image if you need system-level work.
