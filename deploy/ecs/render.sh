#!/usr/bin/env bash
# Render an ECS task definition template by replacing __PLACEHOLDER__ strings.
#
#   AWS_ACCOUNT_ID=123456789012 \
#   AWS_REGION=ap-southeast-1 \
#   IMAGE=ghcr.io/proreka/multica-runtime:base \
#   DAEMON_ID=multica-base \
#   RUNTIME_NAME="Multica Runtime" \
#   EFS_ID=fs-0123456789abcdef0 \
#   EFS_ACCESS_POINT_ID=fsap-0123456789abcdef0 \
#     deploy/ecs/render.sh deploy/ecs/runtime-task-definition.json /tmp/runtime.json
#
# The autoscaler template additionally needs ECS_CLUSTER, AUTOSCALER_IMAGE and
# AUTOSCALER_RUNTIMES.
set -Eeuo pipefail

template="${1:?usage: render.sh <template.json> <output.json>}"
output="${2:?usage: render.sh <template.json> <output.json>}"

require() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        printf 'ERROR: %s is required\n' "$name" >&2
        exit 2
    fi
}

require AWS_ACCOUNT_ID
require AWS_REGION

jq \
    --arg account "$AWS_ACCOUNT_ID" \
    --arg region "$AWS_REGION" \
    --arg image "${IMAGE:-}" \
    --arg autoscaler_image "${AUTOSCALER_IMAGE:-}" \
    --arg daemon "${DAEMON_ID:-multica-runtime}" \
    --arg runtime_name "${RUNTIME_NAME:-Multica Runtime}" \
    --arg efs "${EFS_ID:-}" \
    --arg efs_ap "${EFS_ACCESS_POINT_ID:-}" \
    --arg cluster "${ECS_CLUSTER:-}" \
    --arg runtimes "${AUTOSCALER_RUNTIMES:-}" \
    'walk(
        if type == "string" then
            gsub("__ACCOUNT_ID__"; $account)
            | gsub("__REGION__"; $region)
            | gsub("__IMAGE__"; $image)
            | gsub("__AUTOSCALER_IMAGE__"; $autoscaler_image)
            | gsub("__DAEMON_ID__"; $daemon)
            | gsub("__RUNTIME_NAME__"; $runtime_name)
            | gsub("__EFS_ID__"; $efs)
            | gsub("__EFS_ACCESS_POINT_ID__"; $efs_ap)
            | gsub("__ECS_CLUSTER__"; $cluster)
            | gsub("__AUTOSCALER_RUNTIMES__"; $runtimes)
        else . end
    )' "$template" > "$output"

printf 'Rendered %s → %s\n' "$template" "$output"
