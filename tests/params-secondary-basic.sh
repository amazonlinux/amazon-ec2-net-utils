#!/bin/bash

# Test a secondary interface (i.e. not eth0) with a single local IPv4
# and a single IPv6 address configured.

INTERFACE=eth1
SYSFSDIR=./sys
_TEST_IPV6_ADDRS=(fd01:ffff:eeee:dddd:4:3:2:1)

. ../ec2net-functions
. ./test-functions

# Specific IMDS responses for this test instance
get_meta() {
    echo "CALLED $FUNCNAME" $@ >&2
    case "$1" in
	subnet-ipv4-cidr-block)
	    echo "192.168.10.0/24"
	    ;;
	local-ipv4s)
	    echo "192.168.10.21"
	    ;;
	ipv4-prefix|ipv6-prefix)
	    ;;
	*)
	    echo "unsupported request $1" >&2
	    ;;
    esac
}
