Contributor's guide
*******************

This section is notes on contributing to Charliecloud development. Currently,
it is messy and incomplete. Patches welcome!

It documents public stuff only. If you are on the core team at LANL, also
consult the internal documentation and other resources.

.. contents::
   :depth: 2
   :local:

.. note::

   We're interested in and will consider all good-faith contributions. While
   it does make things easier and faster if you follow the guidelines here,
   they are not required. We'll either clean it up for you or walk you through
   any necessary changes.


Workflow
========

Branching model
---------------

* We try to keep the branching model simple. Right now, we're pretty similar
  to Scott Chacon's “`GitHub Flow
  <http://scottchacon.com/2011/08/31/github-flow.html>`_”: Master is stable;
  work on short-lived topic branches; use pull requests to ask for merging.

* Tagged versions currently get more testing. We are working to improve
  testing for normal commits on the master, but full parity is probably
  unlikely.

* Don't work directly on master. Even the project lead doesn't do this. While
  it may appear that some trivial fixes are being committed to the master
  directly, what's really happening is that these are prototyped on a branch
  and then fast-forward merged after Travis passes.

* Keep history tidy. While it's often difficult to avoid a branch history with
  commits called "try 2" and "fix Travis", clean it up before submitting a PR.
  Interactive rebase is your friend.

* Feature branches should generally be rebased, rather than merged into, in
  order to track master. PRs with conflicts will generally not be merged.

* Feature branches are merged with either a merge commit or squash and rebase,
  which squashes all the branch's commits into one and then rebases that
  commit onto master's HEAD (called "squash and merge" by GitHub). This can be
  done either on the command line or in the GitHub web interface.

  * Merge commit message example:
    :code:`merge PR #268 from @j-ogas: remove ch-docker-run (closes #258)`
  * Squash and rebase commit message example:
    :code:`PR #270 from me: document locations of .bats files`

* Feature branches in the main repo are deleted by the project lead after
  merging.

* Remove obsolete remote branches from your repo with :code:`git fetch --prune
  --all`.

Issues, pull requests, and milestones
-------------------------------------

* We use milestones to organize what is planned for, and what actually
  happened, in each version.

* All but the most trivial changes should have an issue or a `pull request
  <https://git-scm.com/book/en/v2/GitHub-Contributing-to-a-Project>`_ (PR).
  The relevant commit message should close the issue (not PR) using the
  `GitHub syntax
  <https://help.github.com/articles/closing-issues-using-keywords/>`_.

* The standard workflow is:

  1. Propose a change in an issue.

  2. Tag the issue with its kind (bug, enhancement, question).

  3. Get consensus on what to do and how to do it, with key information
     recorded in the issue.

  4. Assign the issue to a milestone.

  5. Submit a PR that refers to the issue.

  6. Review/iterate.

  7. Project lead merges. No one other than the project lead should be
     merging to or committing on master.

  Don't tag or milestone the PR in this case, so that the change is only
  listed once in the various views.

* Bare PRs with no corresponding issue are also considered but should have
  reached consensus using other means, which should be stated in the PR. Tag
  and milestone the PR.

* We acknowledge submitted issues by tagging them.

* Issues and PRs should address a single concern. If there are multiple
  concerns, make separate issues and/or PRs. For example, PRs should not tidy
  unrelated code.

* Best practice for non-trivial changes is to draft documentation and/or
  tests, get feedback on that, and then implement.

* If you are assigned an issue, that means you are actively working on it or
  will do so in the near future. "I'll get to this later" should not be
  assigned to you.

* PR review:

  * If you think you're done and it's ready to merge: Tag the PR :code:`ready
    to merge`. Don't request review from the project lead.

  * If you think you're done and want review from someone other than the
    project lead: Request review from that person using the GitHub web
    interface. Once the PR passes review, go to the previous item.

  * If you're not done but want feedback: Request review from the person you
    want to review, which can be the project lead.

  The purpose of this approach is to provide an easy way to see what PRs are
  ready to go, without the project lead needing to consult both the list of
  PRs and their own list of review requests, and also to provide a way to
  request reviews from the project lead without also requesting merge.

  Comments should all be packaged up into a single review; click *Start a
  review* rather than *Add single comment*. Then the PR author gets only a
  single notification instead of one for every comment you make.

* Closing issues: We close issues when we've taken the requested action,
  decided not to take action, resolved the question, or actively determined an
  issue is obsolete. It is OK for "stale" issues to sit around indefinitely
  awaiting this. Unlike many projects, we do not automatically close issues
  just because they're old.

* Stale PRs, on the other hand, are to be avoided due to bit rot. We try to
  either merge or reject PRs in a timely manner.

* Closed issues can be re-opened if new information arises, for example a
  :code:`worksforme` issue with new reproduction steps. Please comment to ask
  for re-opening rather than doing it yourself.

GitHub issue and PR tags
------------------------

What kind of issue is it?
~~~~~~~~~~~~~~~~~~~~~~~~~

:code:`bug`
  Problem of some kind that needs to be fixed; i.e., something doesn't work.
  This includes usability and documentation problems. Should have steps to
  reproduce with expected and actual behavior.

:code:`enhancement`
  Things work, but it would be better if something was different. For example,
  a new feature proposal or refactoring. Should have steps to reproduce with
  desired and actual behavior.

:code:`help wanted`
  The core team does not plan to address this issue, perhaps because we don't
  know how, but we think it would be good to address it. We hope someone from
  the community will volunteer.

:code:`key issue`
  A particularly important or notable issue.

:code:`question`
  Support request that does not report a problem or ask for a change.

What do we plan to do about it?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

For all of these, leave other tags in place, e.g. :code:`bug`.

:code:`deferred`
  No plans to do this, but not rejected. These issues stay open, because we do
  not consider the deferred state resolved. Submitting PRs on these issues is
  risky; you probably want to argue successfully that it should be done before
  starting work on it.

:code:`duplicate`
  Same as some other previously reported issue. In addition to this tag,
  duplicates should refer to the other issue and be closed.

:code:`obsolete`
  No longer relevant, moot, etc. Close.

:code:`erroneous`
  Not a Charliecloud issue; close. *Use caution when blaming a problem on user
  error. Often (or usually) there is a documentation or usability bug that
  caused the "user error".*

:code:`ready to merge`
  PRs only. Adding this tag states that the PR is complete and requests it be
  merged to master. If the project lead requests changes, they'll remove the
  tag. Re-add it when you're ready to try again. Lead removes tag after
  merging.

:code:`wontfix`
  We are not going to do this, and we won't merge PRs. Close issue after
  tagging, though sometimes you'll want to leave a few days to allow for
  further discussion to catch mistaken tags.

:code:`worksforme`
  We cannot reproduce the issue. Typical workflow is to tag, then wait a few
  days for clarification before closing.

Testing
-------

PRs will not be merged until they pass the tests.

* Tests should pass on your development box as well as all relevant clusters,
  in full scope. (Note that some of the examples take quite a long time to
  build; the Docker cache is your friend.)

* All the Travis tests should pass. If you're iterating trying to make Travis
  happy, consider interactive rebase, amending commits, or a throwaway branch.
  Don't submit a PR with half a dozen "fix Travis" commits.

* :code:`test/docker-clean.sh` can be used to purge your Docker cache, either
  by removing all tags or deleting all containers and images. The former is
  generally preferred, as it lets you update only those base images that have
  actually changed (the ones that haven't will be re-tagged).


Documentation
=============

.. _doc-build:

How to build the documentation
------------------------------

This documentation is built using Sphinx with the sphinx-rtd-theme. It lives
in :code:`doc-src`.

Prerequisites
~~~~~~~~~~~~~

  * Python 3.5+
  * Sphinx 1.4.9+
  * docutils 0.13.1+
  * sphinx-rtd-theme 0.2.4+

Older versions may work but are untested.

To build the HTML
~~~~~~~~~~~~~~~~~

Install the prerequisites::

  $ pip3 install sphinx sphinx-rtd-theme

Then::

  $ cd doc-src
  $ make

The HTML files are copied to :code:`doc` with :code:`rsync`. Anything to not
copy is listed in :code:`RSYNC_EXCLUDE`.

There is also a :code:`make clean` target that removes all the derived files
as well as everything in :code:`doc`.

.. note::

   If you're on Debian Stretch or some version of Ubuntu, this will silently
   install into :code:`~/.local`, leaving the :code:`sphinx-build` binary in
   :code:`~/.local/bin`, which is often not on your path. One workaround
   (untested) is to run :code:`pip3` as root, which violates principle of
   least privilege. A better workaround, assuming you can write to
   :code:`/usr/local`, is to add the undocumented and non-standard
   :code:`--system` argument to install in :code:`/usr/local` instead. (This
   matches previous :code:`pip` behavior.) See Debian bugs `725848
   <https://bugs.debian.org/725848>`_ and `820856
   <https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=820856>`_.

Publishing to the web
~~~~~~~~~~~~~~~~~~~~~

If you have write access to the repository, you can update the web
documentation (i.e., http://hpc.github.io/charliecloud).

Normally, :code:`doc` is a normal directory ignored by Git. To publish to the
web, that diretory needs to contain a Git checkout of the :code:`gh-pages`
branch (not a submodule). To set that up::

  $ rm -Rf doc
  $ git clone git@github.com:hpc/charliecloud.git doc
  $ cd doc
  $ git checkout gh-pages

To publish::

  $ make web

It sometimes takes a few minutes for the web pages to update.


Test suite
==========

Timing the tests
----------------

The :code:`ts` utility from :code:`moreutils` is quite handy. The following
prepends each line with the elapsed time since the previous line::

  $ CH_TEST_SCOPE=quick make test | ts -i '%M:%.S'

Note: a skipped test isn't free; I see ~0.15 seconds to do a skip.

Writing a test image using the standard workflow
------------------------------------------------

The Charliecloud test suite has a workflow that can build images by three
methods:

1. From a Dockerfile, using :code:`ch-build`.
2. By pulling a Docker image, with :code:`docker pull`.
3. By running a custom script.

To create an image that will be built, unpacked, and basic tests run within,
create a file in :code:`test/` called
:code:`{Dockerfile,Docker_Pull,Build}.foo`. This will create an image tagged
:code:`foo`.

To create an image with its own tests, documentation, etc., create a directory
in :code:`examples/*`. In this directory, place
:code:`{Dockerfile,Docker_Pull,Build}[.foo]` to build the image and
:code:`test.bats` with your tests. For example, the file
:code:`examples/mpi/foo/Dockerfile` will create an image tagged :code:`foo`,
and :code:`examples/mpi/foo/Dockerfile.bar` tagged :code:`foo-bar`. These
images also get the basic tests.

Image tags in the test suite must be unique.

Each of these image build files must specify its scope for building and
running, which must be greater than or equal than the scope of all tests in
the corresponding :code:`test.bats`. Exactly one of the following strings must
be in each file:

.. code-block:: none

  ch-test-scope: quick
  ch-test-scope: standard
  ch-test-scope: full

Other stuff on the line (e.g., comment syntax) is ignored.

Additional subdirectories can be symlinked into :code:`examples/` and will be
integrated into the test suite. This allows you to create a site-specific test
suite.

:code:`Dockerfile`:

  * It's a Dockerfile.

:code:`Docker_Pull`:

  * First line states the address to pull from Docker Hub.
  * Second line is a scope expression as described above.
  * Examples (these refer to the same image as of this writing):

    .. code-block:: none

      alpine:3.6
      alpine@sha256:f006ecbb824d87947d0b51ab8488634bf69fe4094959d935c0c103f4820a417d

:code:`Build`:

  * Script or program that builds the image.

  * Arguments:

    * :code:`$1`: Absolute path to directory containing :code:`Build`.

    * :code:`$2`: Absolute path and name of output archive, without extension.
      The script should use an archive format compatible with
      :code:`ch-tar2dir` and append the appropriate extension (e.g.,
      :code:`.tar.gz`).

    * :code:`$3`: Absolute path to appropriate temporary directory.

  * The script must not write anything in the current directory.

  * Temporary directory can be used for whatever and need not be cleaned up.
    It will be deleted by the test harness.

  * The first entry in :code:`$PATH` will be the Charliecloud under test,
    i.e., bare :code:`ch-*` commands will be the right ones.

  * The tarball must not contain leading directory components; top-level
    filesystem directories such as bin and usr must be at the root of the
    tarball with no leading path (:code:`./` is acceptable).

  * Any programming language is permitted. To be included in the Charliecloud
    source code, a language already in the prerequisites is required.

  * Exit codes:

    * 0: Image tarball successfully created.
    * 65: One or more prerequisites were not met.
    * else: An error occurred.


Coding style
============

We haven't written down a comprehensive style guide. Generally, follow the
style of the surrounding code, think in rectangles rather than lines of code
or text, and avoid CamelCase.

Note that Reid is very picky about style, so don’t feel singled out if he
complains (or even updates this section based on your patch!). He tries to be
nice about it.

Writing English
---------------

* When describing what something does (e.g., your PR or a command), use the
  `imperative mood <https://chris.beams.io/posts/git-commit/#imperative>`_,
  i.e., write the orders you are giving rather than describe what the thing
  does. For example, do:

    | Inject files from the host into an image directory.
    | Add :code:`--join-pid` option to :code:`ch-run`.

  Do not (indicative mood):

    | Injects files from the host into an image directory.
    | Adds :code:`--join-pid` option to :code:`ch-run`.

* Use sentence case for titles, not title case.

* If it's not a sentence, start with a lower-case character.

* Use spell check. Keep your personal dictionary updated so your editor is not
  filled with false positives.


:code:`curl` vs. :code:`wget`
-----------------------------

For URL downloading in shell code, including Dockerfiles, use :code:`wget -nv`.

Both work fine for our purposes, and we need to use one or the other
consistently. According to Debian's popularity contest, 99.88% of reporting
systems have :code:`wget` installed, vs. about 44% for :code:`curl`. On the
other hand, :code:`curl` is in the minimal install of CentOS 7 while
:code:`wget` is not.

For now, Reid just picked :code:`wget` because he likes it better.

Variable conventions in shell scripts and :code:`.bats` files
-------------------------------------------------------------

* Separate words with underscores.

* User-configured environment variables: all uppercase, :code:`CH_TEST_`
  prefix. Do not use in individual :code:`.bats` files; instead, provide an
  intermediate variable.

* Variables local to a given file: lower case, no prefix.

* Bats: set in :code:`common.bash` and then used in :code:`.bats` files: lower
  case, :code:`ch_` prefix.

* Surround lower-case variables expanded in strings with curly braces, unless
  they're the only thing in the string. E.g.:

  .. code-block:: none

    "${foo}/bar"  # yes
    "$foo"        # yes
    "$foo/bar"    # no
    "${foo}"      # no

* Quote the entire string instead of just the variable when practical:

  .. code-block:: none

    "${foo}/bar"  # yes
    "${foo}"/bar  # no
    "$foo"/bar    # no

* Don't quote variable assignments or other places where not needed (e.g.,
  case statements). E.g.:

  .. code-block:: none

    foo=${bar}/baz    # yes
    foo="${bar}/baz"  # no


..  LocalWords:  milestoned gh nv cht Chacon's scottchacon
