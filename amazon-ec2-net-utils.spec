Name:    amazon-ec2-net-utils
Version: 2.0.0
Release: 1%{?dist}
Summary: utilities for managing network interfaces in Amazon EC2

License: Apache 2.0
URL:     https://github.com/aws/amazon-ec2-net-utils/
Source0: amazon-ec2-net-utils-%{version}.tar.xz

BuildArch: noarch

BuildRequires: make
Requires: systemd-networkd, udev, curl, iproute

%description
amazon-ec2-net-utils-ng provides udev integration and helper utilities
to manage network configuration in the Amazon EC2 cloud environment

%prep

%autosetup -n %{name}-%{version}

%install
make install DESTDIR=%{buildroot} PREFIX=/usr

%files
%{_sysconfdir}/sysctl.d/90-ipv6-dad.conf
%{_sysconfdir}/systemd/network/80-ec2.network
%{_sysconfdir}/systemd/system/policy-routes@.service
%{_sysconfdir}/systemd/system/refresh-policy-routes@.service
%{_sysconfdir}/systemd/system/refresh-policy-routes@.timer

%{_sysconfdir}/udev/rules.d/98-eni.rules
%{_sysconfdir}/udev/rules.d/99-vpc-policy-routes.rules
%{_bindir}/setup-policy-routes

%post

setup_policy_routes() {
    local iface node
    for node in /sys/class/net/*; do
	iface=$(basename $node)
	unset ID_NET_DRIVER
	eval $(udevadm info --export --query=property /sys/class/net/$iface)
	case $ID_NET_DRIVER in
	    ena|ixgbevf|vif)
		systemctl start policy-routes@${iface}.service
		systemctl start refresh-policy-routes@${iface}.timer
		;;
	    *)
		echo "Skipping $iface with driver $ID_NET_DRIVER"
		;;
	esac
    done
}

if [ $1 == 1 ]; then
    systemctl enable systemd-networkd.service
    systemctl enable systemd-resolved.service
    systemctl disable NetworkManager-wait-online.service
    systemctl disable NetworkManager.service
    [ -f /etc/resolv.conf ] && mv /etc/resolv.conf /etc/resolv.conf.old
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    if [ -d /run/systemd ]; then
	systemctl stop NetworkManager.service
	systemctl start systemd-networkd.service
	setup_policy_routes
	systemctl start systemd-resolved.service
    fi
fi

%changelog

