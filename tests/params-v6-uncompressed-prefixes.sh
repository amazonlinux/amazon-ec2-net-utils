#!/bin/bash

# IMDS may report delegated IPv6 prefixes in uncompressed format
# (e.g. fd0a:ffff:1:0:0:0:0:0/80) instead of the more common
# compressed format (e.g. fd0a:ffff:1::/80), while `ip rule` shows
# them in compressed form.  Ensure that we treat them as equivalent.
#
# The test simulates a RENEW6 operation in dhclient.  The behavior
# we're specifically interested in testing is reflected in the
# corresponding ec2dhcp-up-ipv6.sh.out file.  The expected behavior is
# that we do not create or delete any routing rules.  We should be in
# a steady state with the kernel's rules reflecting the same set of v6
# addresses and prefixes as IMDS.
#
# This tests specifically for the issue documented in
# https://github.com/amazonlinux/amazon-ec2-net-utils/issues/68

INTERFACE=eth2
SYSFSDIR=./sys
_TEST_IPV6_ADDRS=(fd02:ffff:eeee:1:2:3:2:1)

. ../ec2net-functions
. ./test-functions

# Specific IMDS responses for this test instance
get_meta() {
    echo "CALLED $FUNCNAME" $@ >&2
    case "$1" in
	subnet-ipv4-cidr-block)
	    echo 10.0.0.0/24
	    ;;
	local-ipv4s)
	    echo 10.0.0.10
	    ;;
	ipv4-prefix)
	    ;;
	ipv6-prefix)
	    echo "fd0a:ffff:eeee:dddd::/80"
            echo "fd0a:ffff:9999:8888:0:0:0:0/80"
	    ;;
	*)
	    echo "unsupported request $1" >&2
	    ;;
    esac
}

function ip() {
    echo "CALLED ${FUNCNAME[0]} $@" >&2
    if [ "${*}" = "-6 rule list" ]; then
	# full rule listing
	cat <<EOF
0:      from all lookup local
32719:  from fd0a:ffff:eeee:dddd::/80 lookup 10002
32720:  from fd0a:ffff:9999:8888::/80 lookup 10002
32765:  from fd02:ffff:eeee:1:2:3:2:1 lookup 10002
32766:  from all lookup main
EOF
    elif [ "${*}" = "-6 rule list from fd02:ffff:eeee:1:2:3:2:1 lookup 10002" ]; then
        echo "32765:  from fd02:ffff:eeee:1:2:3:2:1 lookup 10002"
    elif [ "${*}" = "-6 rule list from fd0a:ffff:eeee:dddd::/80 lookup 10002" ]; then
        echo "32719:  from fd0a:ffff:eeee:dddd::/80 lookup 10002"
    elif [ "${*}" = "-6 rule list from fd0a:ffff:9999:8888:0:0:0:0/80 lookup 10002" ]; then
        echo "32720:  from fd0a:ffff:9999:8888::/80 lookup 10002"
    elif [ "${*}" = "-6 route show table 10002" ]; then
        echo "default via fe80::4:3:2:1 dev eth2 metric 1024 pref medium"
    fi
}

dhclient6_env_up() {
    new_ip6_address=fd02:ffff:eeee:1:2:3:2:1
    interface=$INTERFACE
    new_life_starts=1646337860
    new_max_life=450
    new_starts=1646337860
    reason=RENEW6
    new_dhcp6_client_id=0:1:0:1:29:b3:b6:e9:2:64:bc:f4:29:f9
    new_preferred_life=140
    new_iaid=ef:3b:20:71
    requested_dhcp6_domain_search=1
    new_rebind=112
    requested_dhcp6_fqdn=1
    requested_dhcp6_name_servers=1
    new_dhcp6_server_id=0:3:0:1:2:8f:53:6f:64:ef
    new_renew=70
    new_ip6_prefixlen=128
}

dhclient_env_up() {
    :
}

dhclient_env_down() {
    reason=STOP
    interface=eth1
}
