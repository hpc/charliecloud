Installing Charliecloud on OS X
===============================

**Note: Charliecloud does not currently work on OS X because filesystem
passthrough support is missing. This instructions are intended to support
future work. **

Note that the KVM hypervisor is not available on OS X, so you will be using
software emulation. Be prepared for a significant performance hit.

Prerequisites
-------------

You need [Homebrew][hbr], a working X11 install, and `git` (via Homebrew is
easiest).

[hbr]: http://brew.sh

Install patched VDE
-------------------

Charliecloud in workstation mode uses [Virtual Distributed Ethernet
(VDE2)][vde] for networking.

We require a patched version of VDE because port forwarding listens on all
interfaces and this can't be changed. Our patched version listens on loopback
only.

Install using a custom Homebrew formula:

1. Add the LANL certificate authority to your keychain. (This is necessary to
   make git talk to `git.lanl.gov` over HTTPS.)

    1. Go to the [LANL certificates cite][cer].
    2. Click on "Display in PEM Encoding".
    3. Copy the PEM and save it in a file named `lanl.cer`.
    4. Drag and drop `lanl.cer` into Keychain Access (your login chain is fine).

2. Install the patched VDE using Homebrew:

>     $ brew install https://git.lanl.gov/reidpr/homebrew/raw/master/Library/Formula/vde.rb
>     ######################################################################## 100.0%
>     ==> Downloading https://downloads.sourceforge.net/project/vde/vde2/2.3.2/vde2-2.
>     ######################################################################## 100.0%
>     ==> Patching
>     patching file configure
>     patching file src/slirpvde/slirpvde.c
>     ==> ./configure --prefix=/usr/local/Cellar/vde/2.3.2
>     ==> make install
>     🍺  /usr/local/Cellar/vde/2.3.2: 63 files, 980K, built in 41 seconds

3. Verify that you have the correct VDE:

>     $ vde_switch --version
>     VDE 2.3.2+lanl1
>     [...]

(Note that if you can't convince git to talk to `git.lanl.gov`, you can
download the `vde.rb` formula manually using the link above and give that file
to `brew`.)

[cer]: https://ca-enroll.lanl.gov/cda-cgi/clientcgi.exe?action=start
[vde]: http://vde.sourceforge.net/

Install QEMU and other dependencies
-----------------------------------

    $ brew install git
    $ brew install qemu --with-vde

The system Python is probably fine, but if you run into trouble, try:

    $ brew install python

Charliecloud has no Python dependencies other than the standard library and a
few things included with the source code.

Install Charliecloud
--------------------

Install the software:

    $ cd
    $ git clone https://git.lanl.gov/reidpr/charliecloud.git

Optionally, you can put `~/charliecloud/bin` in your `$PATH` or add symlinks
to the files therein from `/usr/local/bin`.

Get an image to start with:

    $ cd ~/Documents
    $ rsync --progress tfta01:/scratch3/reidpr/debian-wheezy-base_2014-08-19.qcow2 .

(**FIXME**: Indeed, there will be a better way to manage images soon.)

Smoke test
----------

    $ ~/charliecloud/bin/vcluster --help
    Start a virtual cluster of one or more nodes using the given image. The
    guests are distributed across nodes in a SLURM allocation (if one exists) or
    all run on localhost (if not).
    [...]
