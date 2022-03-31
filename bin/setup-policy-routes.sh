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

declare ether
declare -r runtimedir="/run/systemd/network"
declare -r imds_endpoints=("http://169.254.169.254/latest" "http://[fd00:ec2::254]/latest")
declare -r imds_token_path="api/token"
declare -r syslog_facility="user"
declare -r syslog_tag="ec2net"
declare imds_endpoint imds_token

get_token() {
    # try getting a token early, using each endpoint in
    # turn. Whichever endpoint responds will be used for the rest of
    # the IMDS API calls.  On initial interface setup, we'll retry
    # this operation for up to 30 seconds, but on subsequent
    # invocations we avoid retrying
    local deadline
    deadline=$(date -d "now+30 seconds" +%s)
    while [ "$(date +%s)" -lt $deadline ]; do
        for ep in "${imds_endpoints[@]}"; do
            set +e
            imds_token=$(curl --connect-timeout 0.15 -s --fail \
                              -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" ${ep}/${imds_token_path})
            set -e
            if [ -n "$imds_token" ]; then
                debug "Got IMDSv2 token from ${ep}"
                imds_endpoint=$ep
                return
            fi
        done
        if [ ! -v EC2_IF_INITIAL_SETUP ]; then
            break
        fi
        sleep 0.5
    done
}

log() {
    local priority
    priority=$1 ; shift
    logger --priority "${syslog_facility}.${priority}" --tag "$syslog_tag" "$@"
}

debug() {
    log debug "$@"
}

info() {
    log info "$@"
}

error() {
    log err "$@"
}

get_meta() {
    local key=$1
    local max_tries=${2:-10}
    declare -i attempts=0
    debug "[get_meta] Querying IMDS for ${key}"

    local url="${imds_endpoint}/meta-data/${key}"
    local meta rc
    while [ $attempts -lt $max_tries ]; do
        meta=$(curl -s -H "X-aws-ec2-metadata-token:${imds_token}" -f "$url")
        rc=$?
        if [ $rc -eq 0 ]; then
            echo "$meta"
            return 0
        fi
        attempts+=1
    done
    return 1
}

get_imds() {
    local key=$1
    local max_tries=${2:-10}
    get_meta $key $max_tries
}

get_iface_imds() {
    local mac=$1
    local key=$2
    local max_tries=${3:-10}
    get_imds network/interfaces/macs/${mac}/${key} $max_tries | sort
}

flush_rules() {
    local ruleid=$1
    local family=${2:-4}
    info "Flushing IPv${family} rule ID ${ruleid}"
    while [ -n "$(ip -${family} rule show pref $ruleid)" ]; do
            ip -${family} rule del pref $ruleid
    done
}

_install_and_reload() {
    local src=$1
    local dest=$2
    if [ -e "$dest" ]; then
        if [ "$(md5sum < $dest)" = "$(md5sum < $src)" ]; then
            # The config is unchanged since last run. Nothing left to do:
            rm "$src"
            echo 0
        else
            # The file content has changed, we need to reload:
            mv "$src" "$dest"
            echo 1
        fi
        return
    fi

    # If we're here then we're creating a new config file
    if [ "$(stat --format=%s $src)" -gt 0 ]; then
        mv "$src" "$dest"
        echo 1
        return
    fi
    rm "$src"
    echo 0
}

create_ipv4_aliases() {
    local iface=$1
    local mac=$2
    local addresses
    subnet_supports_ipv4 "$iface" || return 0
    addresses=$(get_iface_imds $mac local-ipv4s | tail -n +2)
    local drop_in_dir="${runtimedir}/70-${iface}.network.d"
    mkdir -p "$drop_in_dir"
    local file="$drop_in_dir/ec2net_alias.conf"
    local work="${file}.new"
    touch "$work"

    for a in $addresses; do
        cat <<EOF >> "$work"
[Address]
Address=${a}/32
AddPrefixRoute=false
EOF
    done
    _install_and_reload "$work" "$file"
}

subnet_supports_ipv4() {
    local iface=$1
    test -n "$iface" || return 1
    ip -4 addr show dev "$iface" scope global | sed -n -E 's,^.*inet (\S+).*,\1,p' | grep -E -q -v '^169\.254\.'
}

subnet_supports_ipv6() {
    local iface=$1
    test -n "$iface" || return 1
    ip -6 addr show dev "$iface" scope global | grep -q inet6
}

create_rules() {
    local iface=$1
    local ruleid=$2
    local family=$3
    local addrs prefixes
    local local_addr_key subnet_pd_key
    local drop_in_dir="${runtimedir}/70-${iface}.network.d"
    mkdir -p "$drop_in_dir"
    case $family in
        4)
            if ! subnet_supports_ipv4 $iface; then
                return 0
            fi
            local_addr_key=local-ipv4s
            subnet_pd_key=ipv4-prefix
            ;;
        6)
            if ! subnet_supports_ipv6 $iface; then
                return 0
            fi
            local_addr_key=ipv6s
            subnet_pd_key=ipv6-prefix
            ;;
        *)
            error "unable to determine protocol"
            return 1
            ;;
    esac

    # We'd like to retry here, but we can't distinguish between an
    # IMDS failure, a propagation delay, or a legitimately empty
    # response.
    addrs=$(get_iface_imds ${ether} ${local_addr_key} || true)

    # don't fail or retry prefix retrieval. IMDS currently returns an
    # error, rather than an empty response, if no prefixes are
    # assigned, so we are unable to distinguish between a service
    # error and a successful but empty response
    prefixes=$(get_iface_imds ${ether} ${subnet_pd_key} 1 || true)

    local source
    local file="$drop_in_dir/ec2net_policy_${family}.conf"
    local work="${file}.new"
    touch "$work"

    for source in $addrs $prefixes; do
        cat <<EOF >> "$work"
[RoutingPolicyRule]
From=${source}
Priority=${ruleid}
Table=${ruleid}
EOF
    done
    _install_and_reload "$work" "$file"
}

create_if_overrides() {
    local iface="$1"; test -n "$iface" || { echo "Invalid iface at $LINENO" >&2 ; exit 1; }
    local tableid="$2"; test -n "$tableid" || { echo "Invalid tableid at $LINENO" >&2 ; exit 1; }
    local ether="$3"; test -n "$ether" || { echo "Invalid ether at $LINENO" >&2 ; exit 1; }
    local cfgfile="$4"; test -n "$cfgfile" || { echo "Invalid cfgfile at $LINENO" >&2 ; exit 1; }
    local cfgdir="${cfgfile}.d"
    local dropin="${cfgdir}/eni.conf"
    mkdir -p "$cfgdir"
    if [ $tableid -eq 0 ]; then
        # primary, just match on MAC
        cat <<EOF > "${dropin}.tmp"
# Configuration for ${iface} generated by policy-routes@${iface}.service
[Match]
MACAddress=${ether}
EOF
    else
        # secondary. match on MAC and set up private route tables
        cat <<EOF > "${dropin}.tmp"
# Configuration for ${iface} generated by policy-routes@${iface}.service
[Match]
MACAddress=${ether}
[DHCPv4]
RouteTable=${tableid}
[Route]
Table=${tableid}
Gateway=_ipv6ra
[IPv6AcceptRA]
RouteTable=${tableid}
[Route]
Gateway=_dhcp4
Metric=${tableid}
Destination=0.0.0.0/0
Table=main
[Route]
Gateway=_ipv6ra
Metric=${tableid}
Destination=::/0
Table=main
EOF
    fi
    mv "${dropin}.tmp" "$dropin"
    echo 1
}

add_altname() {
    local iface=$1
    local ether=$2
    local eni_id
    eni_id=$(get_iface_imds "$ether" interface-id)
    if [ -n "$eni_id" ] &&
           ! ip link show dev "$iface" | grep -q -E "altname\s+${eni_id}"; then
        ip link property add dev "$iface" altname "$eni_id" || true
    fi
}

create_interface_config() {
    local iface=$1
    local ifid=$2
    local ether=$3

    local libdir=/usr/lib/systemd/network
    local defconfig="${libdir}/80-ec2.network"

    local -i retval=0

    local cfgfile="${runtimedir}/70-${iface}.network"
    if [ -e "$cfgfile" ]; then
        info "Using existing cfgfile ${cfgfile}"
        echo $retval
        return
    fi

    info "Linking $cfgfile to $defconfig"
    mkdir -p "$runtimedir"
    ln -s "$defconfig" "$cfgfile"
    retval+=$(create_if_overrides "$iface" "$ifid" "$ether" "$cfgfile")
    add_altname "$iface" "$ether"
    echo $retval
}

# The primary interface is configured to use the 'main' route table,
# secondary interfaces get a private route table for both IPv4 and v6
setup_interface() {
    local iface ether
    iface=$1
    ether=$2

    # Newly provisioned resources (new ENI attachments) take some
    # time to be fully reflected in IMDS. In that case, we poll
    # for a period of time to ensure we've captured all the
    # sources needed for policy routing.  When refreshing an
    # existing ENI attachment's configuration, we skip the
    # polling.
    local -i deadline
    deadline=$(date -d "now+30 seconds" +%s)
    while [ "$(date +%s)" -lt $deadline ]; do
        local -i changes=0
        local -i index ruleid
        index=$(echo $iface | tr -d a-z)
        [ -n "$index" ] || { error "Unable to get index of $iface" ; exit 2; }
        ruleid=$((index+10000))
        mkdir -p /run/network/$iface
        echo $ruleid > /run/network/$iface/pref

        changes+=$(create_interface_config "$iface" "$ruleid" "$ether")
        for family in 4 6; do
            changes+=$(create_rules "$iface" "$ruleid" $family)
        done
        changes+=$(create_ipv4_aliases $iface $ether)

        if [ ! -v EC2_IF_INITIAL_SETUP ] ||
               [ "$changes" -gt 0 ]; then
            break
        fi
    done
    echo $changes
}

# All instances of this process that may reconfigure networkd register
# themselves as such. When exiting, they'll reload networkd only if
# they're the registered process running.
maybe_reload_networkd() {
    rm -f /run/setup-policy-routes/$$
    if rmdir /run/setup-policy-routes/ 2> /dev/null; then
        if [ -e /run/policy-routes-reload-networkd ]; then
            rm -f /run/policy-routes-reload-networkd 2> /dev/null
            networkctl reload
            info "Reloaded networkd"
        else
            info "No networkd reload needed"
        fi
    else
        info "Deferring networkd reload to another process"
    fi
}

register_networkd_reloader() {
    local -i registered=1
    while [ $registered -ne 0 ]; do
        mkdir -p /run/setup-policy-routes/
        trap 'debug "Called trap" ; maybe_reload_networkd' EXIT
        touch /run/setup-policy-routes/$$
        registered=$?
    done
}

iface="$1"
[ -n "$iface" ] || { error "Invocation error"; exit 1; }

get_token

case "$2" in
stop)
    # Note that we can't rely on IMDS or on local state
    # (e.g. interface configuration) here, since the interface may
    # have already been detached from the instance
    if [ ! -e "/run/network/$iface/pref" ]; then
        exit 0
    fi

    register_networkd_reloader
    ruleid=$(cat /run/network/$iface/pref)
    test -n "$ruleid"
    info "Stopping $iface. Will remove rule $ruleid"
    for family in 4 6; do
        flush_rules $ruleid $family
    done
    rm -rf "/run/network/$iface"
    rm -fr "${runtimedir}/70-${iface}.network" "${runtimedir}/70-${iface}.network.d"
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
