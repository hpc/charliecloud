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

This section documents Charliecloud's dependencies in detail. Do you need to
read it? If you are installing Charliecloud on the same system where it will
be used, probably not. :code:`configure` will issue a report saying what will
and won't work. Otherwise, it may be useful to gain an understanding of what
to expect when deploying Charliecloud.

Overview
--------

This section is a comprehensive list of dependencies needed for each feature.
Versions are stated in the next section.

Everything needs a POSIX shell and utilities, so that column has been omitted.


.. todo::

   Two alternatives below on how to accomplish this table. Differences:

     #. ASCII art vs. real HTML table (using raw HTML block)
     #. Single table vs. multiple tables.

   This ASCII art is a clunky way to accomplish this table, but Sphinx/ReST
   don't provide a better way. Raw HTML block as above may be an alternative;
   for vertical header cells:
   https://stackoverflow.com/a/47245068
   https://stackoverflow.com/questions/33913304
   https://stackoverflow.com/questions/9434839


   I'm not convinced we need a table, though. It could be each of the
   following tables could be a section with a bullet list.

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

.. todo::

   Problems with this table:

     #. Column headers not centered horizontally.

     #. Background colors not used helpfully (e.g. can we make the header rows
        gray and the rest white?).

     #. First column not frozen on scrolling.

   Assume these are fixed when evaluating.

.. raw:: html

  <style type="text/css">
    table.docutils {
      /* Work around alternating row colors. This only affects the even
         (white) rows. I couldn't find a way to make the odd rows white. */
      background-color: #f3f6f6;
    }
    table.docutils tr th {
      border: 1px solid #e1e4e5;  /* add missing <th> borders */
      text-align: left;
    }
    /* table.docutils tr td.lhead {
      position: absolute;
    } */
    table.docutils tr.rotate td {
      text-align: center;
      vertical-align: bottom;
    }
    table.docutils tr.rotate td span {
      /* https://stackoverflow.com/a/47245068/396038 */
      -ms-writing-mode: tb-rl;
      -webkit-writing-mode: vertical-rl;
      writing-mode: vertical-rl;
      transform: rotate(180deg);
      white-space: nowrap;
    }

  </style>
  <table class="docutils align-center">
  <tbody>
    <tr class="rotate">
      <td></td>

      <td><span>C11 compiler</span></td>
      <td><span>Git</span></td>
      <td><span>GNU Autotools</span></td>
      <td><span>Sphinx</span></td>
      <td><span>Python</span></td>

      <td><span>Bash</span></td>
      <td><span>Docker</span></td>
      <td><span>Buildah</span></td>
      <td><span>Python module “lark-parser”</span></td>
      <td><span>skopeo</span></td>
      <td><span>umoci</span></td>

      <td><span>One of the three image builders</span></td>
      <td><span>Access to image repository</span></td>
      <td><span>SquashFS tools</span></td>
      <td><span>user namespaces</span></td>
      <td><span>SquashFUSE</span></td>

      <td><span>Bats</span></td>
      <td><span>wget</span></td>
      <td><span>generic sudo</span></td>
    </tr>

    <tr>
      <th colspan=20>Building Charliecloud</th>
    </tr>
    <tr>
      <td class="lhead">build Charliecloud from source</td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">bootstrap build from Git clone</td>

      <td></td>
      <td>x</td>
      <td>x</td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">re-build documentation</td>

      <td></td>
      <td></td>
      <td></td>
      <td>x</td>
      <td>x</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">build test suite</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td>x</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>

    <tr>
      <th colspan=20>Image builders</th>
    </tr>
    <tr>
      <td class="lhead">Docker</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">Buildah</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td>x</td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">ch-grow</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td>x</td>

      <td>x</td>
      <td></td>
      <td></td>
      <td>x</td>
      <td>x</td>
      <td>x</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>

    <tr>
      <th colspan=20>Preparing container images</th>
    </tr>
    <tr>
      <td class="lhead">build images from Dockerfile with <tt>ch-build</tt></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">push/pull images to/from builder storage</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">pack image with <tt>ch-builder2tar</tt></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">pack image with <tt>ch-builder2squash</tt></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td>x</td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>

    <tr>
      <th colspan=20>Running containers</th>
    </tr>
    <tr>
      <td class="lhead"><tt>ch-run</tt></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td>x</td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">unpack image tarballs</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">mount/unmount SquashFS images</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td>x</td>

      <td></td>
      <td></td>
      <td></td>
    </tr>

    <tr>
      <th colspan=20>Running test suite</th>
    </tr>
    <tr>
      <td class="lhead">basic tests</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td>x</td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">recommended tests using tarballs</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
      <td>x</td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">recommended tests using SquashFS</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td>x</td>
      <td>x</td>
      <td>x</td>

      <td>x</td>
      <td>x</td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">complete test suite</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td>x</td>
      <td>x</td>
      <td>x</td>

      <td>x</td>
      <td>x</td>
      <td>x</td>
    </tr>

  </tbody>
  </table>

Overview
--------

This section is a comprehensive list of dependencies needed for each feature.
Versions are stated in the next section.

Everything needs a POSIX shell and utilities.

Building Charliecloud
~~~~~~~~~~~~~~~~~~~~~

.. |br| raw:: html

   <br/>

.. list-table::
   :header-rows: 1

   * - in order to
     - you need

   * - build Charliecloud from source
     - C11 compiler (but not Intel CC)

   * - bootstrap build from Git
     - Git
       |br| GNU Autotools

   * - re-build documentation [1]
     - Python
       |br| Sphinx

   * - build test stuie
     - Python

Build Charliecloud from source:

  * C11 compiler (but not Intel CC)

Bootstrap build from Git:

  * Git
  * GNU Autotools

Re-build documentation:

  * Python
  * Sphinx

Build test suite:

  * Python

Note: Built documentation is included in the tarballs.

Details
-------

For some of the dependencies, there are a few more relevant details.
