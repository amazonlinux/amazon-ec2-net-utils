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

set -eo pipefail

declare -r runtimedir="/run/systemd/network"

libdir=${LIBDIR_OVERRIDE:-AMAZON_EC2_NET_UTILS_LIBDIR}
# shellcheck source=../lib/lib.sh
. "${libdir}/lib.sh"

iface="$1"
[ -n "$iface" ] || { error "Invocation error"; exit 1; }

get_token

case "$2" in
stop)
    register_networkd_reloader
    info "Stopping $iface."
    rm -rf "/run/network/$iface" \
       "${runtimedir}/70-${iface}.network" \
       "${runtimedir}/70-${iface}.network.d"
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
    ether=$(cat /sys/class/net/${iface}/address)

    declare -i changes=0
    # Ideally we'd use the device-number interface property from IMDS,
    # but interface details take some time to propagate, and IMDS
    # reports 0 for the device-number prior to propagation...
    changes+=$(setup_interface $iface $ether)
    if [ $changes -gt 0 ]; then
        touch /run/policy-routes-reload-networkd
    fi
    ;;
*)
    echo "USAGE: $0: start|stop"
    echo "  This tool is normally invoked via udev rules."
    echo "  See https://github.com/amazonlinux/amazon-ec2-net-utils"
    ;;
esac

exit 0
