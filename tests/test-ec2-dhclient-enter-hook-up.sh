#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the MIT License. See the LICENSE accompanying this file
# for the specific language governing permissions and limitations under
# the License.

. ./common.sh
dhclient_env_up

. ../50_ec2_rewrite_primary_enter_hook.sh

