#!/usr/bin/env bash
# shellcheck disable=SC2034  # Globals are consumed by sourced functions/tests.

setup() {
    # shellcheck source=../lib/lib.sh
    source "${BATS_TEST_DIRNAME}/../lib/lib.sh"

    # setup-policy-routes.sh enables noclobber before sourcing lib.sh.
    # register_networkd_reloader relies on it for atomic lock acquisition.
    set -o noclobber

    unitdir="${BATS_TEST_TMPDIR}/run/systemd/network"
    runtimeroot="${BATS_TEST_TMPDIR}/run/amazon-ec2-net-utils"
    lockdir="${runtimeroot}/setup-policy-routes"
    reload_flag="${runtimeroot}/.policy-routes-reload-networkd"

    imds_endpoint=""
    imds_token=""
    imds_interface=""
    ether=""

    mkdir -p "$unitdir" "$runtimeroot"
    unset EC2_IF_INITIAL_SETUP

    # Keep test output free of syslog traffic by default. Individual tests can
    # override error(), debug(), or logger() when logging is under test.
    logger() {
        :
    }
}
