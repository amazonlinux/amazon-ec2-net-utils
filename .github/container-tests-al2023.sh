#!/bin/bash

set -euo pipefail

make unit-test

v=$(rpmspec -q --qf "%{version}" amazon-ec2-net-utils.spec)
make scratch-sources version=${v}
mv ../amazon-ec2-net-utils-${v}.tar.gz .
rpmbuild --define "_sourcedir $PWD" -bb amazon-ec2-net-utils.spec
