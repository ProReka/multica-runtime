#!/usr/bin/env bash
# OpenCode configuration and session persistence.
#
# OpenCode does not read ANTHROPIC_BASE_URL, so the entrypoint writes a global
# config that points a custom provider at the same router as Claude Code. The
# provider speaks the OpenAI wire protocol when /v1/models answers (the common
# case for routers/aggregators), and the Anthropic protocol otherwise.
#
# This file is sourced; it must not execute anything on its own.

# shellcheck shell=bash

# Probe <origin>/v1/models and print a JSON array of model ids. Empty output
# means the probe failed; callers must treat that as "catalogue unknown".
mr_probe_models() {
    local origin url out="" attempt
    origin="$(router_origin "$MR_BASE_URL")"
    url="${AI_MODELS_URL:-${origin}/v1/models}"

    for attempt in 1 2 3; do
        out="$(MR_PROBE_URL="$url" MR_PROBE_KEY="$MR_API_KEY" MR_PROBE_AUTH="$MR_AUTH_MODE" python3 - <<'PY' 2>/dev/null || true
import json
import os
import urllib.request

url = os.environ.get("MR_PROBE_URL", "")
key = os.environ.get("MR_PROBE_KEY", "")
auth = os.environ.get("MR_PROBE_AUTH", "bearer")
try:
    headers = {"Accept": "application/json", "anthropic-version": "2023-06-01"}
    if auth == "api-key":
        headers["x-api-key"] = key
    else:
        headers["Authorization"] = "Bearer " + key
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=10) as response:
        payload = json.loads(response.read())
    if isinstance(payload, dict):
        items = payload.get("data") or payload.get("models") or []
    elif isinstance(payload, list):
        items = payload
    else:
        items = []
    ids = sorted({item["id"] for item in items
                  if isinstance(item, dict) and isinstance(item.get("id"), str) and item["id"]})
    if ids:
        print(json.dumps(ids))
except Exception:
    pass
PY
        )"
        [ -n "$out" ] && break
        [ "$attempt" -lt 3 ] && sleep 2
    done

    printf '%s' "$out"
}

mr_configure_opencode() {
    local root="${MULTICA_WORKSPACES_ROOT:-/workspaces}"
    local config_home config_dir config_file data_home
    local origin catalogue count protocol npm base_url probe_enabled
    local models_json="{}" main_model="" sub_model="" pin_sub="0"
    local main_ref="" sub_ref=""

    # --- Session data on the persistent volume --------------------------------
    if [ -z "${XDG_DATA_HOME:-}" ]; then
        data_home="${root}/.opencode/data"
        if mkdir -p "$data_home" 2>/dev/null; then
            export XDG_DATA_HOME="$data_home"
            log "OpenCode data dir → ${XDG_DATA_HOME}"
        else
            warn "cannot create ${data_home}; OpenCode sessions will not persist"
        fi
    else
        log "OpenCode data dir → ${XDG_DATA_HOME} (operator override)"
    fi

    # --- Config location -------------------------------------------------------
    config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
    config_dir="${config_home}/opencode"
    config_file="${OPENCODE_CONFIG:-${config_dir}/opencode.json}"
    mkdir -p "$(dirname "$config_file")" 2>/dev/null || {
        warn "cannot create $(dirname "$config_file"); OpenCode will use its defaults"
        return 0
    }

    # --- Router catalogue + protocol ------------------------------------------
    origin="$(router_origin "$MR_BASE_URL")"
    if is_true "${AI_MODELS_PROBE:-1}"; then
        probe_enabled=1
        catalogue="$(mr_probe_models)"
    else
        probe_enabled=0
        catalogue=""
        log "AI_MODELS_PROBE disabled — skipping ${origin}/v1/models"
    fi
    count="$(printf '%s' "$catalogue" | jq 'length' 2>/dev/null || printf '0')"
    [ -n "$count" ] || count=0

    case "$MR_PROTOCOL" in
        auto)
            # Anthropic's own /v1/models answers, but its wire protocol is not
            # OpenAI-compatible. Never auto-select openai for api.anthropic.com.
            case "$origin" in
                https://api.anthropic.com) protocol="anthropic" ;;
                *)
                    if [ "$count" -gt 0 ]; then protocol="openai"; else protocol="anthropic"; fi
                    ;;
            esac
            ;;
        openai)    protocol="openai" ;;
        anthropic) protocol="anthropic" ;;
    esac
    MR_EFFECTIVE_PROTOCOL="$protocol"
    export MR_EFFECTIVE_PROTOCOL

    if [ "$protocol" = "openai" ]; then
        npm="@ai-sdk/openai-compatible"
        base_url="${origin}/v1"
    else
        npm="@ai-sdk/anthropic"
        base_url="${MR_BASE_URL}"
    fi

    # --- Model catalogue -------------------------------------------------------
    if [ "$count" -gt 0 ]; then
        models_json="$(printf '%s' "$catalogue" | jq 'map({(.): {name: .}}) | add')"
        log "Router catalogue OK at ${origin}/v1/models (${count} models)"
    else
        if [ -n "${MR_MODEL:-}" ]; then
            models_json="$(jq -n --arg m "$MR_MODEL" '{($m): {name: $m}}')"
        fi
        if [ "$probe_enabled" = "0" ]; then
            log "catalogue unknown (AI_MODELS_PROBE=0); using protocol=${protocol}"
        elif [ "$MR_PROTOCOL" = "auto" ]; then
            log "Router catalogue probe failed at ${origin}/v1/models — using the Anthropic protocol with the configured default model"
        else
            warn "router catalogue probe failed at ${origin}/v1/models — continuing with AI_PROTOCOL=${MR_PROTOCOL}"
        fi
    fi

    # --- Models ----------------------------------------------------------------
    main_model="${MULTICA_OPENCODE_MODEL:-${MR_MODEL:-}}"
    sub_model="${MULTICA_OPENCODE_SUBAGENT_MODEL:-${MR_SUBAGENT:-$main_model}}"

    if [ -n "$main_model" ]; then
        main_ref="$(mr_qualify_model "$main_model")"
    fi
    if [ -n "$sub_model" ]; then
        sub_ref="$(mr_qualify_model "$sub_model")"
        # OpenCode refuses to start a session whose agent model is unknown.
        # Pin subagents only when the id is in the probed catalogue.
        if [ "$count" -eq 0 ] || printf '%s' "$models_json" | jq -e --arg m "$sub_model" 'has($m)' >/dev/null 2>&1; then
            pin_sub="1"
        else
            warn "subagent model '${sub_model}' is not in the router catalogue — subagents inherit '${main_model}'"
            sub_ref=""
        fi
    fi

    if [ "$count" -gt 0 ] && [ -n "$main_model" ] \
        && ! printf '%s' "$models_json" | jq -e --arg m "$main_model" 'has($m)' >/dev/null 2>&1; then
        warn "main model '${main_model}' is not in the router catalogue — tasks using it will fail"
    fi

    # --- Write config (0600: it contains the API key) -------------------------
    if ( umask 077; jq -n \
        --arg id "$MR_PROVIDER_ID" \
        --arg npm "$npm" \
        --arg base "$base_url" \
        --arg key "$MR_API_KEY" \
        --argjson models "$models_json" \
        --arg model "$main_ref" \
        --arg sub "$sub_ref" \
        --arg pin "$pin_sub" \
        '{"$schema": "https://opencode.ai/config.json", autoupdate: false}
         + {provider: {($id): (
              {npm: $npm, name: "Multica AI Router", options: {baseURL: $base, apiKey: $key}}
              + (if ($models | length) > 0 then {models: $models} else {} end)
            )}}
         + (if $model != "" then {model: $model} else {} end)
         + (if ($sub != "" and $pin == "1")
            then {agent: {general: {model: $sub}, explore: {model: $sub}}}
            else {} end)' > "$config_file"
    ); then
        chmod 600 "$config_file" 2>/dev/null || true
        log "OpenCode config → ${config_file} (protocol=${protocol}, provider=${MR_PROVIDER_ID}, models=${count}, main=${main_ref:-default}, subagent=${sub_ref:-inherit})"
    else
        warn "cannot write ${config_file}; falling back to the native environment variable"
        case "$MR_AUTH_MODE" in
            api-key) export ANTHROPIC_API_KEY="$MR_API_KEY" ;;
            *)       export ANTHROPIC_AUTH_TOKEN="$MR_API_KEY" ;;
        esac
    fi

    # --- Warn early when Claude's tiers are not served -----------------------
    if [ "$count" -gt 0 ] && [ -n "${MR_SUBAGENT:-}" ]; then
        local slot
        for slot in "$MR_MODEL" "$MR_LARGE" "$MR_MEDIUM" "$MR_SMALL" "$MR_SUBAGENT"; do
            [ -n "$slot" ] || continue
            printf '%s' "$models_json" | jq -e --arg m "$slot" 'has($m)' >/dev/null 2>&1 \
                || warn "model '${slot}' is not in the router catalogue — Claude Code turns/subagents using it will fail"
        done
    fi
}
