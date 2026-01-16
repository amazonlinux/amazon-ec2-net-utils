# amazon-ec2-net-utils #

## Background ##

The amazon-ec2-net-utils package provides functionality needed to
configure a Linux instance for optimal performance in a VPC
environment. It handles:

* Per-interface policy routing rules to accommodate VPC source/dest
  restrictions
* Configuration of secondary IPv4 addresses
* Configuration of ENIs upon hotplug
* Routing configuration for delegated prefixes

<b>The version 1.x branch of the amazon-ec2-net-utils package was used in
Amazon Linux 2</b> and earlier releases.  It has a long history and is
tightly coupled to ISC dhclient and initscripts network
configuration. Both of these components are deprecated and will not
make up the primary network configuration framework in future releases
of Amazon Linux or other distributions. <b>The 2.x branch (released from
the `main` branch in git) represents a complete rewrite targeting a
more modern network management framework like AL2023</b>.  The rest of this document
describes the 2.x branch.

## Implementation ##

amazon-ec2-net-utils leverages systemd-networkd for most of the actual
interface configuration, and is primarily responsible for mapping
configuration information available via IMDS to systemd-networkd input
configuration. It provides event-based configuration via udev rules,
with timer based actions in order to detect non event based changes
(e.g. secondary IP address assignment). Generated configuration is
stored in the /run/ ephemeral filesystem and is not persisted across
instance reboots. The generated configuration is expected to be
regenerated from scratch upon reboot. Customers can override the
behavior of the package by creating configuration files in the local
administration network directory /etc/systemd/network as described in
systemd-networkd's documentation.
 
By utilizing a common framework in the form of systemd, the
amazon-ec2-net-utils package should be able to integrate with any
systemd-based distribution. This allows us to provide customers with a
common baseline behavior regardless of whether they choose Amazon
Linux or a third-party distribution. Testing has been performed on
Debian, Fedora, and Amazon Linux 2023.

## Usage ##

amazon-ec2-net-utils is expected to be pre-installed on Amazon Linux
2023 and future releases. In the common case, customers should not
need to be aware of its operation. Configuration of network interfaces
should occur following the principle of least astonishment. That is,
traffic should be routed via the ENI associated with the source
address.  Custom configuration should be respected. New ENI
attachments should be used automatically, and associated resources
should be cleaned up on detachment. Manipulation of an ENI attachment
should not impact the functionality of any other ENIs.

## Build and install ##

The recommended way to install amazon-ec2-net-utils is by building a
package for your distribution. A spec file and debian subdirectory are
provided and should be reasonably suitable for modern rpm or dpkg
based distributions. Build dependencies are declared in debian/control
and in amazon-ec2-net-utils.spec and can be installed using standard
tools from the distributions (e.g. dpkg-checkbuilddeps and apt, or dnf
builddep, etc)

The post installation scripts in the spec file and or .deb package
will stop NetworkManager or ifupdown, if running, and initialize
systemd-networkd and systemd-resolved. The expectation is that
amazon-ec2-net-utils will take over and initialize a running system,
without rebooting, such that it is indistinguishable from a system
that booted with amazon-ec2-net-utils.

### rpm build and installation ###

    $ mkdir -p rpmbuild/BUILD
    $ git -C amazon-ec2-net-utils/ archive main | (cd rpmbuild/BUILD/ && tar xvf -)
    $ rpmbuild -bb rpmbuild/BUILD/amazon-ec2-net-utils.spec
    $ sudo dnf install rpmbuild/RPMS/noarch/amazon-ec2-net-utils-*.al2023.noarch.rpm
 
### dpkg build and installation ###

    $ dpkg-buildpackage -uc -us -b
    $ sudo apt install ../amazon-ec2-net-utils_*_all.deb
 
### Installation verification ###

    $ # inspect the state of the system to verify that networkd is running:
    $ networkctl # should report all physical interfaces as "routable" and "configured"
    $ networkctl status ens5 # should report "/run/systemd/network/70-ens5.network" as the network conf file
    $ resolvectl # show status of systemd-resolved

**Example:**

    [ec2-user@ip-172-31-41-210 ~]$ networkctl
    IDX LINK TYPE     OPERATIONAL SETUP
      1 lo   loopback carrier     unmanaged
      2 ens5 ether    routable    configured

    [ec2-user@ip-172-31-41-210 ~]$ networkctl status ens5
    ● 2: ens5                       
                      Link File: /usr/lib/systemd/network/99-default.link
                    Network File: /run/systemd/network/70-ens5.network
                          State: routable (configured)
                    Online state: online
                            Type: ether
                            Path: pci-0000:00:05.0
                          Driver: ena
                          Vendor: Amazon.com, Inc.
                          Model: Elastic Network Adapter (ENA)
              Alternative Names: device-number-0.0
                                  eni-0304feb62015b7959
                                  enp0s5
                Hardware Address: 06:53:e1:d8:f9:29
                            MTU: 9001 (min: 128, max: 9216)
                          QDisc: mq
    IPv6 Address Generation Mode: eui64
        Number of Queues (Tx/Rx): 2/2
                        Address: 172.31.41.210 (DHCP4 via 172.31.32.1)
                                  fe80::453:e1ff:fed8:f929
                        Gateway: 172.31.32.1
                            DNS: 172.31.0.2
                  Search Domains: us-west-2.compute.internal
              Activation Policy: up
            Required For Online: yes
                DHCP4 Client ID: IAID:0xed10bdb8/DUID
              DHCP6 Client IAID: 0xed10bdb8
              DHCP6 Client DUID: DUID-EN/Vendor:0000ab115a2053b21e6b7f0a

            Jan 16 19:49:32 localhost systemd-networkd[1828]: ens5: Configuring with /usr/lib/systemd/network/80-ec2.network.
            Jan 16 19:49:32 localhost systemd-networkd[1828]: ens5: Link UP
            Jan 16 19:49:32 localhost systemd-networkd[1828]: ens5: Gained carrier
            Jan 16 19:49:32 localhost systemd-networkd[1828]: ens5: DHCPv4 address 172.31.41.210/20, gateway 172.31.32.1 acquired from 172.31.32.1
            Jan 16 19:49:32 localhost systemd-networkd[1828]: ens5: Gained IPv6LL
            Jan 16 19:49:33 localhost systemd-networkd[1828]: ens5: Reconfiguring with /run/systemd/network/70-ens5.network.
            Jan 16 19:49:33 localhost systemd-networkd[1828]: ens5: DHCP lease lost
            Jan 16 19:49:33 localhost systemd-networkd[1828]: ens5: DHCPv6 lease lost
            Jan 16 19:49:33 localhost systemd-networkd[1828]: ens5: DHCPv4 address 172.31.41.210/20, gateway 172.31.32.1 acquired from 172.31.32.1
          
    [ec2-user@ip-172-31-41-210 ~]$ resolvectl
     Global
          Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
     resolv.conf mode: uplink
  
     Link 2 (ens5)
     Current Scopes: DNS
        Protocols: +DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
      DNS Servers: 172.31.0.2
        DNS Domain: us-west-2.compute.internal

## Getting help ##

If you're using amazon-ec2-net-utils as packaged by a Linux
distribution, please consider using your distribution's support
channels first.  Your distribution may have modified the behavior of
the package to facilitate better integration, and may have more
specific guidance for you.

Alternatively, if you don't believe your issue is distribution
specific, please feel free to open an issue on GitHub.

## Contributing ##

We are happy to review proposed changes.  If you're considering
introducing any major functionality or behavior changes, you may wish
to consider opening an issue where we can discuss the details before
you proceed with implementation.  Please refer to
[CONTRIBUTING.md](CONTRIBUTING.md) for additional expectations.
