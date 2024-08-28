#! /usr/bin/env bash

# Common functions and variables used by initiate.sh and complete.sh

REPORTING_PROJECT_REF="ihmaxnjpcccasmrbkpvo"
REPORTING_CREDENTIALS_FILE="/root/upgrade-reporting-credentials"

REPORTING_ANON_KEY=""
if [ -f "$REPORTING_CREDENTIALS_FILE" ]; then
    REPORTING_ANON_KEY=$(cat "$REPORTING_CREDENTIALS_FILE")
fi

# shellcheck disable=SC2120
# Arguments are passed in other files
function run_sql {
    psql -h localhost -U supabase_admin -d postgres "$@"
}

function ship_logs {
    LOG_FILE=$1

    if [ -z "$REPORTING_ANON_KEY" ]; then
        echo "No reporting key found. Skipping log upload."
        return 0
    fi

    if [ ! -f "$LOG_FILE" ]; then
        echo "No log file found. Skipping log upload."
        return 0
    fi

    if [ ! -s "$LOG_FILE" ]; then
        echo "Log file is empty. Skipping log upload."
        return 0
    fi

    HOSTNAME=$(hostname)
    DERIVED_REF="${HOSTNAME##*-}"

    printf -v BODY '{ "ref": "%s", "step": "%s", "content": %s }' "$DERIVED_REF" "completion" "$(cat "$LOG_FILE" | jq -Rs '.')"
    curl -sf -X POST "https://$REPORTING_PROJECT_REF.supabase.co/rest/v1/error_logs" \
        -H "apikey: ${REPORTING_ANON_KEY}" \
        -H 'Content-type: application/json' \
        -d "$BODY"
}

function retry {
    local retries=$1
    shift

    local count=0
    until "$@"; do
        exit=$?
        wait=$((2 ** (count + 1)))
        count=$((count + 1))
        if [ $count -lt "$retries" ]; then
            echo "Command $* exited with code $exit, retrying..."
            sleep $wait
        else
            echo "Command $* exited with code $exit, no more retries left."
            return $exit
        fi
    done
    return 0
}

CI_stop_postgres() {
    BINDIR=$(pg_config --bindir)
    ARG=${1:-""}

    if [ "$ARG" = "--new-bin" ]; then
        BINDIR="/tmp/pg_upgrade_bin/$PG_MAJOR_VERSION/bin"
    fi

    su postgres -c "$BINDIR/pg_ctl stop -o '-c config_file=/etc/postgresql/postgresql.conf' -l /tmp/postgres.log"
}

CI_start_postgres() {
    BINDIR=$(pg_config --bindir)
    ARG=${1:-""}

    if [ "$ARG" = "--new-bin" ]; then
        BINDIR="/tmp/pg_upgrade_bin/$PG_MAJOR_VERSION/bin"
    fi

    su postgres -c "$BINDIR/pg_ctl start -o '-c config_file=/etc/postgresql/postgresql.conf' -l /tmp/postgres.log"
}

swap_postgres_and_supabase_admin() {
    SCRIPT_DIR=$(dirname -- "$0")

    if [ -f "$SCRIPT_DIR/migrate_bootstrap_user.sql" ]; then
        run_sql -f "$SCRIPT_DIR/migrate_bootstrap_user.sql"
    else
        echo "Bootstrap user migration script not found. Skipping."
    fi

}
