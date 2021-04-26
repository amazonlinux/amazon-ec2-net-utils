#!/bin/bash

# Test a secondary interface (i.e. not eth0) with a multiple IPv4 and
# v6 addresses configured, including delegated prefixes.

INTERFACE=eth2
SYSFSDIR=./sys
_TEST_IPV6_ADDRS=(fd01:ffff:eeee:5:4:3:2:1 fd01:ffff:eeee:5:4:3:2:2)

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
	    echo "192.168.10.22"
	    echo "192.168.10.23"
	    ;;
	ipv4-prefix)
	    echo "172.16.1.0/24"
	    ;;
	ipv6-prefix)
	    echo "fd0a:1234:1234:1234::/64"
	    ;;
	*)
	    echo "unsupported request $1" >&2
	    ;;
    esac
}
