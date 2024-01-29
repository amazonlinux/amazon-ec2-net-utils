#!/bin/bash

v=$(dpkg-parsechangelog -S Version -l debian/changelog | sed -E 's,^\S:,,; s,-\S+,,')
make scratch-sources version=${v}
DEBEMAIL=nobody@localhost DEBFULLNAME="test runner" dch -v "${v}-1" -b -D unstable "scratch build"
mv ../amazon-ec2-net-utils-${v}.tar.gz ../amazon-ec2-net-utils_${v}.orig.tar.gz
dpkg-buildpackage -uc -us
