#!/usr/bin/env bash
# php variant entrypoint: start embedded databases, then hand off to the base
# entrypoint (login + daemon). Runs as `runner`; no privilege drop needed.
set -Eeuo pipefail

log() { printf '[multica-php] %s\n' "$*" >&2; }

export HOME="${HOME:-/home/runner}"

case "$(printf '%s' "${MULTICA_START_DATABASES:-1}" | tr '[:upper:]' '[:lower:]')" in
    0|false|no|off)
        log "MULTICA_START_DATABASES=${MULTICA_START_DATABASES} → skipping embedded databases"
        ;;
    *)
        /usr/local/bin/multica-start-databases
        ;;
esac

exec /usr/local/bin/multica-entrypoint
