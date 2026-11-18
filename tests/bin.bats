#!/usr/bin/env bats

load test_helper

# This test models a host whose static hostname file is empty. It replaces the
# IMDS and hostnamectl calls with mocks, then verifies that set-hostname-imds
# retrieves local-hostname from IMDS and passes the returned value to
# hostnamectl.
@test "set-hostname-imds sets the hostname from IMDS when the static hostname is empty" {
    local call_log="${BATS_TEST_TMPDIR}/set-hostname-calls.log"
    local hostname_file="${BATS_TEST_TMPDIR}/etc/hostname"
    local mock_libdir="${BATS_TEST_DIRNAME}/fixtures/set-hostname"

    mkdir -p "$(dirname "$hostname_file")"
    : > "$hostname_file"

    run env \
        CALL_LOG="$call_log" \
        EC2_NET_UTILS_HOSTNAME_FILE_OVERRIDE="$hostname_file" \
        LIBDIR_OVERRIDE="$mock_libdir" \
        MOCK_IMDS_HOSTNAME="ip-10-0-0-5.ec2.internal" \
        bash "${BATS_TEST_DIRNAME}/../bin/set-hostname-imds.sh"

    [ "$status" -eq 0 ]
    grep -Fx "get_token" "$call_log"
    grep -Fx "get_imds local-hostname" "$call_log"
    grep -Fx \
        "info Setting hostname to ip-10-0-0-5.ec2.internal retrieved from IMDS" \
        "$call_log"
    grep -Fx \
        "hostnamectl hostname ip-10-0-0-5.ec2.internal" \
        "$call_log"
}

# This test models a host that already has a user-defined static hostname. It
# verifies that set-hostname-imds exits successfully without contacting IMDS
# or invoking hostnamectl, ensuring an existing hostname is never overwritten.
@test "set-hostname-imds preserves an existing static hostname" {
    local call_log="${BATS_TEST_TMPDIR}/set-hostname-existing-calls.log"
    local hostname_file="${BATS_TEST_TMPDIR}/etc/hostname"
    local mock_libdir="${BATS_TEST_DIRNAME}/fixtures/set-hostname"

    mkdir -p "$(dirname "$hostname_file")"
    printf 'custom.example.internal\n' > "$hostname_file"

    run env \
        CALL_LOG="$call_log" \
        EC2_NET_UTILS_HOSTNAME_FILE_OVERRIDE="$hostname_file" \
        LIBDIR_OVERRIDE="$mock_libdir" \
        bash "${BATS_TEST_DIRNAME}/../bin/set-hostname-imds.sh"

    [ "$status" -eq 0 ]
    grep -Fx \
        "info Static hostname is already set - not modifying existing hostname" \
        "$call_log"
    run grep -E '^(get_token|get_imds|hostnamectl)' "$call_log"
    [ "$status" -eq 1 ]
}

# This test models an empty static hostname file followed by an empty response
# from IMDS. It verifies that the script reports failure, logs the reason, and
# does not call hostnamectl with an invalid or empty hostname.
@test "set-hostname-imds fails when IMDS returns an empty hostname" {
    local call_log="${BATS_TEST_TMPDIR}/set-hostname-empty-imds-calls.log"
    local hostname_file="${BATS_TEST_TMPDIR}/etc/hostname"
    local mock_libdir="${BATS_TEST_DIRNAME}/fixtures/set-hostname"

    mkdir -p "$(dirname "$hostname_file")"
    : > "$hostname_file"

    run env \
        CALL_LOG="$call_log" \
        EC2_NET_UTILS_HOSTNAME_FILE_OVERRIDE="$hostname_file" \
        LIBDIR_OVERRIDE="$mock_libdir" \
        bash "${BATS_TEST_DIRNAME}/../bin/set-hostname-imds.sh"

    [ "$status" -eq 1 ]
    grep -Fx "get_token" "$call_log"
    grep -Fx "get_imds local-hostname" "$call_log"
    grep -Fx "error Unable to retrieve hostname from IMDS - aborting" "$call_log"
    run grep -E '^hostnamectl' "$call_log"
    [ "$status" -eq 1 ]
}

@test "setup-policy-routes refresh configures an existing interface" {
    local call_log="${BATS_TEST_TMPDIR}/policy-route-calls.log"
    local mock_libdir="${BATS_TEST_DIRNAME}/fixtures/setup-policy-routes"
    local runtime_root="${BATS_TEST_TMPDIR}/run/amazon-ec2-net-utils"
    local sys_class_net="${BATS_TEST_TMPDIR}/sys/class/net"
    local unit_dir="${BATS_TEST_TMPDIR}/run/systemd/network"

    mkdir -p "${sys_class_net}/ens6" "$unit_dir"
    printf '00:11:22:33:44:55\n' > "${sys_class_net}/ens6/address"

    run env \
        CALL_LOG="$call_log" \
        LIBDIR_OVERRIDE="$mock_libdir" \
        EC2_NET_UTILS_RUNTIME_ROOT_OVERRIDE="$runtime_root" \
        EC2_NET_UTILS_SYS_CLASS_NET_OVERRIDE="$sys_class_net" \
        EC2_NET_UTILS_UNIT_DIR_OVERRIDE="$unit_dir" \
        bash "${BATS_TEST_DIRNAME}/../bin/setup-policy-routes.sh" \
        "ens6" "refresh"

    [ "$status" -eq 0 ]
    grep -Fx "register_networkd_reloader" "$call_log"
    grep -Fx "debug Starting configuration refresh for ens6" "$call_log"
    grep -Fx \
        "setup_interface ens6 00:11:22:33:44:55" \
        "$call_log"
    [ -e "${runtime_root}/.policy-routes-reload-networkd" ]
}

# This test models a refresh event that arrives after an interface has already
# disappeared from sysfs. It verifies that the process registers for coordinated
# networkd reload handling, exits successfully, and never tries to generate
# configuration for the missing interface.
@test "setup-policy-routes refresh exits successfully when the interface is absent" {
    local call_log="${BATS_TEST_TMPDIR}/policy-route-missing-refresh-calls.log"
    local mock_libdir="${BATS_TEST_DIRNAME}/fixtures/setup-policy-routes"
    local runtime_root="${BATS_TEST_TMPDIR}/run/amazon-ec2-net-utils"
    local sys_class_net="${BATS_TEST_TMPDIR}/sys/class/net"
    local unit_dir="${BATS_TEST_TMPDIR}/run/systemd/network"

    mkdir -p "$sys_class_net" "$unit_dir"

    run env \
        CALL_LOG="$call_log" \
        LIBDIR_OVERRIDE="$mock_libdir" \
        EC2_NET_UTILS_RUNTIME_ROOT_OVERRIDE="$runtime_root" \
        EC2_NET_UTILS_SYS_CLASS_NET_OVERRIDE="$sys_class_net" \
        EC2_NET_UTILS_UNIT_DIR_OVERRIDE="$unit_dir" \
        bash "${BATS_TEST_DIRNAME}/../bin/setup-policy-routes.sh" \
        "missing0" "refresh"

    [ "$status" -eq 0 ]
    grep -Fx "register_networkd_reloader" "$call_log"
    run grep -E '^setup_interface' "$call_log"
    [ "$status" -eq 1 ]
}

# This test models a start event for an interface whose sysfs node never
# appears. It shortens the production wait through test-only overrides and
# verifies exit status 2, a timeout error, and cleanup of the interface's
# refresh timer instead of an infinite wait.
@test "setup-policy-routes start times out and disables refresh for a missing interface" {
    local call_log="${BATS_TEST_TMPDIR}/policy-route-timeout-calls.log"
    local mock_libdir="${BATS_TEST_DIRNAME}/fixtures/setup-policy-routes"
    local runtime_root="${BATS_TEST_TMPDIR}/run/amazon-ec2-net-utils"
    local sys_class_net="${BATS_TEST_TMPDIR}/sys/class/net"
    local unit_dir="${BATS_TEST_TMPDIR}/run/systemd/network"

    mkdir -p "$sys_class_net" "$unit_dir"

    run env \
        CALL_LOG="$call_log" \
        LIBDIR_OVERRIDE="$mock_libdir" \
        EC2_NET_UTILS_RUNTIME_ROOT_OVERRIDE="$runtime_root" \
        EC2_NET_UTILS_SYS_CLASS_NET_OVERRIDE="$sys_class_net" \
        EC2_NET_UTILS_SYSFS_WAIT_MAX_OVERRIDE=3 \
        EC2_NET_UTILS_SYSTEMCTL_OVERRIDE=/bin/echo \
        EC2_NET_UTILS_UNIT_DIR_OVERRIDE="$unit_dir" \
        bash "${BATS_TEST_DIRNAME}/../bin/setup-policy-routes.sh" \
        "missing0" "start"

    [ "$status" -eq 2 ]
    [ "$output" = "disable --now refresh-policy-routes@missing0.timer" ]
    grep -Fx "register_networkd_reloader" "$call_log"
    grep -F "error Timed out waiting for sysfs node for missing0" "$call_log"
}
