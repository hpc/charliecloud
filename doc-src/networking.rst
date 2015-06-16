Networking
**********

This file documents network addresses, topology, and security in
Charliecloud virtual clusters. We distinguish between *workstation
mode*, where guests can make outgoing connections to the network, and
*cluster mode*, where guests have no network access at all beyond the
SLURM allocation.

.. contents::
   :depth: 2
   :local:

.. note::

   InfiniBand within guests is not available at this time, so we do not
   consider it in this document.


Network addresses
=================

In selecting IP and MAC addresses for guests, there are several
desirable properties:

#. No collisions with other real or virtual hardware.
#. Easy to recognize as Charliecloud addresses.
#. Well-defined mappings so that guests can infer useful things.

This section covers background information on both types of addresses
and parameter selection to meet these desiderata.

IP addresses
------------

There are three `private IP address
ranges <http://en.wikipedia.org/wiki/Private_network#Private_IPv4_address_spaces>`_:

* 10.0.0.0/8
* 172.16.0.0/12 (i.e., 172.16.0.0 - 172.31.255.255)
* 192.168.0.0/16

Of these, 10/8 and 192.168/16 are very commonly used. Therefore, we use
172.16/12 to avoid collisions.

Guests set their IP address to the lower four bytes of the MAC address. It is
the responsibility of the :code:`oneguest` caller to ensure that the MAC address
maps to a reasonable IP address. (Guests can do something else if they wish,
but this will lead to a non-functional network.)

MAC addresses
-------------

QEMU emulates Ethernet network devices. MAC addresses for Ethernet are 48 bits
long, typically expressed as 6 hexadecimal octets. The first three octets are
a vendor code (*organizationally unique identifier* or OUI). For example, a
device with MAC address 00:03:93:x:x:x is an Apple product (there are many
other Apple vendor codes too). These are listed `officially by the IEEE
<http://standards.ieee.org/develop/regauth/oui/oui.txt>`_ and unofficially by
`other sources
<https://code.wireshark.org/review/gitweb?p=wireshark.git;a=blob_plain;f=manuf>`_.

QEMU has an assigned vendor code, 52:54:00, as do many other virtualization
technologies. However, if we control 4 bytes rather than just 3, this enables
a convenient mapping to IP address.

Private MAC addresses do exist. They are called *locally administered
addresses* and there are four ranges: *xy*:*xx*:*xx*, where *y* is 2, 6, A, or
E and *x* is any hex digit.

My reading of the standards is that we should be using such MAC addresses.
However, they don't work in guests. For example, Debian Wheezy will hang
during boot, and CentOS 6.4 will finish booting but not bring up the
interface. I have not investigated this issue.

We use MAC addresses in the range 0C:00:AC:1B:*xx*:*xx*; these produce IP
addresses in the range 172.22.0.0/16. (This uses a real but apparently unused
vendor code of 0C:00:AC.)

QEMU sets the MAC addresses of virtualized hardware. This can be changed later
by guests, though again to their detriment.


Topology
========

The following is the topology of each virtual cluster. Implementation varies
depending on mode (workstation vs. cluster); these details are given below.

Hosts are numbered consecutively starting with 1, perhaps non-consecutively.
On each host, guests are numbered consecutively starting with 1. (This
numbering has no well-defined mapping with guest IDs, which count from 0
across the whole virtual cluster.) Each guest receives the IP address 172.22.\
:math:`i`.\ :math:`j`, where :math:`i` is the host number and :math:`j` is the
guest number. Guests on each host share a gateway router with IP 172.22.\
:math:`i`.254.

For example, the following are the addresses used in a 4-node virtual
cluster running on two hosts:

========  ======  =======  =================  ==========  ============
guest ID  host #  guest #  guest MAC          guest IP    router IP
========  ======  =======  =================  ==========  ============
0         1       1        0C:00:AC:16:01:01  172.22.1.1  172.22.1.254
1         1       2        0C:00:AC:16:01:02  172.22.1.2  172.22.1.254
2         2       1        0C:00:AC:16:02:01  172.22.2.1  172.22.2.254
3         2       2        0C:00:AC:16:02:02  172.22.2.2  172.22.2.254
========  ======  =======  =================  ==========  ============

The topology, from the perspective of guest 1:

.. code-block:: text

   +------------+  +------------+  +------------+  +------------+
   |   guest 0  |  |   guest 1  |  |   guest 2  |  |   guest 3  |
   | 172.22.1.1 |  | 172.22.1.2 |  | 172.22.2.1 |  | 172.22.2.2 |
   +------------+  +------------+  +------------+  +------------+
            |         |                   |               |
          +--------------+                |               |
          |    switch    |                |               |
          +--------------+                |               |
                  |                       |               |
          +--------------+                |               |
          |   router 1   |                |               |
          | 172.22.1.254 |                |               |
          +--------------+                |               |
                  |                       |               |
      +------------------------------------------------------+
      |                  opaque interconnect                 |
      +------------------------------------------------------+

.. note::

   * Because the user has root inside the guest, these assignments are merely
     advisory. The guest interface can be set to any IP or MAC address. The
     security implications of this are discussed below.

   * This specific numbering scheme does not scale beyond 254 hosts, but the
     principles hold in larger clusters. We defer a more flexible numbering
     scheme to future work.


Workstation mode
================

Requirements
------------

* **Multiple users on the host.** While most workstations have only a single
  user, this isn't universal. Guest resources should be only available to the
  user running the guest and to those other local users to whom s/he has
  explicitly granted access.

* **Multiple guests running simultaneously.** There might even be multiple
  virtual clusters.

* **No inbound networking except from the host and virtual cluster.** Guests
  accept no connections from the outside world. Connections from other guests
  in the same virtual cluster are permitted.

* **Outbound network access to network and host.** Guests may initiate
  connections to other guests in the virtual cluster, the network, and the
  host. That is, guests have more or less the same outgoing network access
  that the host does.

Topology implementation
-----------------------

Switching is done with a host OS bridge device; outbound networking is
provided with OS IP forwarding and NAT; inbound networking is prevented by
NAT.

Security
--------

MAC and IP spoofing
~~~~~~~~~~~~~~~~~~~

Under the workstation model, no packets with user-defined IP or MAC addresses
leave the virtual environment. Therefore, spoofing has no benefit.

Inbound network access
~~~~~~~~~~~~~~~~~~~~~~

NAT prevents guests from listening to the physical network. Anything on the
host can connect to the guest IP addresses.

This raises a potential security issue, as users on the host might not
necessarily be authorized to log into guests. This is mitigated in the base
images by SSH key authentication and running minimal network services.

Risks
~~~~~

* The user might change the Charliecloud scripts, enabling errors such as
  exposing guests directly to the network.

* Data center operators have limited control of what goes on in workstation
  mode, especially if the user has root on their workstation, which is a
  common situation. Ultimately, maintaining security in this mode is up to the
  user and their management.


Cluster mode
============

In cluster mode, one runs a virtual cluster on physical nodes in a SLURM
allocation.

Requirements
------------

* **Node-exclusive allocation.** We still have one job per node, consistent
  with existing supercomputing practice.

* **Multiple guests per host.** While current plans call for a single guest
  per host node, the cluster mode topology is designed to support several.

* **Network traffic limited to job.** No network packets originating from or
  destined to a guest in a SLURM allocation to may go beyond the guests and
  hosts (compute nodes) in that allocation. In particular, the front end, I/O
  nodes, and other cluster support infrastructure, as well as network
  resources such as filesystem servers, are never accessible to guests.

* **Resilient security scripts.** The network limitations above are
  implemented using a variety of setup and teardown scripts. Allocation setup
  is designed to fail if network security rules are not configured correctly,
  and rules are designed with some degree of redundancy so that the effect of
  bugs is minimized.

* **No user configuration of host networking.** All privileged network
  configuration described below, except within the guest, is performed by
  boot, prologue, and epilogue scripts which the user cannot change. This
  includes setuid tools; for example, we do not use the setuid script
  :code:`qemu-bridge-helper` provided in some installations of QEMU.

Topology
--------

* Hosts (compute nodes) use the cluster numbering: e.g., :code:`cn001` is host
  1, :code:`cn002` is host 2, etc.

* Each guest is connected to a host TAP interface: guest 1 to :code:`tap0`,
  guest 2 to :code:`tap1`, etc.

* All of these TAPs are bridged together in :code:`br0`, which is assigned the
  router address. This accomplishes switching.

* Kernel routing tables connect :code:`br0` to the IP-over-InfiniBand
  interface :code:`ib0` at Layer 3. This accomplishes routing.

Security
--------

MAC and IP spoofing
~~~~~~~~~~~~~~~~~~~

User-selected MAC addresses do not leave the virtual environment (the bridge
:code:`br0`).

However, packets with user-selected IP addresses pass to the physical host
network. This raises the following attack scenario: clone the IP address of a
compute node and use IP-based authentication (common at many sites) to access
resources that should be unavailable.

This is mitigated by adding an iptables rule to each TAP device which drops
traffic not to/from the assigned IP address. This ensures that packets with
spoofed addresses don't leave (or aren't delivered to) the guest.

Guest isolation
~~~~~~~~~~~~~~~

Guest traffic should only travel between guests in the same job, and in
particular it should not be allowed to leave the compute nodes. This prevents
both (a) others accessing perhaps-insecure guest services and (b) guests
accessing resources that should be unavailable.

This is mitigated with iptables rules that drop outgoing traffic not destined
for guests or hosts in the job and incoming traffic not originating from
guests or hosts in the job.

Risks
~~~~~

The risks of the above plan include:

* Problems with the firewall rules can leave openings that were not intended.
  This is mitigated by redundant checks that the rules are set up correctly.

* Guest traffic with other compute nodes (and their guests) is filtered only
  on the host. However, other sandboxing means surround the the compute nodes,
  limiting the scope of any problems.

While it's true that a user who pwns a host can then adjust the firewall rules
to escalate guest access, this is more work than simply using the pwned host
directly. Therefore, we don't worry too much about maliciously adjusted
rules.

Cluster mode FAQ
----------------

* **Why not use point-to-point links over TCP sockets?** This would completely
  avoid guest traffic being on the physical network, but we would need a
  complete graph, which doesn't scale well.

* **How about NAT?** This would make it difficult for guest codes to find one
  another.

* **This means guests get no DNS!** That's right, but they don't need it
  really since they only need to talk to their peers in the job. Charliecloud
  provides an :code:`/etc/hosts` file with symbolic names for the guests in a
  cluster.

* **We could build a second physical network.** This network wouldn't go
  beyond the compute nodes. Then, even if network traffic escaped the software
  constraints, it couldn't go beyond the compute nodes. This approach would be
  pretty reliable but also expensive, and it wouldn't serve the Charliecloud
  goal of augmenting existing clusters.


Resources
=========

* https://people.gnome.org/~markmc/qemu-networking.html
* https://wiki.archlinux.org/index.php/QEMU#Networking
* http://wiki.qemu.org/Features/HelperNetworking
* http://www.linux-kvm.org/page/Networking
* https://www.kernel.org/doc/Documentation/networking/tuntap.txt
* https://www.berrange.com/posts/2011/10/03/guest-mac-spoofing-denial-of-service-and-preventing-it-with-libvirt-and-kvm/
