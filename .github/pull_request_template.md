<!--
Thanks for contributing. Keep the description short and specific.
-->

## What changed

<!-- One or two sentences. -->

## Why

<!-- The problem this solves. Link the issue if there is one. -->

## How it was verified

<!--
Paste the relevant CI job, command, or log lines. "Works on my machine" is not
reviewable, and no image is small enough to build on every reviewer's laptop.
-->

- [ ] `make lint` passes
- [ ] CI is green (or a maintainer explicitly agreed to run it after merge)

## Checklist

- [ ] One concern per PR
- [ ] No secret, token, or key in any file, commit, log, or screenshot
- [ ] New tool versions live in `versions.env`; Dockerfile ARGs have no defaults
- [ ] New runtime code runs as uid 1000 (no root, no setpriv/gosu)
- [ ] No new privileged requirement, inbound port, or Docker socket
- [ ] Docs updated if behaviour changed
- [ ] `CHANGELOG.md` updated for user-visible changes
