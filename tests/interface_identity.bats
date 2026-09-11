#!/usr/bin/env bats
# shellcheck disable=SC2154  # Globals are provided by test_helper/lib.sh.

load test_helper

@test "_is_primary_interface compares against the top-level IMDS MAC" {
    get_imds() {
        printf '00:11:22:33:44:55\n'
    }

    run _is_primary_interface "00:11:22:33:44:55"
    [ "$status" -eq 0 ]

    run _is_primary_interface "00:11:22:33:44:66"
    [ "$status" -eq 1 ]
}

@test "_get_device_number returns zero immediately for the primary interface" {
    local request_marker="${BATS_TEST_TMPDIR}/requested"
    _is_primary_interface() {
        return 0
    }
    get_iface_imds() {
        touch "$request_marker"
        printf '9\n'
    }

    run _get_device_number "ens5" "00:11:22:33:44:55" 0

    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    [ ! -e "$request_marker" ]
}

@test "_get_device_number retries an unpropagated zero value" {
    local request_log="${BATS_TEST_TMPDIR}/requests.log"
    _is_primary_interface() {
        return 1
    }
    sleep() {
        :
    }
    get_iface_imds() {
        printf 'call\n' >> "$request_log"
        if [ "$(wc -l < "$request_log")" -lt 3 ]; then
            printf '0\n'
        else
            printf '2\n'
        fi
    }

    run _get_device_number "ens6" "00:11:22:33:44:66" 0

    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
    [ "$(wc -l < "$request_log")" -eq 3 ]
}

@test "_get_network_card records support after a propagated value appears" {
    local request_log="${BATS_TEST_TMPDIR}/requests.log"
    _is_primary_interface() {
        return 1
    }
    sleep() {
        :
    }
    get_iface_imds() {
        printf 'call\n' >> "$request_log"
        if [ "$(wc -l < "$request_log")" -ge 2 ]; then
            printf '1\n'
        fi
    }

    run _get_network_card "ens6" "00:11:22:33:44:66"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    [ "$(wc -l < "$request_log")" -eq 2 ]
    [ -e "${runtimeroot}/.has-network-card" ]
    [ ! -e "${runtimeroot}/.no-network-card" ]
}

@test "_get_network_card records lack of support after exhausting retries" {
    local request_log="${BATS_TEST_TMPDIR}/requests.log"
    _is_primary_interface() {
        return 1
    }
    sleep() {
        :
    }
    get_iface_imds() {
        printf 'call\n' >> "$request_log"
    }

    run _get_network_card "ens6" "00:11:22:33:44:66"

    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    [ "$(wc -l < "$request_log")" -eq 8 ]
    [ -e "${runtimeroot}/.no-network-card" ]
    [ ! -e "${runtimeroot}/.has-network-card" ]
}

@test "setup_interface configures both policy families on a secondary interface" {
    local calls="${BATS_TEST_TMPDIR}/calls.log"
    get_token() {
        printf 'get_token %s\n' "$*" >> "$calls"
    }
    _get_network_card() {
        printf '1\n'
    }
    _get_device_number() {
        printf '2\n'
    }
    create_interface_config() {
        printf 'create_interface_config %s\n' "$*" >> "$calls"
        printf '1\n'
    }
    _is_primary_interface() {
        return 1
    }
    create_rules() {
        printf 'create_rules %s\n' "$*" >> "$calls"
        printf '0\n'
    }
    create_ipv4_aliases() {
        printf 'create_ipv4_aliases %s\n' "$*" >> "$calls"
        printf '0\n'
    }
    date() {
        if [ "$1" = "-d" ]; then
            printf '100\n'
        else
            printf '99\n'
        fi
    }

    run setup_interface "ens6" "00:11:22:33:44:66"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    grep -Fx "get_token ens6" "$calls"
    grep -Fx \
        "create_interface_config ens6 2 1 00:11:22:33:44:66" \
        "$calls"
    grep -Fx "create_rules ens6 2 1 4" "$calls"
    grep -Fx "create_rules ens6 2 1 6" "$calls"
    grep -Fx \
        "create_ipv4_aliases ens6 00:11:22:33:44:66" \
        "$calls"
}
