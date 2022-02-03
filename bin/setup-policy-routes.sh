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
    debug "[get_meta] Querying IMDS for ${key}"

    local url="${imds_endpoint}/meta-data/${key}"
    curl -s -H "X-aws-ec2-metadata-token:${imds_token}" -f "$url"
}

get_imds() {
    local key=$1
    get_meta $key
}

get_iface_imds() {
    local mac=$1
    local key=$2
    get_imds network/interfaces/macs/${mac}/${key} | sort
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
	    local_addr_key=local-ipv4s
	    subnet_pd_key=ipv4-prefix
	    ;;
	6)
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
    prefixes=$(get_iface_imds ${ether} ${subnet_pd_key} || true)

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

create_interface_config() {
    local iface=$1
    local tableid=$2
    local ether=$3
    local metric=${4:-1024}
    local tablename=$tableid

    local usedns=no
    local usentp=no
    local usehostname=no

    if [ "$tableid" = "0" ]; then
        # This is the "primary" interface
        tablename=main
        usedns=yes
        usentp=yes
        usehostname=yes
    fi
    local cfgfile="${runtimedir}/70-${iface}.network"
    if [ -e "$cfgfile" ]; then
	info "Using existing cfgfile ${cfgfile}"
	echo 0
	return
    fi

    info "Creating $cfgfile"
    mkdir -p "$runtimedir"
    cat <<EOF > "$cfgfile"
[Match]
Driver=ena ixgbevf vif
MACAddress=${ether}

[Link]
MTUBytes=9001

[Network]
DHCP=yes
IPv6DuplicateAddressDetection=0
LLMNR=no

[DHCPv4]
RouteTable=${tableid}
RouteMetric=${metric}
UseHostname=${usehostname}
UseDNS=${usedns}
UseNTP=${usentp}

[DHCPv6]
UseHostname=${usehostname}
UseDNS=${usedns}
UseNTP=${usentp}
RouteMetric=${metric}
WithoutRA=solicit

[Route]
Gateway=_ipv6ra
Table=${tablename}
Metric=${metric}

[IPv6AcceptRA]
RouteTable=${tableid}
EOF

    echo 1
}

# The primary interface is configured to use the 'main' route table,
# secondary interfaces get a private route table for both IPv4 and v6
setup_interface() {
    local iface ether type
    iface=$1
    ether=$2
    type=$3

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
	if [ "$type" = primary ]; then
	    changes+=$(create_interface_config "$iface" 0 "$ether" 512)
	else
	    local -i index ruleid
	    index=$(cat /sys/class/net/${iface}/ifindex)
	    [ -n "$index" ] || { error "Unable to get index of $iface" ; exit 2; }
	    ruleid=$((index+10000))
	    mkdir -p /run/network/$iface
	    echo $ruleid > /run/network/$iface/pref

	    changes+=$(create_interface_config "$iface" "$ruleid" "$ether")
	    for family in 4 6; do
		changes+=$(create_rules "$iface" "$ruleid" $family)
	    done
	fi
	changes+=$(create_ipv4_aliases $iface $ether)

	if [ ! -v EC2_IF_INITIAL_SETUP ] ||
	   [ "$changes" -gt 0 ]; then
	    break
	fi
    done
    echo $changes
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

    ruleid=$(cat /run/network/$iface/pref)
    test -n "$ruleid"
    info "Stopping $iface. Will remove rule $ruleid"
    for family in 4 6; do
	flush_rules $ruleid $family
    done
    rm -rf "/run/network/$iface"
    rm -fr "${runtimedir}/70-${iface}.network" "${runtimedir}/70-${iface}.network.d"
    ;;
*)
    while [ ! -e "/sys/class/net/${iface}" ]; do
	debug  "Waiting for sysfs node to exist"
	sleep 0.1
    done
    info "Starting configuration for $iface"
    debug /lib/systemd/systemd-networkd-wait-online -i "$iface"
    /lib/systemd/systemd-networkd-wait-online -i "$iface"
    ether=$(cat /sys/class/net/${iface}/address)
    imds_ether=$(get_imds mac)
    [ -n "$ether" ] || { error "Unable to identify MAC address for $iface" ; exit 2; }
    [ -n "$imds_ether" ] || { error "Unable to get MAC address from IMDS for $iface" ; exit 2; }

    declare -i changes=0
    # Ideally we'd use the device-number interface property from IMDS,
    # but interface details take some time to propagate, and IMDS
    # reports 0 for the device-number prior to propagation...
    if [ "$ether" = "$imds_ether" ]; then
	info "Configuring $iface as primary"
	# We don't give the "primary" interface a custom route table,
	# but do override its route metric to ensure that it is
	# preferred over any other route that might appear in the main
	# table:
	changes+=$(setup_interface $iface $ether primary)
    else
	changes+=$(setup_interface $iface $ether secondary)
    fi
    if [ $changes -gt 0 ]; then
	info "Reloading networkd"
	networkctl reload
    fi

    ;;
esac

exit 0
