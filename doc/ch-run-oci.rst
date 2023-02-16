:code:`ch-run-oci`
++++++++++++++++++

.. only:: not man

   OCI wrapper for :code:`ch-run`.


Synopsis
========

::

   $ ch-run-oci OPERATION [ARG ...]

Description
===========

.. note::

   This command is experimental. Features may be incomplete and/or buggy. The
   quality of code is not yet up to the usual Charliecloud standards, and
   error handling is poor. Please report any issues you find, so we can fix
   them!


Open Containers Initiative (OCI) wrapper for :code:`ch-run(1)`. You probably
don’t want to run this command directly; it is intended to interface with
other software that expects an OCI runtime. The current goal is to support
completely unprivileged image building (e.g. :code:`buildah
--runtime=ch-run-oci`) rather than general OCI container running.

*Support of the OCI runtime specification is only partial.* This is for two
reasons. First, it’s an experimental and incomplete feature. More importantly,
the philosophy and goals of OCI differ significantly from those of
Charliecloud. Key differences include:

  * OCI is designed to run services, while Charliecloud is designed to run
    scientific applications.

  * OCI containers are persistent things with a complex lifecycle, while
    Charliecloud containers are simply UNIX processes.

  * OCI expects support for a variety of namespaces, while Charliecloud
    supports user and mount, no more and no less.

  * OCI expects runtimes to maintain a supervisor process in addition to
    user processes; Charliecloud has no need for this.

  * OCI expects runtimes to maintain state throughout the container lifecycle
    in a location independent from the caller.

For these reasons, :code:`ch-run-oci` is a bit of a kludge, and much of what
it does is provide scaffolding to satisfy OCI requirements.

Which OCI features are and are not supported is provided in the rest of this
man page, and technical analysis and discussion are in the Contributor’s
Guide.

This command supports OCI version 1.0.0 only and fails with an error if other
versions are offered.

Operations
==========

All OCI operations are accepted, but some are no-ops or merely scaffolding to
satisfy the caller. For comparison, see also:

* `OCI runtime and lifecycle spec
  <https://github.com/opencontainers/runtime-spec/blob/master/runtime.md>`_
* The `runc man pages
  <https://github.com/opencontainers/runc/tree/master/man>`_

:code:`create`
--------------

::

   $ ch-run-oci create --bundle DIR --pid-file FILE [--no-new-keyring] CONTAINER_ID

Create a container. Charliecloud does not have separate create and start
phases, so this operation only sets up OCI-related scaffolding.

Arguments:

  :code:`--bundle DIR`
    Directory containing the OCI bundle. This must be :code:`/tmp/buildahYYY`,
    where :code:`YYY` matches :code:`CONTAINER_ID` below.

  :code:`--pid-file FILE`
    Filename to write the "container" process PID to. Note that for
    Charliecloud, the process given is fake; see above. This must be
    :code:`DIR/pid`, where :code:`DIR` is given by :code:`--bundle`.

  :code:`--no-new-keyring`
    Ignored. (Charliecloud does not implement session keyrings.)

  :code:`CONTAINER_ID`
    String to use as the container ID. This must be
    :code:`buildah-buildahYYY`, where :code:`YYY` matches :code:`DIR` above.

Unsupported arguments:

  :code:`--console-socket PATH`
    UNIX socket to pass pseudoterminal file descriptor. Charliecloud does not
    support pseudoterminals; fail with an error if this argument is given. For
    Buildah, redirect its input from :code:`/dev/null` to prevent it from
    requesting a pseudoterminal.

:code:`delete`
--------------

::

   $ ch-run-oci delete CONTAINER_ID

Clean up the OCI-related scaffolding for specified container.

:code:`kill`
------------

::

   $ ch-run-oci kill CONTAINER_ID

No-op.

:code:`start`
-------------

::

   $ ch-run-oci start CONTAINER_ID

Eexecute the user command specified at create time in a Charliecloud
container.

:code:`state`
-------------

::

   $ ch-run-oci state CONTAINER_ID

Print the state of the given container on standard output as an OCI compliant
JSON document.

Unsupported OCI features
========================

As noted above, various OCI features are not supported by Charliecloud. We
have tried to guess which features would be essential to callers;
:code:`ch-run-oci` fails with an error if these are requested. Otherwise, the
request is simply ignored.

We are interested in hearing about scientific-computing use cases for
unsupported features, so we can add support for things that are needed.

Our goal is for this man page to be comprehensive: every OCI runtime feature
should either work or be listed as unsupported.

Unsupported features that are an error:

  * Pseudoterminals
  * Hooks (prestart, poststart, and prestop)
  * Annotations
  * Joining existing namespaces
  * Intel Resource Director Technology (RDT)

Unsupported features that are ignored:

  * Mounts other than the root filesystem
  * User/group mappings beyond one user mapped to EUID and one group mapped to
    EGID
  * Disabling :code:`prctl(PR_SET_NO_NEW_PRIVS)`
  * Root filesystem propagation mode
  * :code:`sysctl` directives
  * masked and read-only paths (remaining unprivileged protects you)
  * Capabilities
  * rlimits
  * Devices (all devices are inherited from the host)
  * cgroups
  * seccomp
  * SELinux
  * AppArmor
  * Container hostname setting

Environment variables
=====================

.. include:: py_env.rst

:code:`CH_RUN_OCI_HANG`

  If set to the name of a command (e.g., :code:`create`), sleep indefinitely
  when that command is invoked. The purpose here is to halt a build so it can
  be examined and debugged.


.. include:: ./bugs.rst
.. include:: ./see_also.rst
