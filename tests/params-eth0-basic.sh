#!/bin/bash

# Basic eth0 configuration.  Single IPv4 address, no IPv6 configured.

INTERFACE=eth0
SYSFSDIR=./sys

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
	    echo "192.168.10.10"
	    ;;
	*)
	    echo "unsupported request $1" >&2
	    ;;
    esac
}
