#!/usr/bin/env bats
# shellcheck disable=SC2034,SC2154  # Globals are provided by test_helper/lib.sh.

load test_helper

@test "maybe_reload_networkd reloads after the final process exits" {
    local networkctl_log="${BATS_TEST_TMPDIR}/networkctl.log"
    iface="ens6"
    mkdir -p "$lockdir"
    printf '%s\n' "$$" > "${lockdir}/${iface}"
    touch "$reload_flag"

    networkctl() {
        printf '%s\n' "$*" > "$networkctl_log"
    }

    run maybe_reload_networkd

    [ "$status" -eq 0 ]
    [ ! -e "$lockdir" ]
    [ ! -e "$reload_flag" ]
    [ "$(cat "$networkctl_log")" = "reload" ]
}

@test "maybe_reload_networkd defers while another process is registered" {
    local debug_log="${BATS_TEST_TMPDIR}/debug.log"
    local networkctl_marker="${BATS_TEST_TMPDIR}/networkctl-called"
    iface="ens6"
    mkdir -p "$lockdir"
    printf '%s\n' "$$" > "${lockdir}/${iface}"
    printf '12345\n' > "${lockdir}/ens7"
    touch "$reload_flag"

    networkctl() {
        touch "$networkctl_marker"
    }
    debug() {
        printf '%s\n' "$*" > "$debug_log"
    }

    run maybe_reload_networkd

    [ "$status" -eq 0 ]
    [ -e "${lockdir}/ens7" ]
    [ -e "$reload_flag" ]
    [ ! -e "$networkctl_marker" ]
    grep -F "Deferring networkd reload to another process" "$debug_log"
}

@test "register_networkd_reloader does not overwrite an active lock" {
    local lockfile
    local observed_lock="${BATS_TEST_TMPDIR}/observed-lock"
    local sleep_log="${BATS_TEST_TMPDIR}/sleep.log"
    iface="ens6"
    lockfile="${lockdir}/${iface}"
    mkdir -p "$lockdir"
    printf '12345\n' > "$lockfile"

    kill() {
        return 0
    }
    sleep() {
        cat "$lockfile" >> "$observed_lock"
        printf 'sleep\n' >> "$sleep_log"
        rm -f "$lockfile"
    }
    maybe_reload_networkd() {
        :
    }

    run register_networkd_reloader

    [ "$status" -eq 0 ]
    [ "$(cat "$observed_lock")" = "12345" ]
    [ "$(wc -l < "$sleep_log")" -eq 1 ]
    [ -f "$lockfile" ]
    [ "$(cat "$lockfile")" != "12345" ]
}

# AmiTest source: ec2-net-utils-infinite-loop-fix
@test "register_networkd_reloader replaces a stale lock from a dead process" {
    local debug_log="${BATS_TEST_TMPDIR}/debug.log"
    local lockfile
    iface="ens6"
    lockfile="${lockdir}/${iface}"
    mkdir -p "$lockdir"
    printf '99999\n' > "$lockfile"

    kill() {
        if [ "$1" = "-0" ] && [ "$2" = "99999" ]; then
            return 1
        fi
        return 0
    }
    debug() {
        printf '%s\n' "$*" >> "$debug_log"
    }
    maybe_reload_networkd() {
        :
    }

    run register_networkd_reloader

    [ "$status" -eq 0 ]
    grep -F "Removing stale lock from dead process 99999 for ens6" "$debug_log"
    [ -f "$lockfile" ]
    [ "$(cat "$lockfile")" != "99999" ]
}
