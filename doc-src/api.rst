API documentation
*****************

.. contents::
   :depth: 2
   :local:

.. note::

   The Charliecloud API is currently in flux; therefore, this documentation is
   an incomplete work in progress. Honestly, it is best ignored at this point.


The job directory
=================

FIXME

* :code:`metadata`: metadata files provided to guests (see below)
* :code:`console`: serial console output from each guest (named by guest ID)
* :code:`images`: guest root filesystem overlays (named by guest ID)

Job script arguments: (FIXME: environment variables?)

#. guest ID (integer starting with 0)
#. metadata directory
#. temporary directory
#. data1, if present else empty string
#. data2
#. data3
#. data4


Filesystems provided to the guest
=================================

Charliecloud guests receive both metadata about the job and data of the user's
choice using 9p virtio filesystem passthrough. In standard images, these are
mounted automatically under :code:`/ch`. The mount tag for each is the same as
the final directory given below, which can be used to identify the filesystem
in other guests (e.g.: :code:`/ch/meta` gets mount tag :code:`meta`).

Metadata
--------

Metadata is available under :code:`/ch/meta`. The following files are
provided. All guests in the job get the same files.

Files containing records have one record per line; fields are separated by
whitespace. Record order is arbitrary.

* :code:`commit`: If present, the root filesystem of least one virtual machine
  in the cluster will be committed. If absent, all changes will be discarded.
  The point is to let jobs know if they can safely mess with the root
  filesystem.

* :code:`guest-macs`: Two fields: integer guest ID followed by MAC address.

* :code:`guest-ips`: Three fields: integer guest ID, IP address of guest, IP
  address of corresponding host. Note that this file may be incomplete and may
  list guests that are unreachable.

* :code:`host-userdata`: Python pickle file describing the user and groups of
  the invoking host user.

* :code:`interactive`: Indicates that the boot scripts have requested an
  interactive job despite providing a job script. If present, the standard
  images do not shut down after :code:`job.sh` finishes.

* :code:`job.sh`: Job shell script provided to guest boot script. If present,
  the standard images run this script after boot. (Note: If :code:`job.sh` is
  not present, standard images will stay up after boot regardless of
  :code:`interactive`.) (FIXME: Document that :code:`sudo /etc/rc.local` will
  re-run the job as if after boot, and document that doing so won't shut down
  regardless of above.)

Charliecloud resources
----------------------

:code:`/ch/opt` contains guest resources that come with Charliecloud, such as
scripts to run the job. Standard images require these resources in order to do
boot as documented here, but they will come up in a minimal configuration if
they are absent.

Persistent storage
------------------

Directories selected by the user (using the :code:`-d` switch of
:code:`runguest` or `runguests`) are offered to the guests under
:code:`/ch/data[1-4]`. (There's no inherent limit, but 4 is what we
implemented in the standard images.)

Temporary storage
-----------------

A block storage device is offered to each guest for temporary file storage; it
is wiped after the guest shuts down.

Standard guests create an ext4 filesystem with no journal and mount it under
:code:`/ch/tmp`, option noatime.
