#!/usr/bin/env bats
# shellcheck disable=SC2034,SC2154  # Globals are provided by test_helper/lib.sh.

load test_helper

@test "subnet_supports_ipv4 distinguishes routable and link-local addresses" {
    local address
    ip() {
        printf '2: ens6    inet %s scope global ens6\n' "$address"
    }

    address="10.0.0.5/24"
    run subnet_supports_ipv4 "ens6"
    [ "$status" -eq 0 ]

    address="169.254.10.5/16"
    run subnet_supports_ipv4 "ens6"
    [ "$status" -eq 1 ]
}

@test "subnet_supports_ipv6 detects a global IPv6 address" {
    ip() {
        printf '2: ens6    inet6 2001:db8::5/64 scope global\n'
    }

    run subnet_supports_ipv6 "ens6"

    [ "$status" -eq 0 ]
}

@test "subnet_routes selects the IMDS key for each address family" {
    get_and_validate_imds() {
        printf '%s|%s\n' "$1" "$2"
    }

    run subnet_routes "00:11:22:33:44:55" "ipv4"
    [ "$status" -eq 0 ]
    [ "$output" = \
        "00:11:22:33:44:55|subnet-ipv4-cidr-block" ]

    run subnet_routes "00:11:22:33:44:55" "ipv6"
    [ "$status" -eq 0 ]
    [ "$output" = \
        "00:11:22:33:44:55|subnet-ipv6-cidr-blocks" ]
}

@test "create_ipv4_aliases writes sorted secondary addresses" {
    local expected="${BATS_TEST_TMPDIR}/expected"
    local config

    subnet_supports_ipv4() {
        return 0
    }
    get_and_validate_imds() {
        printf '%s\n' "10.0.0.5" "10.0.0.20" "10.0.0.10"
    }

    run create_ipv4_aliases "ens6" "00:11:22:33:44:55"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    config=$(find "$unitdir" -name ec2net_alias.conf -print -quit)
    [ -n "$config" ]
    cat > "$expected" <<'EOF'
[Address]
Address=10.0.0.10/32
AddPrefixRoute=false
[Address]
Address=10.0.0.20/32
AddPrefixRoute=false
EOF
    diff -u "$expected" "$config"
}

@test "create_ipv4_aliases removes stale aliases when only the primary remains" {
    local config
    get_and_validate_imds() {
        printf '%s\n' "10.0.0.5" "10.0.0.10"
    }
    subnet_supports_ipv4() {
        return 0
    }
    create_ipv4_aliases "ens6" "00:11:22:33:44:55" >/dev/null
    config=$(find "$unitdir" -name ec2net_alias.conf -print -quit)
    [ -n "$config" ]
    printf 'stale alias configuration\n' >| "$config"

    get_and_validate_imds() {
        printf '10.0.0.5\n'
    }

    run create_ipv4_aliases "ens6" "00:11:22:33:44:55"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    [ ! -e "$config" ]
}

@test "create_rules writes address and prefix policy rules using the interface table" {
    local expected="${BATS_TEST_TMPDIR}/expected"
    local config
    ether="00:11:22:33:44:55"

    subnet_supports_ipv4() {
        return 0
    }
    get_and_validate_imds() {
        printf '%s\n' "10.0.0.5" "10.0.0.10"
    }
    get_iface_imds() {
        printf '10.0.1.0/24\n'
    }

    run create_rules "ens6" 2 1 4

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    config=$(find "$unitdir" -name ec2net_policy_4.conf -print -quit)
    [ -n "$config" ]
    cat > "$expected" <<'EOF'
[RoutingPolicyRule]
From=10.0.0.5
Priority=10102
Table=10102
[RoutingPolicyRule]
From=10.0.0.10
Priority=10102
Table=10102
[RoutingPolicyRule]
From=10.0.1.0/24
Priority=10102
Table=10102
EOF
    diff -u "$expected" "$config"
}

@test "create_rules preserves existing policy when required metadata is unavailable" {
    local config
    ether="00:11:22:33:44:55"

    subnet_supports_ipv4() {
        return 0
    }
    get_and_validate_imds() {
        printf '10.0.0.5\n'
    }
    get_iface_imds() {
        return 0
    }
    create_rules "ens6" 2 1 4 >/dev/null
    config=$(find "$unitdir" -name ec2net_policy_4.conf -print -quit)
    [ -n "$config" ]
    printf 'existing policy\n' >| "$config"

    get_and_validate_imds() {
        return 1
    }

    run create_rules "ens6" 2 1 4

    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(cat "$config")" = "existing policy" ]
}

@test "create_if_overrides generates dual-stack routes with deterministic IDs" {
    local cfgfile="${unitdir}/70-ens6.network"
    local config="${cfgfile}.d/eni.conf"

    subnet_supports_ipv4() {
        return 0
    }
    subnet_supports_ipv6() {
        return 0
    }
    subnet_routes() {
        case "$2" in
        ipv4)
            printf '10.0.0.0/24\n'
            ;;
        ipv6)
            printf '2001:db8:1::/64\n'
            ;;
        esac
    }

    run create_if_overrides \
        "ens6" 2 1 "00:11:22:33:44:55" "$cfgfile"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    [ "$(grep -c '^RouteMetric=614$' "$config")" -eq 2 ]
    [ "$(grep -c '^Table=10102$' "$config")" -eq 4 ]
    grep -Fx "Gateway=_ipv6ra" "$config"
    grep -Fx "Gateway=_dhcp4" "$config"
    grep -Fx "Destination=2001:db8:1::/64" "$config"
    grep -Fx "Destination=10.0.0.0/24" "$config"
}

@test "add_altnames adds missing ENI and device-number names" {
    local ip_log="${BATS_TEST_TMPDIR}/ip.log"
    get_iface_imds() {
        printf 'eni-0123456789abcdef0\n'
    }
    ip() {
        printf '%s\n' "$*" >> "$ip_log"
        if [ "$1 $2" = "link show" ]; then
            return 1
        fi
        return 0
    }

    run add_altnames "ens6" "00:11:22:33:44:55" 2 1

    [ "$status" -eq 0 ]
    grep -Fx \
        "link property add dev ens6 altname eni-0123456789abcdef0" \
        "$ip_log"
    grep -Fx \
        "link property add dev ens6 altname device-number-2.1" \
        "$ip_log"
}

@test "create_interface_config links the base config and invokes its generators" {
    local calls="${BATS_TEST_TMPDIR}/calls.log"
    local config
    create_if_overrides() {
        printf 'create_if_overrides %s\n' "$*" >> "$calls"
        printf '1\n'
    }
    add_altnames() {
        printf 'add_altnames %s\n' "$*" >> "$calls"
    }

    run create_interface_config "ens6" 2 1 "00:11:22:33:44:55"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    config=$(find "$unitdir" -maxdepth 1 -type l -name '*-ens6.network' -print -quit)
    [ -n "$config" ]
    [ -L "$config" ]
    [ "$(readlink "$config")" = "/usr/lib/systemd/network/80-ec2.network" ]
    grep -F "create_if_overrides ens6 2 1 00:11:22:33:44:55" "$calls"
    grep -F "add_altnames ens6 00:11:22:33:44:55 2 1" "$calls"
}
