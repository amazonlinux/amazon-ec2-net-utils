%if 0%{?amzn} >= 2 || 0%{?fedora} >= 17 || 0%{?rhel} >= 7
%global systemd 1
%else
%global systemd 0
%endif

Name:      amazon-ec2-net-utils
Summary:   A set of network tools for managing ENIs
Version:   1.4
Release:   2%{?dist}
License:   MIT and GPLv2
Group:     System Tools
Source0:   53-ec2-network-interfaces.rules.systemd
Source1:   53-ec2-network-interfaces.rules.upstart
Source2:   75-persistent-net-generator.rules
Source3:   ec2net-functions
Source4:   ec2net.hotplug
Source5:   ec2ifup
Source6:   ec2ifdown
Source7:   ec2dhcp.sh
Source8:   ec2ifup.8
Source9:   ec2ifscan
Source10:  ec2ifscan.8
Source11:  ixgbevf.conf
Source12:  elastic-network-interfaces.conf
Source13:  ec2net-scan.service
Source14:  write_net_rules
Source15:  rule_generator.functions
Source16:  ec2net-ifup@.service

URL:       https://github.com/aws/amazon-ec2-net-utils
BuildArch: noarch
Requires:  curl
Requires:  iproute
%if %{systemd}
%{?systemd_requires}
BuildRequires: systemd-units
Requires: systemd-units
%endif # systemd
Requires: dhclient
Provides: ec2-net-utils
BuildRoot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

%description
amazon-ec2-net-utils contains a set of utilities for managing elastic network
interfaces.

%prep

%build

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/udev/rules.d/
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/network-scripts/
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/dhcp/dhclient.d/
mkdir -p $RPM_BUILD_ROOT%{_mandir}/man8/

install -m644 %{SOURCE2} $RPM_BUILD_ROOT%{_sysconfdir}/udev/rules.d/
install -m644 %{SOURCE3} $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/network-scripts/
install -m755 %{SOURCE4} $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/network-scripts/
install -m755 %{SOURCE7} $RPM_BUILD_ROOT%{_sysconfdir}/dhcp/dhclient.d/
%if %{systemd}
install -d -m755 $RPM_BUILD_ROOT%{_sbindir}
install -m755 %{SOURCE5} $RPM_BUILD_ROOT%{_sbindir}/
install -m755 %{SOURCE6} $RPM_BUILD_ROOT%{_sbindir}/
install -m755 %{SOURCE9} $RPM_BUILD_ROOT%{_sbindir}/
install -m644 %{SOURCE0} $RPM_BUILD_ROOT%{_sysconfdir}/udev/rules.d/53-ec2-network-interfaces.rules
install -d -m755 $RPM_BUILD_ROOT%{_unitdir}
install -m644 %{SOURCE13} $RPM_BUILD_ROOT%{_unitdir}/ec2net-scan.service
install -m644 %{SOURCE16} $RPM_BUILD_ROOT%{_unitdir}/ec2net-ifup@.service
install -d -m755 $RPM_BUILD_ROOT/usr/lib/udev
install -m644 %{SOURCE14} $RPM_BUILD_ROOT/usr/lib/udev
install -m644 %{SOURCE15} $RPM_BUILD_ROOT/usr/lib/udev
%else
install -d -m755 $RPM_BUILD_ROOT/sbin
install -m755 %{SOURCE5} $RPM_BUILD_ROOT/sbin/
install -m755 %{SOURCE6} $RPM_BUILD_ROOT/sbin/
install -m755 %{SOURCE9} $RPM_BUILD_ROOT/sbin/
install -m644 %{SOURCE1} $RPM_BUILD_ROOT%{_sysconfdir}/udev/rules.d/53-ec2-network-interfaces.rules
install -d -m755 $RPM_BUILD_ROOT%{_sysconfdir}/init
install -m644 %{SOURCE12} $RPM_BUILD_ROOT%{_sysconfdir}/init
%endif # systemd
install -m644 %{SOURCE8} $RPM_BUILD_ROOT%{_mandir}/man8/ec2ifup.8
ln -s ./ec2ifup.8.gz $RPM_BUILD_ROOT%{_mandir}/man8/ec2ifdown.8.gz
install -m644 %{SOURCE10} $RPM_BUILD_ROOT%{_mandir}/man8/ec2ifscan.8

# add module configs
install -m644 -D %{SOURCE11} $RPM_BUILD_ROOT/etc/modprobe.d/ixgbevf.conf

%clean
rm -rf $RPM_BUILD_ROOT

%if %{with systemd}
%post
%systemd_post ec2net-scan.service
%systemd_post ec2net-ifup@.service

%preun
%systemd_preun ec2net-scan.service
%systemd_preun ec2net-ifup@.service
%endif # systemd

%files
%{_sysconfdir}/udev/rules.d/53-ec2-network-interfaces.rules
%{_sysconfdir}/udev/rules.d/75-persistent-net-generator.rules
%{_sysconfdir}/modprobe.d/ixgbevf.conf
%{_sysconfdir}/sysconfig/network-scripts/ec2net-functions
%{_sysconfdir}/sysconfig/network-scripts/ec2net.hotplug
%{_sysconfdir}/dhcp/dhclient.d/ec2dhcp.sh
%if %{systemd}
%{_sbindir}/ec2ifup
%{_sbindir}/ec2ifdown
%{_sbindir}/ec2ifscan
%attr(0644,root,root) %{_unitdir}/ec2net-scan.service
%attr(0644,root,root) %{_unitdir}/ec2net-ifup@.service
%attr(755, -, -) %{_prefix}/lib/udev/write_net_rules
%{_prefix}/lib/udev/rule_generator.functions
%else
/sbin/ec2ifup
/sbin/ec2ifdown
/sbin/ec2ifscan
%{_sysconfdir}/init/elastic-network-interfaces.conf
%endif # systemd
%doc %{_mandir}/man8/ec2ifup.8.gz
%doc %{_mandir}/man8/ec2ifdown.8.gz
%doc %{_mandir}/man8/ec2ifscan.8.gz

%changelog
* Mon Jul 13 2020 Frederick Lefebvre <fredlef@amazon.com> 1.4-2
- Provides ec2-net-utils for backward compatibility

* Wed Jun  3 2020 Frederick Lefebvre <fredlef@amazon.com> 1.4-1
- Rename package to match the name of the git repo
- Fix installation on non-systemd environments
- Support toggling default route through {INTERFACE} to main kernel route table [Prithvi Ramesh]

* Thu Mar  5 2020 Frederick Lefebvre <fredlef@amazon.com> 1.3-2
- Fix installation on non-systemd environments

* Wed Jan 15 2020 Frederick Lefebvre <fredlef@amazon.com> 1.3-1
- Add support for IMDSv2

* Wed Jan  8 2020 Frederick Lefebvre <fredlef@amazon.com> 1.2-2.1
- Explicitly set the dhcp timeout for ENIs

* Tue Jul 17 2018 Frederick Lefebvre <fredlef@amazon.com> 1.2-1.1
- Re-license under MIT

* Wed Jun 06 2018 Chad Miller <millchad@amazon.com>
- Loop to get correct MAC address from sysfs when it's
  all 00s

* Mon Dec 04 2017 Frederick Lefebvre <fredlef@amazon.com>
- Add systemd support

* Wed Sep 22 2010 Nathan Blackham <blackham@amazon.com>
- move to ec2-utils
- add udev code for symlinking xvd* devices to sd*

* Tue Sep 07 2010 Nathan Blackham <blackham@amazon.com>
- initial packaging of script as an rpm
