Name:    amazon-ec2-net-utils
Version: 2.2.0
Release: 1%{?dist}
Summary: utilities for managing network interfaces in Amazon EC2

License: Apache 2.0
URL:     https://github.com/aws/amazon-ec2-net-utils/
Source0: amazon-ec2-net-utils-%{version}.tar.gz

BuildArch: noarch

BuildRequires: make
Requires: systemd-networkd, udev, curl, iproute
Requires: (systemd-resolved or systemd < 250)

%description
amazon-ec2-net-utils-ng provides udev integration and helper utilities
to manage network configuration in the Amazon EC2 cloud environment

%prep

%autosetup -n %{name}-%{version}

%install
make install DESTDIR=%{buildroot} PREFIX=/usr

%files
%{_sysconfdir}/sysctl.d/90-ipv6-dad.conf
/usr/lib/systemd/network/80-ec2.network
/usr/lib/systemd/system/policy-routes@.service
/usr/lib/systemd/system/refresh-policy-routes@.service
/usr/lib/systemd/system/refresh-policy-routes@.timer

/usr/lib/udev/rules.d/98-eni.rules
/usr/lib/udev/rules.d/99-vpc-policy-routes.rules
%{_bindir}/setup-policy-routes
%{_datarootdir}/amazon-ec2-net-utils/lib.sh

%post

setup_policy_routes() {
    local iface node
    for node in /sys/class/net/*; do
	iface=$(basename $node)
	unset ID_NET_DRIVER
	eval $(udevadm info --export --query=property /sys/class/net/$iface)
	case $ID_NET_DRIVER in
	    ena|ixgbevf|vif)
		systemctl restart policy-routes@${iface}.service
		systemctl start refresh-policy-routes@${iface}.timer
		;;
	esac
    done
}

if [ $1 -eq 1 ]; then
    # This is a new install
    systemctl enable systemd-networkd.service
    systemctl enable systemd-resolved.service
    systemctl disable NetworkManager-wait-online.service
    systemctl disable NetworkManager.service
    [ -f /etc/resolv.conf ] && mv /etc/resolv.conf /etc/resolv.conf.old
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    if [ -d /run/systemd/system ]; then
	systemctl stop NetworkManager.service
	systemctl start systemd-networkd.service
	setup_policy_routes
	systemctl start systemd-resolved.service
    fi
elif [ $1 -gt 1 ]; then
    # This is an upgrade, there's less setup to do, but we do want to
    # ensure we apply any configuration introduced by the new version
    systemctl daemon-reload
    setup_policy_routes
fi

%changelog

