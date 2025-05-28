#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may
# not use this file except in compliance with the License. A copy of the
# License is located at
#
#      http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

set -eCo pipefail

libdir=${LIBDIR_OVERRIDE:-/usr/share/amazon-ec2-net-utils}

. "${libdir}/lib.sh"

if [ -s /etc/hostname ]; then
    info "Static hostname is already set - not modifying existing hostname"
    exit 0
fi

get_token
hostname=$(get_imds local-hostname)

if [ -n "$hostname" ]; then
    info "Setting hostname to ${hostname} retrieved from IMDS"
    hostnamectl hostname ${hostname}
else
    error "Unable to retrieve hostname from IMDS - aborting"
    exit 1
fi
