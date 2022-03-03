#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the MIT License. See the LICENSE accompanying this file
# for the specific language governing permissions and limitations under
# the License.

. ./common.sh
# test params files should define a dhclient environment

if command -v dhclient6_env_up > /dev/null 2>&1; then
    dhclient6_env_up
    . ../ec2dhcp.sh

    # sourcing ec2dhcp.sh leads to sourcing ec2net-functions again, which
    # undoes some of the overrides we installed, so we need to source
    # common.sh again:
    . ./common.sh

    ec2dhcp_config
fi
