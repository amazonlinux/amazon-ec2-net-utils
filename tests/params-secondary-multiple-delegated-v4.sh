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

dhclient6_env_up() {
    :
}

dhclient_env_up() {
    requested_host_name=1
    new_host_name=ip-10-0-0-192
    new_subnet_mask=255.255.255.0
    new_domain_name=us-west-2.compute.internal
    requested_time_offset=1
    requested_classless_static_routes=1
    new_next_server=0.0.0.0
    new_ip_address=10.0.0.192
    new_network_number=10.0.0.0
    interface=eth1
    requested_ntp_servers=1
    reason=REBOOT
    requested_domain_search=1
    new_expiry=1646262563
    PATH=/bin:/usr/bin:/sbin
    new_dhcp_lease_time=3600
    pid=1876
    new_dhcp_server_identifier=10.0.0.1
    PWD=/etc/sysconfig/network-scripts
    requested_subnet_mask=1
    new_routers=10.0.0.1
    requested_nis_domain=1
    new_interface_mtu=9001
    requested_domain_name=1
    new_domain_name_servers=10.0.0.2
    SHLVL=1
    requested_domain_name_servers=1
    new_dhcp_message_type=5
    requested_broadcast_address=1
    new_broadcast_address=10.0.0.255
    requested_routers=1
    requested_interface_mtu=1
    requested_nis_servers=1
}

dhclient_env_down() {
    reason=STOP
    interface=eth1
}