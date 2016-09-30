Version history
***************

A detailed version history is available in the Git commit log.

.. contents::
   :depth: 2
   :local:

v0.2.0, FIXME
=============

* Switch to containers rather than virtual machines. (VM code remains
  available under the :code:`virtual-machines` branch.)

v0.1.5, 2015-Jun-16
===================

* First public release.

v0.1.4, 2015-Jun-04
===================

* Stop using VDE in workstation mode; use OS bridge/NAT instead (#40).
* Various bug fixes.

v0.1.3, 2015-Apr-30
===================

* Remove :code:`chextern` secondary job user (#51).
* Add :code:`--version` argument to scripts (#54).
* Pass tests under QEMU 2.3.0.
* Various bug fixes.

v0.1.2, 2015-Feb-09
===================

* Regression testing.
* Performance improvements (:code:`virtio-blk` data plane driver,
  :code:`fallocate()` for temp block devices).
* Better error handling.
* API updates.
* Various bug fixes.

v0.1.1, 2014-Dec-01
===================

* Write documentation.
* API updates.
* Various bug fixes.

v0.1.0, 2014-Sep-30
===================

* First numbered version
