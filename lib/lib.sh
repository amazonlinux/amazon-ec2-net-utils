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

# These should be set by the calling program
declare ether
declare unitdir
declare lockdir
declare reload_flag

declare -r imds_endpoints=("http://169.254.169.254/latest" "http://[fd00:ec2::254]/latest")
declare -r imds_token_path="api/token"
declare -r syslog_facility="user"
declare -r syslog_tag="ec2net"
declare -i -r rule_base=10000

# Systemd installs routes with a metric of 1024 by default.  We
# override to a lower metric to ensure that our fully configured
# interfaces are preferred over those in the process of being
# configured.
declare -i -r metric_base=512
declare imds_endpoint imds_token

get_token() {
    # try getting a token early, using each endpoint in
    # turn. Whichever endpoint responds will be used for the rest of
    # the IMDS API calls.  On initial interface setup, we'll retry
    # this operation for up to 30 seconds, but on subsequent
    # invocations we avoid retrying
    local deadline
    deadline=$(date -d "now+30 seconds" +%s)
    local old_opts=$-
    while [ "$(date +%s)" -lt $deadline ]; do
        for ep in "${imds_endpoints[@]}"; do
            set +e
            imds_token=$(curl --max-time 5 --connect-timeout 0.15 -s --fail \
                              -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" ${ep}/${imds_token_path})
            [[ $old_opts = *e* ]] && set -e
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

    get_token

    local url="${imds_endpoint}/meta-data/${key}"
    local meta rc
    while [ $attempts -lt $max_tries ]; do
        meta=$(curl -s --max-time 5 -H "X-aws-ec2-metadata-token:${imds_token}" -f "$url")
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
    get_imds network/interfaces/macs/${mac}/${key} $max_tries
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
    addresses=$(get_iface_imds $mac local-ipv4s | tail -n +2 | sort)
    local drop_in_dir="${unitdir}/70-${iface}.network.d"
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
    if [ -z "$iface" ]; then
        error "${FUNCNAME[0]} called without an interface"
        return 1
    fi
    ! ip -4 addr show dev "$iface" scope global | \
        sed -n -E 's,^.*inet (\S+).*,\1,p' | grep -E -q '^169\.254\.'
}

subnet_supports_ipv6() {
    local iface=$1
    if [ -z "$iface" ]; then
        error "${FUNCNAME[0]} called without an interface"
        return 1
    fi
    ip -6 addr show dev "$iface" scope global | grep -q inet6
}

subnet_prefixroutes() {
    local ether=$1
    local family=${2:-ipv4}
    if [ -z "$ether" ]; then
        err "${FUNCNAME[0]} called without an MAC address"
        return 1
    fi
    case "$family" in
        ipv4)
            get_iface_imds "$ether" "subnet-${family}-cidr-block"
            ;;
        ipv6)
            get_iface_imds "$ether" "subnet-${family}-cidr-blocks"
            ;;
    esac
}

create_rules() {
    local iface=$1
    local device_number=$2
    local network_card=$3
    local family=$4
    local addrs prefixes
    local local_addr_key subnet_pd_key
    local drop_in_dir="${unitdir}/70-${iface}.network.d"
    mkdir -p "$drop_in_dir"

    local -i ruleid=$((device_number+rule_base+100*network_card))

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
    local -i device_number="$2"; test -n "$device_number" || { echo "Invalid device_number at $LINENO" >&2 ; exit 1; }
    local -i network_card="$3"; test -n "$network_card" || { echo "Invalid network_card at $LINENO" >&2 ; exit 1; }
    local ether="$4"; test -n "$ether" || { echo "Invalid ether at $LINENO" >&2 ; exit 1; }
    local cfgfile="$5"; test -n "$cfgfile" || { echo "Invalid cfgfile at $LINENO" >&2 ; exit 1; }

    local cfgdir="${cfgfile}.d"
    local dropin="${cfgdir}/eni.conf"
    local -i metric=$((metric_base+100*network_card+device_number))
    local -i tableid=$((rule_base+100*network_card+device_number))

    mkdir -p "$cfgdir"
    cat <<EOF > "${dropin}.tmp"
# Configuration for ${iface} generated by policy-routes@${iface}.service
[Match]
MACAddress=${ether}
[Network]
DHCP=yes

[DHCPv4]
RouteMetric=${metric}
UseRoutes=true
UseGateway=true

[IPv6AcceptRA]
RouteMetric=${metric}
UseGateway=true

EOF

    cat <<EOF >> "${dropin}.tmp"
[Route]
Table=${tableid}
Gateway=_ipv6ra

EOF
    for dest in $(subnet_prefixroutes "$ether" ipv6); do
        cat <<EOF >> "${dropin}.tmp"
[Route]
Table=${tableid}
Destination=${dest}

EOF
    done

    if subnet_supports_ipv4 "$iface"; then
        # if not in a v6-only network, add IPv4 routes to the private table
        cat <<EOF >> "${dropin}.tmp"
[Route]
Gateway=_dhcp4
Table=${tableid}
EOF
        local dest
        for dest in $(subnet_prefixroutes "$ether" ipv4); do
            cat <<EOF >> "${dropin}.tmp"
[Route]
Table=${tableid}
Destination=${dest}
EOF
        done
    fi


    mv "${dropin}.tmp" "$dropin"
    echo 1
}

add_altnames() {
    local iface=$1
    local ether=$2
    local device_number=$3
    local network_card=$4
    local eni_id
    eni_id=$(get_iface_imds "$ether" interface-id)
    # Interface altnames can also be added using systemd .link files.
    # However, in order to use them, we need to wait until a
    # systemd-networkd reload operation completes and then trigger a
    # udev "move" event.  We avoid that overhead by adding the
    # altnames directly using ip(8).
    if [ -n "$eni_id" ] &&
           ! ip link show dev "$iface" | grep -q -E "altname\s+${eni_id}"; then
        ip link property add dev "$iface" altname "$eni_id" || true
    fi
    local device_number_alt="device-number-${device_number}"
    if [ -n "$network_card" ]; then
        # On instance types that don't support a network-card key, we
        # won't append a value here.  A value of zero would be
        # appropriate, but would be a visible change to the interface
        # configuration on these instance types and could disrupt
        # existing automation.
        device_number_alt="${device_number_alt}.${network_card}"
    fi
    if [ -n "$device_number" ] &&
           ! ip link show dev "$device_number_alt" > /dev/null 2>&1; then
        ip link property add dev "$iface" altname "${device_number_alt}" || true
    fi
}

create_interface_config() {
    local iface=$1
    local device_number=$2
    local network_card=$3
    local ether=$4

    local libdir=/usr/lib/systemd/network
    local defconfig="${libdir}/80-ec2.network"

    local -i retval=0

    local cfgfile="${unitdir}/70-${iface}.network"
    if [ -e "$cfgfile" ]; then
        debug "Using existing cfgfile ${cfgfile}"
        echo $retval
        return
    fi

    debug "Linking $cfgfile to $defconfig"
    mkdir -p "$unitdir"
    ln -s "$defconfig" "$cfgfile"
    retval+=$(create_if_overrides "$iface" "$device_number" "$network_card" "$ether" "$cfgfile")
    add_altnames "$iface" "$ether" "$device_number" "$network_card"
    echo $retval
}

# device-number, which represents the DeviceIndex field in an EC2
# NetworkInterfaceAttachment object, is not guaranteed to have
# propagated to IMDS by the time a hot-plugged interface is visible to
# the instance.  Further complicating things, IMDS returns 0 for the
# device-number before propagation is complete, which is a valid value
# and represents the instance's primary interface.  We cope with this
# by ensuring that the only interface for which we return 0 as the
# device-number is the one whose MAC address matches the instance's
# top-level "mac" field, which is static and guaranteed to be
# available as soon as the instance launches.
_get_device_number() {
    local iface ether default_mac
    iface="$1"
    ether="$2"

    default_mac=$(get_imds mac)

    if [ "$ether" = "$default_mac" ]; then
        echo 0
        return 0
    fi

    local -i maxtries=60 ntries=0
    for (( ntries = 0; ntries < maxtries; ntries++ )); do
        device_number=$(get_iface_imds "$ether" device-number)
        if [ $device_number -ne 0 ]; then
            echo "$device_number"
            return 0
        else
            sleep 0.1
        fi
    done
    error "Unable to identify device-number for $iface after $ntries attempts"
    return 1
}

# print the network-card IMDS value for the given interface
# NOTE: On many instance types, this value is not defined.  This
# function will print the empty string on those instances.  On
# instances where it is defined, it will be a numeric value.
_get_network_card() {
    local iface ether network_card
    iface="$1"
    ether="$2"
    network_card=$(get_iface_imds "$ether" network-card)
    echo ${network_card}
}


# Interfaces get configured with addresses and routes from
# DHCP. Routes are inserted in the main table with metrics based on
# their physical location (slot ID) to ensure deterministic route
# ordering.  Interfaces also get policy routing rules based on source
# address matching and ensuring that all egress traffic with one of
# the interface's IPs (primary or secondary, IPv4 or IPv6, including
# addresses from delegated prefixes) will be routing according to an
# interface-specific routing table.
setup_interface() {
    local iface ether
    local -i device_number network_card
    iface=$1
    ether=$2

    device_number=$(_get_device_number "$iface" "$ether")
    network_card=$(_get_network_card "$iface" "$ether")

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

        changes+=$(create_interface_config "$iface" "$device_number" "$network_card" "$ether")
        for family in 4 6; do
            if [ $device_number -ne 0 ]; then
                # We only create rules for secondary interfaces so
                # external tools that modify the main route table can
                # still communicate with the host's primary IPs.  For
                # example, considering a host with address 10.1.2.3 on
                # ens5 (device-number-0) and a container communicating
                # on a docker0 bridge interface, the expectation is
                # that the container can communicate with 10.1.2.3 in
                # both directions.  If we install policy rules,
                # they'll redirect the return traffic out ens5 rather
                # than docker0, effectively blackholing it.
                # https://github.com/amazonlinux/amazon-ec2-net-utils/issues/97
                changes+=$(create_rules "$iface" "$device_number" "$network_card" $family)
            fi
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
    rm -f "${lockdir}/${iface}"
    if rmdir "$lockdir" 2> /dev/null; then
        if [ -e "$reload_flag" ]; then
            rm -f "$reload_flag" 2> /dev/null
            networkctl reload
            info "Reloaded networkd"
        else
            debug "No networkd reload needed"
        fi
    else
        debug "Deferring networkd reload to another process"
    fi
}


register_networkd_reloader() {
    local -i registered=1 cnt=0
    local -i max=10000
    local -r lockfile="${lockdir}/${iface}"
    local old_opts=$-

    # Disable -o errexit in the following block so we can capture
    # nonzero exit codes from a redirect without considering them
    # fatal errors
    set +e
    while [ $cnt -lt $max ]; do
        cnt+=1
        mkdir -p "$lockdir"
        trap 'debug "Called trap" ; maybe_reload_networkd' EXIT
        # If the redirect fails, most likely because the target file
        # already exists and -o noclobber is in effect, $? will be set
        # nonzero.  If it succeeds, it is set to 0
        echo $$ > "${lockfile}"
        registered=$?
        [ $registered -eq 0 ] && break
        sleep 0.1
        if (( $cnt % 100 == 0 )); then
            info "Unable to lock ${iface} after ${cnt} tries."
        fi
    done
    # re-enable -o errexit if it had originally been set
    [[ $old_opts = *e* ]] && set -e

    # If registered is still nonzero when we get here, we have failed
    # to create the lock.  Log this and exit.
    if [ $registered -ne 0 ]; then
        local msg="Unable to lock configuration for ${iface}."
        error "$(printf "%s Check pid %d", "$msg", "$(cat "${lockfile}")")"
        exit 1
    fi
}
