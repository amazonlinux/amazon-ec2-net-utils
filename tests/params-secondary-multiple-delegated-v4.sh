#!/bin/bash

# Test a secondary interface (i.e. not eth0) with multiple delegated IPv4 prefixes.

INTERFACE=eth2
SYSFSDIR=./sys

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
	    echo "192.168.0.0/24"
	    echo "192.168.1.0/24"
	    ;;
	ipv6-prefix)
	    ;;
	*)
	    echo "unsupported request $1" >&2
	    ;;
    esac
}
