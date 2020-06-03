#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the MIT License. See the LICENSE accompanying this file
# for the specific language governing permissions and limitations under
# the License.

INTERFACE="${interface}"
PREFIX="${new_prefix}"
. /etc/sysconfig/network-scripts/ec2net-functions

ec2dhcp_config() {
  rewrite_rules
  # This can be done asynchronously, to save boot time
  # since it doesn't affect the primary address
  rewrite_aliases &
}

ec2dhcp_restore() {
  remove_aliases
  remove_rules
}
