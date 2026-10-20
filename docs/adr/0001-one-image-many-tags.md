# ADR 0001: one image repository, many variant tags

**Status:** accepted

## Context

Every stack (Node, PHP, Flutter, …) needs the same foundation: Debian, an agent
CLI, the Multica CLI, git, a non-root user, and the same entrypoint. Only the
toolchain differs.

The alternatives were:

1. one repository/package per stack;
2. one image with every tool installed;
3. one base image plus a variant tag per stack, all in one package.

Option 1 multiplies CI, documentation, and the number of places where a security
fix must land. Option 2 produces a huge image and forces every task to carry
PHP, Android SDK, and Terraform whether it needs them or not.

## Decision

Use **one package** (`ghcr.io/proreka/multica-runtime`) with a tag per variant:

```
:base  :node  :python  :php  :go  :flutter  :devops  :qa  :design
```

Each variant is `FROM base` and adds only its toolchain. All tags are built from
the same commit and share the base layers, so pulling a second variant downloads
only the difference.

The autoscaler is a separate package (`multica-autoscaler`) because it is not a
runtime: different entrypoint, different permissions, different lifecycle.

## Consequences

- One CI pipeline, one changelog, one place to bump a version.
- A base-layer fix reaches every variant on the next build.
- Registry storage is efficient: the shared base is stored once.
- Users must understand tags; `:php` is not a separate product.
- A breaking change in `base` affects every variant at once. CI builds them all on
  every PR, which is the point.
- A variant that needs a different base OS is not possible without forking the
  model. Nothing so far needs it.
