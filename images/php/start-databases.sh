#!/usr/bin/env bash
# Starts MariaDB, PostgreSQL and Redis inside the php runtime container.
#
# Runs as the unprivileged `runner` user. Data lives under /tmp so a restart
# always gives a clean database, and no root privileges are ever required.
set -Eeuo pipefail

log()  { printf '[multica-db] %s\n' "$*" >&2; }
warn() { printf '[multica-db] WARN: %s\n' "$*" >&2; }
die()  { printf '[multica-db] ERROR: %s\n' "$*" >&2; exit 1; }

ROOT="${MULTICA_DB_ROOT:-/tmp/multica-db}"
DB_NAME="${MULTICA_DB_NAME:-${DB_DATABASE:-laravel}}"
DB_USER="${MULTICA_DB_USER:-${DB_USERNAME:-laravel}}"
DB_PASS="${MULTICA_DB_PASSWORD:-${DB_PASSWORD:-secret}}"

DB_PASS_SQL="${DB_PASS//\'/\'\'}"
DB_NAME_SQL="${DB_NAME//\'/\'\'}"
DB_USER_SQL="${DB_USER//\'/\'\'}"
DB_USER_ID="${DB_USER//\"/\"\"}"
DB_NAME_ID="${DB_NAME//\"/\"\"}"

mkdir -p "$ROOT"
chmod 700 "$ROOT" 2>/dev/null || true

# --- MariaDB -----------------------------------------------------------------
start_mariadb() {
    local data="$ROOT/mysql" socket="$ROOT/mysql.sock" logfile="$ROOT/mysql.err"
    local port="${MULTICA_MYSQL_PORT:-3306}"

    mkdir -p "$data"
    if [ ! -d "$data/mysql" ]; then
        log "MariaDB: initialising data directory"
        mariadb-install-db \
            --datadir="$data" \
            --auth-root-authentication-method=normal \
            --skip-test-db >/dev/null 2>&1 \
            || die "mariadb-install-db failed"
    fi

    log "MariaDB: starting on 127.0.0.1:${port}"
    mariadbd \
        --datadir="$data" \
        --socket="$socket" \
        --pid-file="$ROOT/mysql.pid" \
        --port="$port" \
        --bind-address=127.0.0.1 \
        --skip-networking=0 \
        --skip-name-resolve \
        --log-error="$logfile" &
    local pid=$!

    for _ in $(seq 1 60); do
        mariadb-admin --protocol=socket --socket="$socket" ping >/dev/null 2>&1 && break
        kill -0 "$pid" 2>/dev/null || { tail -n 50 "$logfile" >&2 || true; die "MariaDB exited during startup"; }
        sleep 1
    done
    mariadb-admin --protocol=socket --socket="$socket" ping >/dev/null 2>&1 \
        || { tail -n 50 "$logfile" >&2 || true; die "MariaDB did not become ready"; }

    mariadb --protocol=socket --socket="$socket" -u root <<SQL \
        || die "MariaDB user/database setup failed"
CREATE DATABASE IF NOT EXISTS \`${DB_NAME_SQL}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER_SQL}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS_SQL}';
CREATE USER IF NOT EXISTS '${DB_USER_SQL}'@'localhost' IDENTIFIED BY '${DB_PASS_SQL}';
GRANT ALL PRIVILEGES ON \`${DB_NAME_SQL}\`.* TO '${DB_USER_SQL}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME_SQL}\`.* TO '${DB_USER_SQL}'@'localhost';
FLUSH PRIVILEGES;
SQL
    log "MariaDB: ready (db=${DB_NAME}, user=${DB_USER}, port=${port})"
}

# --- PostgreSQL --------------------------------------------------------------
start_postgres() {
    local data="$ROOT/postgres" logfile="$ROOT/postgres.log"
    local port="${MULTICA_POSTGRES_PORT:-5432}" pg_bin
    pg_bin="$(find /usr/lib/postgresql -maxdepth 3 -type d -name bin 2>/dev/null | sort | head -n1 || true)"
    [ -n "$pg_bin" ] || { warn "PostgreSQL binaries not found — skipping"; return 0; }

    mkdir -p "$data"
    if [ ! -s "$data/PG_VERSION" ]; then
        log "PostgreSQL: initialising data directory"
        "$pg_bin/initdb" -D "$data" -U postgres --auth-local=trust --auth-host=trust \
            --encoding=UTF8 --locale=C >/dev/null 2>&1 \
            || die "initdb failed"
        {
            printf "\nlisten_addresses = '127.0.0.1'\n"
            printf "port = %s\n" "$port"
            printf "unix_socket_directories = '%s'\n" "$ROOT"
        } >> "$data/postgresql.conf"
        printf "host all all 127.0.0.1/32 trust\n" >> "$data/pg_hba.conf"
    fi

    log "PostgreSQL: starting on 127.0.0.1:${port}"
    "$pg_bin/pg_ctl" -D "$data" -w -l "$logfile" start >/dev/null 2>&1 \
        || { tail -n 50 "$logfile" >&2 || true; die "PostgreSQL failed to start"; }

    "$pg_bin/psql" -h 127.0.0.1 -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 >/dev/null <<SQL \
        || die "PostgreSQL user/database setup failed"
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER_SQL}') THEN
    CREATE ROLE "${DB_USER_ID}" LOGIN PASSWORD '${DB_PASS_SQL}';
  END IF;
END \$\$;
SELECT 'CREATE DATABASE "${DB_NAME_ID}" OWNER "${DB_USER_ID}"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME_SQL}')\gexec
SQL
    log "PostgreSQL: ready (db=${DB_NAME}, user=${DB_USER}, port=${port})"
}

# --- Redis -------------------------------------------------------------------
start_redis() {
    local dir="$ROOT/redis" logfile="$ROOT/redis.log"
    local port="${MULTICA_REDIS_PORT:-6379}"
    mkdir -p "$dir"

    log "Redis: starting on 127.0.0.1:${port}"
    redis-server \
        --bind 127.0.0.1 \
        --port "$port" \
        --dir "$dir" \
        --daemonize yes \
        --save "" \
        --appendonly no \
        --logfile "$logfile" \
        || { tail -n 50 "$logfile" >&2 || true; die "Redis failed to start"; }

    for _ in $(seq 1 30); do
        redis-cli -h 127.0.0.1 -p "$port" ping >/dev/null 2>&1 && break
        sleep 1
    done
    redis-cli -h 127.0.0.1 -p "$port" ping >/dev/null 2>&1 \
        || { tail -n 50 "$logfile" >&2 || true; die "Redis did not become ready"; }
    log "Redis: ready (port=${port})"
}

start_mariadb
start_postgres
start_redis
log "All embedded databases are ready."
