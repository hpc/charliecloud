Installation
************

This section describes what you need to install Charliecloud and how to do so.

.. contents::
   :depth: 2
   :local:


Dependencies
============

Charliecloud's philosophy on dependencies is that they should be (1) minimal
and (2) granular. For any given feature, we try to implement it with the
minimum set of dependencies, and in any given environment, we try to make the
maximum set of features available.

Overview
--------

.. todo::

   This ASCII art is a clunky way to accomplish this table, but Sphinx/ReST
   don't provide a better way. Raw HTML block as above may be an alternative;
   for vertical header cells:
   https://stackoverflow.com/a/47245068
   https://stackoverflow.com/questions/33913304
   https://stackoverflow.com/questions/9434839

   .. raw:: html

     <div class="wy-table-responsive">
     <table class="docutils align-center">
     <tbody>
       <tr>
         <td>foo</td>
         <td>bar</td>
       </tr>
       <tr>
         <td>baz</td>
         <td>qux</td>
       </tr>
       <tr>
         <td>baz</td>
         <td>qux</td>
       </tr>
     </tbody>
     </table>
     </div>

   I'm not convinced we need a table, though. It could be each of the
   following tables could be a section with a bullet list.

   A third alternative is, don't document this here, but have
   :code:`configure` provide a report saying what you can and can't do on a
   given system.

.. code-block:: none

                                               POSIX environment
                                               |  C11 compiler
                                               |  |  Git
                                               |  |  |  GNU Autotools
                                               |  |  |  |  Sphinx 1.4.9+
                                               |  |  |  |  |  Python 3.4+
   BUILDING CHARLIECLOUD ..................... |  |  |  |  |  |
   build Charliecloud from source              x  x
   bootstrap build from Git clone              x  x  x  x
   re-build documentation [1]                  x           x  x
   build test suite                            x              x

                                               POSIX environment
                                               |  Bash 4.1+
                                               |  |  Docker
                                               |  |  |  mktemp(1)
                                               |  |  |  |  Buildah 1.10.1+
                                               |  |  |  |  |  Python 3.4+
                                               |  |  |  |  |  |  Python module "lark-parser"
                                               |  |  |  |  |  |  |  skopeo
                                               |  |  |  |  |  |  |  |  umoci
   IMAGE BUILDERS ............................ |  |  |  |  |  |  |  |  |
   Docker                                      x  x  x  x
   Buildah                                     x  x        x
   ch-grow                                     x  x           x  x  x  x

                                               POSIX environment
                                               |  Bash 4.1+
                                               |  |  One of the image builders above
                                               |  |  |  Access to image repository
                                               |  |  |  |  SquashFS tools
   MANAGING CONTAINER IMAGES ................  |  |  |  |  |
   build images from Dockerfile with ch-build  x  x  x  x
   push/pull images to/from builder storage    x  x  x  x
   pack image with ch-builder2tar              x  x  x
   pack image with ch-builder2squash           x  x  x     x

                                               POSIX environment
                                               |  user namespaces
                                               |  |  SquashFUSE
   RUNNING CONTAINERS .......................  |  |  |
   ch-run                                      x  x
   unpack image tarballs                       x
   mount/unmount SquashFS images               x     x

                                               POSIX environment
                                               |  Bash 4.1+
                                               |  |  Bats 0.4.0
                                               |  |  |  user namespaces
                                               |  |  |  |  wget
                                               |  |  |  |  |  One of the builders above
                                               |  |  |  |  |  |  Access to image repository
                                               |  |  |  |  |  |  |  Sphinx 1.4.9+
                                               |  |  |  |  |  |  |  |  Python 3.4+
                                               |  |  |  |  |  |  |  |  |  SquashFS tools
                                               |  |  |  |  |  |  |  |  |  |  SquashFUSE
                                               |  |  |  |  |  |  |  |  |  |  |  generic sudo
   TEST SUITE ...............................  |  |  |  |  |  |  |  |  |  |  |  |
   run basic tests                             x  x  x  x  x
   run recommended tests with tarballs         x  x  x  x  x  x  x
   run recommented tests using SquashFS        x  x  x  x  x  x  x        x  x
   run complete test suite                     x  x  x  x  x  x  x  x  x  x  x  x

   [1] Pre-built documentation is provided in release tarballs.
