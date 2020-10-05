#!/bin/bash

# Test a secondary interface (i.e. not eth0) with a single delegated IPv6 prefix.

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
	    echo "fd0a:ffff::/80"
	    ;;
	*)
	    echo "unsupported request $1" >&2
	    ;;
    esac
}
