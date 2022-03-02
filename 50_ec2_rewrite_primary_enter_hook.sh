# -*-Shell-script-*-

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the MIT License. See the LICENSE accompanying this file
# for the specific language governing permissions and limitations under
# the License.

## NB: This is not a standalone script, but rather a script fragment
## that is sourced by /sbin/dhclient-script.  It runs within the same
## process, which means that it shares state with that process and
## terminates that process if it exits.

# shellcheck source=./ec2net-functions-lib
. "${EC2_INCLUDEDIR:-/etc/sysconfig/network-scripts}/ec2net-functions-lib"

ec2_rewrite_primary_enter_hook() {

    # Explicit local assignment of variables inherited from the dhclient
    # environment. By referencing the originals, we could modify the
    # behavior of the dhcp lease processing, but it's not something we
    # do at the moment.
    local interface="${interface}"
    local reason="${reason}"
    local new_network_number="${new_network_number}"
    local new_ip_address="${new_ip_address}"
    local new_routers="${new_routers}"
    local new_subnet_mask="${new_subnet_mask}"

    # eth0 configs are statically configured on Amazon Linux
    if [ "${interface}" == "eth0" ]; then
        return
    fi

    if [ "$reason" != BOUND ] &&
           [ "$reason" != REBOOT ]; then
        return
    fi

    local HWADDR
    local SYSFSDIR=${SYSFSDIR:-/sys}
    HWADDR=$(cat "${SYSFSDIR}"/class/net/${interface}/address 2>/dev/null)
    [ -z "$HWADDR" ] && return

    local EC2_ETCDIR=${EC2_ETCDIR:-/etc}
    local config_file="$EC2_ETCDIR/sysconfig/network-scripts/ifcfg-${interface}"

    if ! should_sync_interface "${interface}" "${config_file}"; then
        return
    fi

    local network="$new_network_number"
    local gateway="$new_routers"
    local route_file="$EC2_ETCDIR/sysconfig/network-scripts/route-${interface}"
    local route_dest="${network}/${new_subnet_mask}"

    local RTABLE
    RTABLE=$(get_interface_rt_table "$interface")

    [ -z "$new_ip_address" ] && { logger --tag ec2net "DHCP lease did not set new_ip_address" ; return 1; }
    [ -z "$gateway" ] && { logger --tag ec2net "DHCP lease did not set gateway" ; return 1; }
    [ -z "$route_dest" ] && { logger --tag ec2net "DHCP lease did not set route_dest" ; return 1; }

    if subnet_supports_ipv4 "$new_ip_address"; then
        cat << EOF > ${route_file}
default via ${gateway} dev ${interface} table ${RTABLE}
${route_dest} dev ${interface} proto kernel scope link src ${new_ip_address} table ${RTABLE}
EOF
        if should_use_mainroutetable "$config_file"; then
            logger --tag ec2net "[dhclient] adding default route to main table for ${interface} metric ${RTABLE}"
            cat << EOF >> ${route_file}
default via ${gateway} dev ${interface} metric ${RTABLE}
EOF
        fi
    fi
}

ec2_rewrite_primary_enter_hook
