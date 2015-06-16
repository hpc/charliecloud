Testing Charliecloud
********************

Charliecloud includes some rudimentary regression tests to verify that the
scripts are installed and working properly and that images are configured
correctly.

.. contents::
   :depth: 2
   :local:


Non-interactive testing
=======================

This boots a 3-node Charliecloud cluster, runs the tests, and then evaluates
the output. If this test is successful, the interactive tests are generally
not needed.

To run the tests::

  $ cd /data/vm
  $ ~/charliecloud/test/runtest.sh image.qcow2

Wait a minute or two. Eventually, you will see something like the following::

  test output check
  collecting files
  evaluating results
  node 0 test output start (no output = pass)
  node 0 internet results:
    2015-01-23 13:05:39 URL:http://216.58.216.228/ [17374] -> "/dev/null" [1]
    2015-01-23 13:05:40 URL:http://www.google.com/ [17356] -> "/dev/null" [1]
  node 1 test output start (no output = pass)
  node 1 internet results:
    2015-01-23 13:05:39 URL:http://216.58.216.228/ [17374] -> "/dev/null" [1]
    2015-01-23 13:05:40 URL:http://www.google.com/ [17356] -> "/dev/null" [1]
  node 2 test output start (no output = pass)
  node 2 internet results:
    2015-01-23 13:05:39 URL:http://216.58.216.228/ [17374] -> "/dev/null" [1]
    2015-01-23 13:05:40 URL:http://www.google.com/ [17356] -> "/dev/null" [1]

In this case, we can see that:

1. The tests passed, because there was no output between the :code:`test
   output start` lines and :code:`internet results`.

2. The nodes can reach the internet, because the :code:`wget` output reports
   successfully fetching the Google home page. (This test is not automatically
   interpreted because it is difficult to know if the internet *should* be
   reachable.)

If the tests failed, detailed differences between expected and actual output
will be presented. If you have :code:`colordiff` installed, these differences
will be in color.

.. tip::

   * If the cluster hangs or fails during boot, diagnose with :code:`tail -F
     charlie-test/out/*` in another window.

   * VDE networking in workstation mode is known to be buggy. If some but not
     all nodes have trouble reaching the internet or each other, that is
     likely why. This should not be considered a Charliecloud or image
     configuration problem. See `issue #40
     <https://git.lanl.gov/reidpr/charliecloud/issues/40>`_.


Interactive testing
===================

If the non-interactive tests fail, typically you will need to boot a cluster
and iterate between repair work and re-tests. The interactive tests are not
quite as comprehensive, so a non-interactive test run is advised once the
interactive tests pass.

To boot an interactive test cluster::

  $ ~/charliecloud/test/runtest.sh -ic image.qcow2

:code:`-i` starts the cluster in interactive mode, and :code:`-c` commits the
changes to guest 0 after it shuts down.

While the cluster is booting, start the evaluator in another terminal on the
host::

  $ ~/charliecloud/test/evaluate.sh -i0 charlie-test testout

:code:`-i` runs the evaluation in interactive mode, and :code:`-0` evaluates
only the results from guest 0, which is typically what you want during image
repairs.

When prompted, log into guest 0's console and run the tests. Typically, you
will run them on guest 0 only, which avoids the need to simultaneously update
the other guests as you repair problems::

  > /ch/meta/jobscript 2> /dev/ttyS2 | tee /dev/ttyS1

The :code:`tee` pipe shows the main test output as it is generated.

To iterate, just run :code:`evaluate.sh` again.

To run the tests on all guests::

  > for g in $(cat /ch/meta/guests); do
  >   ssh $g sh -c '/ch/meta/jobscript 1> /dev/ttyS1 2>/dev/ttyS2'
  > done
