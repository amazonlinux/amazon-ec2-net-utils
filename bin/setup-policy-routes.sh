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
declare -r runtimeroot="${EC2_NET_UTILS_RUNTIME_ROOT_OVERRIDE:-/run/amazon-ec2-net-utils}"
declare -r lockdir="${runtimeroot}/setup-policy-routes"
declare -r unitdir="${EC2_NET_UTILS_UNIT_DIR_OVERRIDE:-/run/systemd/network}"
declare -r reload_flag="${runtimeroot}/.policy-routes-reload-networkd"
declare -r sys_class_net="${EC2_NET_UTILS_SYS_CLASS_NET_OVERRIDE:-/sys/class/net}"

libdir=${LIBDIR_OVERRIDE:-AMAZON_EC2_NET_UTILS_LIBDIR}
# shellcheck source=../lib/lib.sh
. "${libdir}/lib.sh"

iface="$1"
[ -n "$iface" ] || { error "Invocation error"; exit 1; }

mkdir -p "$runtimeroot"

do_setup() {
    ether=$(cat "${sys_class_net}/${iface}/address")

    declare -i changes=0
    changes+=$(setup_interface $iface $ether)
    if [ $changes -gt 0 ]; then
        touch "$reload_flag"
    fi
}

case "$2" in
refresh)
    register_networkd_reloader
    [ -e "${sys_class_net}/${iface}" ] || exit 0
    debug "Starting configuration refresh for $iface"
    do_setup
    ;;
start)
    register_networkd_reloader
    counter=0
    max_wait=6000   # 10 minute timeout to avoid infinite loop if sysfs node never appears
    while [ ! -e "${sys_class_net}/${iface}" ]; do
        if ((counter % 1000 == 0)); then
            debug "Waiting for sysfs node to exist for ${iface} (iteration $counter)"
        fi
        sleep 0.1
        ((counter++)) || true
        if ((counter >= max_wait)); then
            error "Timed out waiting for sysfs node for ${iface} after $((counter / 10)) seconds"
            /usr/bin/systemctl disable --now refresh-policy-routes@${iface}.timer 2>/dev/null || true
            exit 2
        fi
    done
    debug "Starting configuration for $iface"
    debug /lib/systemd/systemd-networkd-wait-online -i "$iface"
    /lib/systemd/systemd-networkd-wait-online -i "$iface"
    export EC2_IF_INITIAL_SETUP=1
    do_setup
    ;;
remove)
    # Clean up stale 70-<iface>.network config left behind when an ENI
    # renames on re-attach (ens6 -> ens7, amazon-ec2-net-utils#166).
    # Do not networkd reload/reconfigure here: the link is already gone by
    # the time this runs, and a global reload would reset conntrack for
    # unrelated interfaces (the regression fixed in: 
    # https://github.com/amazonlinux/amazon-ec2-net-utils/pull/107/changes/c35c4d504fea196af3aa4a00c84b17fa54657d9e).
    # In addtion, this code also runs during upgrade, only run this when sysfs node is not present.
    # This means that it's an actual detach rather than a restart.
    if [ -e "${sys_class_net}/${iface}" ]; then
        debug "Link ${iface} still present, skipping configuration removal."
        exit 0
    fi
    debug "Removing configuration for $iface."
    rm -rf "/run/network/$iface" \
       "${unitdir}/70-${iface}.network" \
       "${unitdir}/70-${iface}.network.d" || true
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
