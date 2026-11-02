#!/usr/bin/env bash
# No network, credentials, or OpenCode process required.
set -eu
cd "$(dirname "$0")/.."
source images/base/lib/opencode.sh
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
export HOME="$root" XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data"
export MULTICA_WORKSPACES_ROOT="$root" AI_PROTOCOL=openai
MR_BASE_URL=http://localhost:1
MR_API_KEY=""
MR_PROTOCOL=openai
MR_PROVIDER_ID=router
MR_MODEL=general
MR_SUBAGENT=coding
MR_LARGE=coding-high
MR_MEDIUM=coding
MR_SMALL=coding-low
log() { :; }
warn() { :; }
is_true() { [ "$1" = 1 ]; }
router_origin() { printf '%s' "$1"; }
mr_qualify_model() { printf 'router/%s' "$1"; }
mr_probe_models() { :; }
mr_configure_opencode
jq -e '.model == "router/general" and .agent.general.model == "router/coding"' \
 "$XDG_CONFIG_HOME/opencode/opencode.json" >/dev/null
jq -e '
 .provider.router.models | keys == ["coding", "coding-high", "coding-low", "general"]
' "$XDG_CONFIG_HOME/opencode/opencode.json" >/dev/null
export MULTICA_OPENCODE_MODEL=custom-main MULTICA_OPENCODE_SUBAGENT_MODEL=custom-sub
mr_configure_opencode
jq -e '.provider.router.models | has("custom-main") and has("custom-sub")' \
 "$XDG_CONFIG_HOME/opencode/opencode.json" >/dev/null
unset MULTICA_OPENCODE_MODEL MULTICA_OPENCODE_SUBAGENT_MODEL
MR_MODEL="" MR_SUBAGENT="" MR_LARGE="" MR_MEDIUM="" MR_SMALL=""
mr_configure_opencode
jq -e '(.provider.router.models // {}) == {}' \
 "$XDG_CONFIG_HOME/opencode/opencode.json" >/dev/null
MR_MODEL=general MR_SUBAGENT=coding MR_LARGE=coding-high MR_MEDIUM=coding MR_SMALL=coding-low
mr_probe_models() { printf '["general"]'; }
mr_configure_opencode
jq -e '.provider.router.models | keys == ["general"]' \
 "$XDG_CONFIG_HOME/opencode/opencode.json" >/dev/null
printf 'OpenCode catalogue checks passed.\n'
