#!/usr/bin/env bats
# shellcheck disable=SC2154  # Globals are provided by test_helper/lib.sh.

load test_helper

@test "get_lowest_secondary_interface returns the second predictable interface" {
    basename() {
        printf '%s\n' "lo" "ens5" "ens6"
    }

    run get_lowest_secondary_interface

    [ "$status" -eq 0 ]
    [ "$output" = "ens6" ]
}

@test "make_token_request passes the interface and token request options to curl" {
    local curl_log="${BATS_TEST_TMPDIR}/curl.log"
    curl() {
        printf '%s\n' "$@" > "$curl_log"
        printf 'test-token\n'
    }

    run make_token_request "http://169.254.169.254/latest" "ens6"

    [ "$status" -eq 0 ]
    [ "$output" = "test-token" ]
    grep -Fx -- "--interface" "$curl_log"
    grep -Fx -- "ens6" "$curl_log"
    grep -Fx -- "X-aws-ec2-metadata-token-ttl-seconds: 60" "$curl_log"
    grep -Fx -- "http://169.254.169.254/latest/api/token" "$curl_log"
}

@test "get_meta returns metadata and sends authentication options to curl" {
    local curl_log="${BATS_TEST_TMPDIR}/curl.log"
    imds_endpoint="http://169.254.169.254/latest"
    imds_token="test-token"
    imds_interface="ens6"

    curl() {
        printf '%s\n' "$@" > "$curl_log"
        printf '10.0.0.42\n'
    }

    run get_meta "local-ipv4"

    [ "$status" -eq 0 ]
    [ "$output" = "10.0.0.42" ]
    grep -Fx -- "--interface" "$curl_log"
    grep -Fx -- "ens6" "$curl_log"
    grep -Fx -- "X-aws-ec2-metadata-token:test-token" "$curl_log"
    grep -Fx -- "http://169.254.169.254/latest/meta-data/local-ipv4" "$curl_log"
}

@test "get_iface_imds builds the interface metadata path" {
    local request_log="${BATS_TEST_TMPDIR}/request.log"
    get_meta() {
        printf '%s|%s\n' "$1" "$2" > "$request_log"
        printf '10.0.0.0/24\n'
    }

    run get_iface_imds \
        "00:11:22:33:44:55" "subnet-ipv4-cidr-block" 3

    [ "$status" -eq 0 ]
    [ "$output" = "10.0.0.0/24" ]
    [ "$(cat "$request_log")" = \
        "network/interfaces/macs/00:11:22:33:44:55/subnet-ipv4-cidr-block|3" ]
}

@test "info logs with info priority" {
    local logger_log="${BATS_TEST_TMPDIR}/logger.log"
    logger() {
        printf '%s\n' "$@" > "$logger_log"
    }

    run info "interface configured"

    [ "$status" -eq 0 ]
    grep -Fx -- "--priority" "$logger_log"
    grep -Fx -- "user.info" "$logger_log"
    grep -Fx -- "--tag" "$logger_log"
    grep -Fx -- "ec2net" "$logger_log"
    grep -Fx -- "interface configured" "$logger_log"
}

@test "get_meta fails before calling curl when token state is incomplete" {
    local curl_marker="${BATS_TEST_TMPDIR}/curl-called"
    local error_log="${BATS_TEST_TMPDIR}/error.log"
    imds_endpoint=""
    imds_token=""
    imds_interface=""

    curl() {
        touch "$curl_marker"
    }
    error() {
        printf '%s\n' "$*" >> "$error_log"
    }

    run get_meta "local-ipv4"

    [ "$status" -eq 1 ]
    [ ! -e "$curl_marker" ]
    grep -F "Unable to obtain IMDS token" "$error_log"
}

@test "get_meta retries curl up to the requested attempt count" {
    local curl_log="${BATS_TEST_TMPDIR}/curl.log"
    imds_endpoint="http://169.254.169.254/latest"
    imds_token="test-token"
    imds_interface="$default_route"

    curl() {
        printf 'call\n' >> "$curl_log"
        return 22
    }

    run get_meta "local-hostname" 3

    [ "$status" -eq 1 ]
    [ "$(wc -l < "$curl_log")" -eq 3 ]
}

@test "get_and_validate_imds rejects an empty metadata response" {
    local error_log="${BATS_TEST_TMPDIR}/error.log"
    get_iface_imds() {
        return 0
    }
    error() {
        printf '%s\n' "$*" >> "$error_log"
    }

    run get_and_validate_imds "00:11:22:33:44:55" "local-ipv4s"

    [ "$status" -eq 1 ]
    [ -z "$output" ]
    grep -F "local-ipv4s returned empty" "$error_log"
}

@test "get_token falls back from the requested interface to the default route" {
    local request_log="${BATS_TEST_TMPDIR}/requests.log"
    date() {
        if [ "$1" = "-d" ]; then
            printf '100\n'
        else
            printf '99\n'
        fi
    }
    make_token_request() {
        printf '%s|%s\n' "$1" "${2:-}" >> "$request_log"
        if [ -z "${2:-}" ]; then
            printf 'test-token\n'
        fi
    }

    get_token "ens6"

    [ "$imds_token" = "test-token" ]
    [ "$imds_endpoint" = "http://169.254.169.254/latest" ]
    [ "$imds_interface" = "$default_route" ]
    [ "$(wc -l < "$request_log")" -eq 2 ]
}
