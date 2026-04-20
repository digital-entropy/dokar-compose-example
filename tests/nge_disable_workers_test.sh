#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected to find `%s` in:\n%s\n' "$needle" "$haystack" >&2
        exit 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'Did not expect to find `%s` in:\n%s\n' "$needle" "$haystack" >&2
        exit 1
    fi
}

make_fake_docker() {
    local bin_dir="$1"
    local log_file="$2"

    mkdir -p "$bin_dir"

    cat > "$bin_dir/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$log_file"
EOF

    chmod +x "$bin_dir/docker"
}

make_workspace() {
    local workspace="$1"
    local enable_horizon="$2"
    local enable_scheduler="$3"

    mkdir -p "$workspace/config/gateway"

    cat > "$workspace/.env" <<EOF
DOCKER_IMAGE=registry.example.com/app/app
DOCKER_TAG=experiment
DOCKER_PORT=8082
DOCKER_VOLUMES_DRIVER=local
DOCKER_NETWORKS_DRIVER=bridge
DOCKER_HOSTNAME=app-from-unknown-server
DOCKER_USER=appuser
ENABLE_WEB=true
ENABLE_HORIZON=$enable_horizon
ENABLE_SCHEDULER=$enable_scheduler
EOF

    cat > "$workspace/config/gateway/upstream.conf" <<'EOF'
upstream core {
    server core-blue:80;
    keepalive 64;
}
EOF
}

run_nge() {
    local workspace="$1"
    local log_file="$2"
    shift 2

    (
        cd "$workspace"
        PATH="$workspace/bin:$PATH" bash "$REPO_ROOT/nge" "$@" >/dev/null
    )
    cat "$log_file"
}

test_start_stops_disabled_workers() {
    local workspace
    workspace="$(mktemp -d)"
    local log_file="$workspace/docker.log"

    make_workspace "$workspace" false false
    make_fake_docker "$workspace/bin" "$log_file"

    local output
    output="$(run_nge "$workspace" "$log_file" start)"

    assert_contains "$output" 'compose up -d gateway core-blue'
    assert_not_contains "$output" 'compose up -d gateway core-blue horizon'
    assert_not_contains "$output" 'compose up -d gateway core-blue scheduler'
    assert_contains "$output" 'compose rm --stop --force horizon scheduler'
    assert_contains "$output" 'compose stop core-green'

    rm -rf "$workspace"
}

test_start_keeps_enabled_worker_targetable() {
    local workspace
    workspace="$(mktemp -d)"
    local log_file="$workspace/docker.log"

    make_workspace "$workspace" true false
    make_fake_docker "$workspace/bin" "$log_file"

    local output
    output="$(run_nge "$workspace" "$log_file" start)"

    assert_contains "$output" 'compose up -d gateway core-blue horizon'
    assert_not_contains "$output" 'compose up -d gateway core-blue horizon scheduler'
    assert_contains "$output" 'compose rm --stop --force scheduler'

    rm -rf "$workspace"
}

test_image_upgrade_reconciles_disabled_workers() {
    local workspace
    workspace="$(mktemp -d)"
    local log_file="$workspace/docker.log"

    make_workspace "$workspace" false false
    make_fake_docker "$workspace/bin" "$log_file"

    local output
    output="$(run_nge "$workspace" "$log_file" image:upgrade)"

    assert_contains "$output" 'compose up -d --force-recreate --remove-orphans'
    assert_contains "$output" 'compose rm --stop --force horizon scheduler'

    rm -rf "$workspace"
}

test_image_upgrade_recreates_only_enabled_worker() {
    local workspace
    workspace="$(mktemp -d)"
    local log_file="$workspace/docker.log"

    make_workspace "$workspace" false true
    make_fake_docker "$workspace/bin" "$log_file"

    local output
    output="$(run_nge "$workspace" "$log_file" image:upgrade)"

    assert_contains "$output" 'compose up -d --force-recreate --remove-orphans'
    assert_contains "$output" 'compose up -d --force-recreate scheduler'
    assert_not_contains "$output" 'compose up -d --force-recreate horizon scheduler'
    assert_contains "$output" 'compose rm --stop --force horizon'

    rm -rf "$workspace"
}

test_image_upgrade_recreates_enabled_workers() {
    local workspace
    workspace="$(mktemp -d)"
    local log_file="$workspace/docker.log"

    make_workspace "$workspace" true true
    make_fake_docker "$workspace/bin" "$log_file"

    local output
    output="$(run_nge "$workspace" "$log_file" image:upgrade)"

    assert_contains "$output" 'compose up -d --force-recreate --remove-orphans'
    assert_contains "$output" 'compose up -d --force-recreate horizon scheduler'
    assert_not_contains "$output" 'compose rm --stop --force horizon scheduler'

    rm -rf "$workspace"
}

test_update_downtime_reconciles_disabled_workers() {
    local workspace
    workspace="$(mktemp -d)"
    local log_file="$workspace/docker.log"

    make_workspace "$workspace" false false
    make_fake_docker "$workspace/bin" "$log_file"

    local output
    output="$(run_nge "$workspace" "$log_file" update:downtime)"

    assert_contains "$output" 'compose pull core-blue artisan'
    assert_contains "$output" 'compose up -d --force-recreate core-blue'
    assert_not_contains "$output" 'compose pull horizon'
    assert_not_contains "$output" 'compose pull scheduler'
    assert_contains "$output" 'compose rm --stop --force horizon scheduler'
    assert_contains "$output" 'compose restart gateway'

    rm -rf "$workspace"
}

test_update_zero_downtime_recreates_only_enabled_worker() {
    local workspace
    workspace="$(mktemp -d)"
    local log_file="$workspace/docker.log"

    make_workspace "$workspace" true false
    make_fake_docker "$workspace/bin" "$log_file"

    local output
    output="$(run_nge "$workspace" "$log_file" update:zero_downtime)"

    assert_contains "$output" 'compose pull core-green artisan'
    assert_contains "$output" 'compose up -d core-green'
    assert_contains "$output" 'compose exec -T gateway nginx -s reload'
    assert_contains "$output" 'compose pull horizon'
    assert_contains "$output" 'compose up -d horizon'
    assert_not_contains "$output" 'compose up -d horizon scheduler'
    assert_contains "$output" 'compose rm --stop --force scheduler'
    assert_contains "$output" 'compose stop core-blue'

    rm -rf "$workspace"
}

test_code_reload_reconciles_disabled_workers() {
    local workspace
    workspace="$(mktemp -d)"
    local log_file="$workspace/docker.log"

    make_workspace "$workspace" true false
    make_fake_docker "$workspace/bin" "$log_file"

    local output
    output="$(run_nge "$workspace" "$log_file" code:reload)"

    assert_contains "$output" 'compose restart core-blue horizon'
    assert_not_contains "$output" 'compose restart core-blue horizon scheduler'
    assert_contains "$output" 'compose rm --stop --force scheduler'
    assert_contains "$output" 'compose restart gateway'

    rm -rf "$workspace"
}

test_down_stops_worker_services_explicitly() {
    local workspace
    workspace="$(mktemp -d)"
    local log_file="$workspace/docker.log"

    make_workspace "$workspace" false false
    make_fake_docker "$workspace/bin" "$log_file"

    local output
    output="$(run_nge "$workspace" "$log_file" down)"

    assert_contains "$output" 'compose rm --stop --force horizon scheduler'
    assert_contains "$output" 'compose down'

    rm -rf "$workspace"
}

test_start_stops_disabled_workers
test_start_keeps_enabled_worker_targetable
test_image_upgrade_reconciles_disabled_workers
test_image_upgrade_recreates_only_enabled_worker
test_image_upgrade_recreates_enabled_workers
test_update_downtime_reconciles_disabled_workers
test_update_zero_downtime_recreates_only_enabled_worker
test_code_reload_reconciles_disabled_workers
test_down_stops_worker_services_explicitly

printf 'nge worker disable tests passed\n'
