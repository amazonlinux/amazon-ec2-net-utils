#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the MIT License. See the LICENSE accompanying this file
# for the specific language governing permissions and limitations under
# the License.

. ./common.sh

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

ec2dhcp_config
