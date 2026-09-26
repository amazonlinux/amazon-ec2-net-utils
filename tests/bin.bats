#!/usr/bin/env bats

load test_helper

@test "set-hostname-imds sets an empty static hostname from IMDS" {
    local call_log="${BATS_TEST_TMPDIR}/set-hostname-calls.log"
    local hostname_file="${BATS_TEST_TMPDIR}/etc/hostname"
    local mock_libdir="${BATS_TEST_TMPDIR}/set-hostname-lib"

    mkdir -p "$(dirname "$hostname_file")" "$mock_libdir"
    : > "$hostname_file"
    cat > "${mock_libdir}/lib.sh" <<'EOF'
get_token() {
    printf 'get_token\n' >> "$CALL_LOG"
}
get_imds() {
    printf 'get_imds %s\n' "$*" >> "$CALL_LOG"
    printf 'ip-10-0-0-5.ec2.internal\n'
}
info() {
    printf 'info %s\n' "$*" >> "$CALL_LOG"
}
error() {
    printf 'error %s\n' "$*" >> "$CALL_LOG"
}
hostnamectl() {
    printf 'hostnamectl %s\n' "$*" >> "$CALL_LOG"
}
EOF

    run env \
        CALL_LOG="$call_log" \
        EC2_NET_UTILS_HOSTNAME_FILE_OVERRIDE="$hostname_file" \
        LIBDIR_OVERRIDE="$mock_libdir" \
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

@test "setup-policy-routes refresh configures an existing interface" {
    local call_log="${BATS_TEST_TMPDIR}/policy-route-calls.log"
    local mock_libdir="${BATS_TEST_TMPDIR}/policy-route-lib"
    local runtime_root="${BATS_TEST_TMPDIR}/run/amazon-ec2-net-utils"
    local sys_class_net="${BATS_TEST_TMPDIR}/sys/class/net"
    local unit_dir="${BATS_TEST_TMPDIR}/run/systemd/network"

    mkdir -p "$mock_libdir" "${sys_class_net}/ens6" "$unit_dir"
    printf '00:11:22:33:44:55\n' > "${sys_class_net}/ens6/address"
    cat > "${mock_libdir}/lib.sh" <<'EOF'
register_networkd_reloader() {
    printf 'register_networkd_reloader\n' >> "$CALL_LOG"
}
debug() {
    printf 'debug %s\n' "$*" >> "$CALL_LOG"
}
error() {
    printf 'error %s\n' "$*" >> "$CALL_LOG"
}
setup_interface() {
    printf 'setup_interface %s\n' "$*" >> "$CALL_LOG"
    printf '1\n'
}
EOF

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
