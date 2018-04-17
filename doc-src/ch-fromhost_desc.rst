Synopsis
========

::

  $ ch-fromhost [OPTION ...] (--cmd CMD | --file FILE | --nvidia ...) DIR


Description
===========

Inject files from the host into the Charliecloud image directory :code:`DIR`.

The purpose of this command is to provide host-specific files, such as GPU
libraries, to a container. It should be run after :code:`ch-tar2dir` and
before :code:`ch-run`. After invocation, the image is no longer portable to
other hosts.

Injection is not atomic; if an error occurs partway through injection, the
image is left in an undefined state. Injection is currently implemented using
a simple file copy, but that may change in the future.

By default, file paths that contain the string :code:`/bin` are assumed to be
executables and are placed in :code:`/usr/bin` within the container. File
paths that contain the strings :code:`/lib` or :code:`.so` are assumed to be
shared libraries and are placed in :code:`/usr/lib`. Other files are placed in
the directory specified by :code:`--dest`.

If any of the files appear to be shared libraries, run :code:`ldconfig` inside
the container (using :code:`ch-run -w`) after injection.


Options
=======

To specify which files to inject:

  :code:`-c`, :code:`--cmd CMD`
    Inject files listed in the standard output of command :code:`CMD`.

  :code:`-f`, :code:`--file FILE`
    Inject files listed in the file :code:`FILE`.

  :code:`--nvidia`
    Use :code:`nvidia-container-cli list` (from :code:`libnvidia-container`)
    to find executables and libraries to inject.

These can be repeated, and at least one must be specified.

Additional arguments:

  :code:`-d`, :code:`--dest DST`

    Place files whose destination cannot be inferred in directory
    :code:`DIR/DST`. If such a file is found and this option is not specified,
    exit with an error.

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`--no-infer`
    Do no try to infer the destination of any files.

  :code:`-v`, :code:`--verbose`
    Pist the injected files.

  :code:`--version`
    Print version and exit.


Notes
=====

Symbolic links are dereferenced, i.e., the files pointed to are injected, not
the links themselves.

As a corollary, do not include symlinks to shared libraries. These will be
re-created by :code:`ldconfig`.

There are two alternate approaches for nVidia GPU libraries:

  1. Link :code:`libnvidia-containers` into :code:`ch-run` and call the
     library functions directly. However, this would mean that Charliecloud
     would either (a) need to be compiled differently on machines with and
     without nVidia GPUs or (b) have :code:`libnvidia-containers` available
     even on machines without nVidia GPUs. Neither of these is consistent with
     Charliecloud's philosophies of simplicity and minimal dependencies.

  2. Use :code:`nvidia-container-cli configure` to do the injecting. This
     would require that containers have a half-started state, where the
     namespaces are active and everything is mounted but :code:`pivot_root(2)`
     has not been performed, but Charliecloud has no notion of a half-started
     container.

Further, while these alternate approaches would simplify or eliminate this
script for nVidia GPUs, it would not solve the problem for other situations.


Bugs
====

File paths may not contain newlines.


Examples
========

Place shared library :code:`/usr/lib64/libfoo.so` at path
:code:`/usr/lib/libfoo.so` within the image :code:`/var/tmp/baz` and
executable :code:`/bin/bar` at path :code:`/usr/bin/bar`. Then, create
appropriate symlinks to :code:`libfoo` and update the :code:`ld.so` cache.

::

  $ cat qux.txt
  /bin/bar
  /usr/lib64/libfoo.so
  $ ch-fromhost --file qux.txt /var/tmp/baz

Same as above::

  $ ch-fromhost --cmd 'cat qux.txt' /var/tmp/baz

Same as above, and also place file :code:`/etc/quux` at :code:`/etc/quux`
within the container::

  $ cat corge.txt
  /bin/bar
  /etc/quux
  /usr/lib64/libfoo.so
  $ ch-fromhost --file corge.txt --dest /etc /var/tmp/baz

Inject the executables and libraries recommended by nVidia into the image, and
then run :code:`ldconfig`::

  $ ch-fromhost --nvidia /var/tmp/baz
