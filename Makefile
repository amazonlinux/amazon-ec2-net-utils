# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the MIT License. See the LICENSE accompanying this file
# for the specific language governing permissions and limitations under
# the License.

pkgname=amazon-ec2-net-utils
version?=$(shell git describe --dirty)

prefix?=/usr/local
sysconfdir=${DESTDIR}/etc
sbindir=${DESTDIR}/${prefix}/sbin
systemddir=${DESTDIR}/${prefix}/lib/systemd
udevdir=${DESTDIR}/${prefix}/lib/udev/rules.d
mandir=${DESTDIR}/${prefix}/share/man

# We support installation of some init-system dependent files, and
# default to systemd.
init=systemd

define install-file
test -d $2 || install -d -o root -g root -m755 $2
install -o root -g root -m644 $1 $2
endef

define install-exe
test -d $2 || install -d -o root -g root -m755 $2
install -o root -g root -m755 $1 $2
endef

sources:
	git archive --format tar.gz --prefix ${pkgname}-${version}/ HEAD > ../${pkgname}-${version}.tar.gz

install:
	${call install-exe,ec2dhcp.sh,${sysconfdir}/dhcp/dhclient.d}
	${call install-file,ixgbevf.conf,${sysconfdir}/modprobe.d}
	${call install-file,ec2net-functions,${sysconfdir}/sysconfig/network-scripts}
	${call install-exe,ec2net.hotplug,${sysconfdir}/sysconfig/network-scripts}
	${call install-file,\
	  53-ec2-network-interfaces.rules.${init},\
	  ${udevdir}}
	mv ${udevdir}/53-ec2-network-interfaces.rules.${init} \
	  ${udevdir}/53-ec2-network-interfaces.rules
	${call install-file,75-persistent-net-generator.rules,${udevdir}}
	${call install-file,ec2net-ifup@.service,${systemddir}/system}
	${call install-file,ec2net-scan.service,${systemddir}/system}
	${call install-file,rule_generator.functions,${DESTDIR}/${prefix}/lib/udev}
	${call install-file,write_net_rules,${DESTDIR}/${prefix}/lib/udev}
	${call install-exe,ec2ifdown,${sbindir}}
	${call install-exe,ec2ifscan,${sbindir}}
	${call install-exe,ec2ifup,${sbindir}}
	${call install-file,ec2ifscan.8,${mandir}/man8}
	${call install-file,ec2ifup.8,${mandir}/man8}
	ln -fs ec2ifup.8 ${mandir}/man8/ec2ifdown.8
