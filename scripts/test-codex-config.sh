#!/usr/bin/env bash
# No network, credentials, or real Codex binary required.
set -eu
cd "$(dirname "$0")/.."
source images/base/lib/common.sh
source images/base/lib/codex.sh
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin"
printf '#!/bin/sh\n' > "$root/bin/codex"
chmod +x "$root/bin/codex"
export PATH="$root/bin:$PATH" HOME="$root" MULTICA_WORKSPACES_ROOT="$root"
log() { :; }
MR_BASE_URL=http://localhost:18080/v1 MR_API_KEY=k MR_PROVIDER_ID=multica MR_MODEL='m"x'
cfg="$root/.codex/config.toml"

mr_configure_codex
grep -qx 'model = "m\\"x"' "$cfg"
grep -qx 'model_provider = "multica"' "$cfg"
grep -qx 'base_url = "http://localhost:18080/v1"' "$cfg"
grep -qx 'env_key = "CODEX_API_KEY"' "$cfg"
grep -qx 'wire_api = "responses"' "$cfg"
if grep -q 'k' <<<"$(grep -v '^\[\|=' "$cfg")"; then exit 1; fi
[ "$CODEX_API_KEY" = k ] && [ "$CODEX_HOME" = "$root/.codex" ]
[ "$(stat -c %a "$cfg")" = 600 ]

CODEX_MODEL=o CODEX_BASE_URL=http://other/v1/ CODEX_API_KEY=other mr_configure_codex
grep -qx 'model = "o"' "$cfg"
grep -qx 'base_url = "http://other/v1"' "$cfg"

unset CODEX_API_KEY CODEX_HOME
MR_MODEL=""
mr_configure_codex
if grep -q '^model = ' "$cfg"; then exit 1; fi

printf 'Codex config checks passed.\n'
