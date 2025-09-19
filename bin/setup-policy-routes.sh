#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may
# not use this file except in compliance with the License. A copy of the
# License is located at
#
#      http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

set -eo pipefail -o noclobber -o nounset

export unitdir lockdir runtimeroot reload_flag
declare -r runtimeroot="/run/amazon-ec2-net-utils"
declare -r lockdir="${runtimeroot}/setup-policy-routes"
declare -r unitdir="/run/systemd/network"
declare -r reload_flag="${runtimeroot}/.policy-routes-reload-networkd"

libdir=${LIBDIR_OVERRIDE:-AMAZON_EC2_NET_UTILS_LIBDIR}
# shellcheck source=../lib/lib.sh
. "${libdir}/lib.sh"

iface="$1"
[ -n "$iface" ] || { error "Invocation error"; exit 1; }

mkdir -p "$runtimeroot"

do_setup() {
    ether=$(cat /sys/class/net/${iface}/address)

    declare -i changes=0
    changes+=$(setup_interface $iface $ether)
    if [ $changes -gt 0 ]; then
        touch "$reload_flag"
    fi
}

case "$2" in
refresh)
    register_networkd_reloader
    [ -e "/sys/class/net/${iface}" ] || exit 0
    info "Starting configuration refresh for $iface"
    do_setup
    ;;
start)
    register_networkd_reloader
    while [ ! -e "/sys/class/net/${iface}" ]; do
        debug  "Waiting for sysfs node to exist"
        sleep 0.1
    done
    info "Starting configuration for $iface"
    debug /lib/systemd/systemd-networkd-wait-online -i "$iface"
    /lib/systemd/systemd-networkd-wait-online -i "$iface"
    export EC2_IF_INITIAL_SETUP=1
    do_setup
    ;;
remove)
    register_networkd_reloader
    info "Removing configuration for $iface."
    rm -rf "/run/network/$iface" \
       "${unitdir}/70-${iface}.network" \
       "${unitdir}/70-${iface}.network.d" || true
    touch "$reload_flag"
    ;;
stop|cleanup)
    # this is a no-op, only supported for compatibility
    :;;
*)
    echo "USAGE: $0: start|stop"
    echo "  This tool is normally invoked via udev rules."
    echo "  See https://github.com/amazonlinux/amazon-ec2-net-utils"
    ;;
esac

exit 0
