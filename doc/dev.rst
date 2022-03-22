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

We try to keep procedures and the Git branching model simple. Right now, we're
pretty similar to Scott Chacon's “`GitHub Flow
<http://scottchacon.com/2011/08/31/github-flow.html>`_”: Master is stable;
work on short-lived topic branches; use pull requests to ask for merging; keep issues organized with tags and milestones.

The standard workflow is:

  1. Propose a change in an issue.

  2. Tag the issue with its kind (bug, enhancement, question).

  3. Get consensus on what to do and how to do it, with key information
     recorded in the issue.

  4. Submit a PR that refers to the issue.

  5. Assign the issue to a milestone.

  6. Review/iterate.

  7. Project lead merges.

Core team members may deliberate in public on GitHub or internally, whichever
they are comfortable with, making sure to follow LANL policy and taking into
account the probable desires of the recipient as well.

Milestones
----------

We use milestones to organize what we plan to do next and what happened in a
given release. There are two groups of milestones:

* :code:`next` contains the issues that we plan to complete soon but have not
  yet landed on a specific release. Generally, we avoid putting PRs in here
  because of their ticking clocks.

* Each release has a milestone. These are dated with the target date for that
  release. We put an issue in when it has actually landed in that release or
  we are willing to delay that release until it does. We put a PR in when we
  think it's reasonably likely to be merged for that release.

If an issue is assigned to a person, that means they are actively leading the
work on it or will do so in the near future. Typically this happens when the
issue ends up in :code:`next`. Issues in a status of "I'll get to this later"
should not be assigned to a person.

Peer review
-----------

**Issues and pull requests.** The standard workflow is to introduce a change
in an issue, get consensus on what to do, and then create a *draft* `pull
request <https://git-scm.com/book/en/v2/GitHub-Contributing-to-a-Project>`_
(PR) for the implementation.

The issue, not the PR, should be tagged and milestoned so a given change shows
up only once in the various views.

If consensus is obtained through other means (e.g., in-person discussion),
then open a PR directly. In this case, the PR should be tagged and milestoned,
since there is no issue.

**Address a single concern.** When possible, issues and PRs should address
completely one self-contained change. If there are multiple concerns, make
separate issues and/or PRs. For example, PRs should not tidy unrelated code,
and non-essential complications should be split into a follow-on issue.

**Documentation and tests first.** The best practice for significant changes
is to draft documentation and/or tests first, get feedback on that, and then
implement the code. Reviews of the form "you need a completely different
approach" are no fun.

**Tests must pass.** PRs will not be merged until they pass the tests. While
this most saliently includes CI, the tests should also pass on your
development box as well as all relevant clusters (if appropriate for the
changes).

**No close keywords in PRs.** While GitHub will interpret issue-closing
keywords (variations on `"closes", "fixes", and "resolves"
<https://help.github.com/en/articles/closing-issues-using-keywords>`_) in PR
descriptions, don't use this feature, because often the specific issues a PR
closes change over time, and we don't want to have to edit the description to
deal with that. We also want this information in only one place (the commit
log). Instead, use "addresses", and we'll edit the keywords into the commit
message(s) at merge time if needed.

**PR review procedure.** When your draft PR is ready for review — which may or
may not be when you want it considered for merging! — do one or both of:

* Request review from the person(s) you want to look at it. If you think it
  may be ready for merge, that should include the project lead. The purpose of
  requesting review is so the person is notified you need their help.

* If you think it may be ready to merge (even if you're not sure), then also
  mark the PR "ready to review". The purpose of this is so the project lead
  can see which PRs are ready to consider for merging (green icon) and which
  are not (gray icon). If the project lead decides it's ready, they will
  merge; otherwise, they'll change it back to draft.

In both cases, the person from whom you requested review now owns the branch,
and you should stop work on it unless and until you get it back.

Do not hesitate to pester your reviewer if you haven't heard back promptly,
say within 24 hours.

*Special case 1:* Often, the review consists of code changes, and the reviewer
will want you to assess those changes. GitHub doesn't let you request review
from the PR submitter, so this must be done with a comment, either online or
offline.

*Special case 2:* GitHub will not let you request review from external people,
so this needs to be done with a comment too. Generally you should ask the
original bug reporter to review, to make sure it solves their problem.

**Use multi-comment reviews.** Review comments should all be packaged up into
a single review; click *Start a review* rather than *Add single comment*. Then
the PR author gets only a single notification instead of one for every comment
you make, and it's clear when they branch is theirs again.

Branching and merging
---------------------

**Don't commit directly to master.** Even the project lead doesn't do this.
While it may appear that some trivial fixes are being committed to the master
directly, what's really happening is that these are prototyped on a branch and
then fast-forward merged after the tests pass.

**Merging to master.** Only the project lead should do this.

**Branch merge procedure.** Generally, branches are merged in the GitHub web
interface with the *Squash and merge* button, which is :code:`git merge
--squash` under the hood. This squashes the branch into a single commit on
master. Commit message example::

  PR #268 from @j-ogas: remove ch-docker-run (closes #258)

If the branch closes multiple issues and it's reasonable to separate those
issues into independent commits, then the branch is rebased, interactively
squashed, and force-pushed into a tidy history with close instructions, then
merged in the web interface with *Create a merge commit*. Example history and
commit messages::

  * 18aa2b8 merge PR #254 from @j-ogas and me: Dockerfile.openmpi: use snapshot
  |\
  | * 79fa89a upgrade to ibverbs 20.0-1 (closes #250)
  | * 385ce16 Dockerfile.debian9: use snapshot.debian.org (closes #249)
  |/
  * 322df2f ...

The reason to prefer merge via web interface is that GitHub often doesn't
notice merges done on the command line.

After merge, the branch is deleted via the web interface.

**Branch history tidiness.** Commit frequently at semantically relevant times,
and keep in mind that this history will probably be squashed per above. It is
not necessary to rebase or squash to keep branch history tidy. But, don't go
crazy. Commit messages like "try 2" and "fix CI again" are a bad sign; so are
carefully proofread ones. Commit messages that are brief, technically
relevant, and quick to write are what you want on feature branches.

**Keep branches up to date.** Merge master into your branch, rather than
rebasing. This lets you resolve conflicts once rather than multiple times as
rebase works through a stack of commits.

Note that PRs with merge conflicts will generally not be merged. Resolve
conflicts before asking for merge.

**Remove obsolete branches.** Keep your repo free of old branches with
:code:`git branch -d` (or :code:`-D`) and :code:`git fetch --prune --all`.

Miscellaneous issue and pull request notes
------------------------------------------

**Acknowledging issues.** Issues and PRs submitted from outside should be
acknowledged promptly, including adding or correcting tags.

**Closing issues.** We close issues when we've taken the requested action,
decided not to take action, resolved the question, or actively determined an
issue is obsolete. It is OK for "stale" issues to sit around indefinitely
awaiting this. Unlike many projects, we do not automatically close issues just
because they're old.

**Closing PR.** Stale PRs, on the other hand, are to be avoided due to bit
rot. We try to either merge or reject PRs in a timely manner.

**Re-opening issues.** Closed issues can be re-opened if new information
arises, for example a :code:`worksforme` issue with new reproduction steps.

Continuous integration testing
------------------------------

**Quality of testing.** Tagged versions currently get more testing for various
reasons. We are working to improve testing for normal commits on master, but
full parity is probably unlikely.

**Cycles budget.** The resource is there for your use, so take advantage of
it, but be mindful of the various costs of this compute time.

Things you can do include testing locally first, cancelling jobs you know will
fail or that won't give you additional information, and not pushing every
commit (CI tests only the most recent commit in a pushed group).

**Iterating.** When trying to make CI happy, force-push or squash-merge. Don't
submit a PR with half a dozen "fix CI" commits.

**Purging Docker cache.** :code:`misc/docker-clean.sh` can be used to purge
your Docker cache, either by removing all tags or deleting all containers and
images. The former is generally preferred, as it lets you update only those
base images that have actually changed (the ones that haven't will be
re-tagged).

Issue labeling
--------------

We use the following labels (a.k.a. tags) to organize issues. Each issue (or
stand-alone PR) should have label(s) from every category, with the exception
of disposition which only applies to closed issues.

Charliecloud team members should label their own issues. Members of the
general public are more than welcome to label their issues if they like, but
in practice this is rare, which is fine. Whoever triages the incoming issue
should add or adjust labels as needed.

.. note::

   This scheme is designed to organize open issues only. There have been
   previous schemes, and we have not re-labeled closed issues.

What kind of change is it?
~~~~~~~~~~~~~~~~~~~~~~~~~~

Choose *one type* from:

:code:`bug`
  Something doesn't work; e.g., it doesn't work as intended or it was
  mis-designed. This includes usability and documentation problems. Steps to
  reproduce with expected and actual behavior are almost always very helpful.

:code:`enhancement`
  Things work, but it would be better if something was different. For example,
  a new feature proposal, an improvement in how a feature works, or clarifying
  an error message. Steps to reproduce with desired and current behavior are
  often helpful.

:code:`refactor`
  Change that will improve Charliecloud but does not materially affect
  user-visible behavior. Note this doesn't mean "invisible to the user"; even
  user-facing documentation or logging changes could feasibly be this, if they
  are more cleanup-oriented.

How important/urgent is it?
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Choose *one priority* from:

:code:`high`
  High priority.

:code:`medium`
  Medium priority.

:code:`low`
  Low priority. Note: Unfortunately, due to resource limitations, complex
  issues here are likely to wait a long time, perhaps forever. If that makes
  you particularly sad on a particular issue, please comment to say why. Maybe
  it's mis-prioritized.

:code:`deferred`
  No plans to do this, but not rejected. These issues stay open, because we do
  not consider the deferred state resolved. Submitting PRs on these issues is
  risky; you probably want to argue successfully that it should be done before
  starting work on it.

Priority is indeed required, though it can be tricky because the levels are
fuzzy. Do not hesitate to ask for advice. Considerations include: is customer
or development work blocked by the issue; how valuable is the issue for
customers; does the issue affect key customers; how many customers are
affected; how much of Charliecloud is affected; what is the workaround like,
if any. Difficulty of the issue is not a factor in priority, i.e., here we are
trying to express benefit, not cost/benefit ratio. Perhaps the `Debian bug
severity levels <https://www.debian.org/Bugs/Developer#severities>`_ provide
inspiration. The number of :code:`high` priority issues should be relatively
low.

In part because priority is quite imprecise, issues are not a priority queue,
i.e., we do work on lower-priority issues while higher-priority ones are still
open. Related to this, issues do often move between priority levels. In
particular, if you think we picked the wrong priority level, please say so.

What part of Charliecloud is affected?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Choose *one or more components* from:

:code:`runtime`
  The container runtime itself; largely :code:`ch-run`.

:code:`image`
  Image building and interaction with image registries; largely
  :code:`ch-image`. (Not to be confused with image management tasks done by
  glue code.)

:code:`glue`
  The “glue” that ties the runtime and image management (:code:`ch-image` or
  another builder) together. Largely shell scripts in :code:`bin`.

:code:`install`
  Charliecloud build & install system, packaging, etc. (Not to be confused
  with image building.)

:code:`doc`
  Documentation.

:code:`test`
  Test suite and examples.

:code:`misc`
  Everything else. Do not combine with another component.

Special considerations
~~~~~~~~~~~~~~~~~~~~~~

Choose *one or more extras* from:

:code:`blocked`
  We can't do this yet because something else needs to happen first. If that
  something is another issue, mention it in a comment.

:code:`hpc`
  Related specifically to HPC and HPC scaling considerations; e.g.,
  interactions with job schedulers.

:code:`uncertain`
  Course of action is unclear. For example: is the feature a good idea,
  what is a good approach to solve the bug, what additional information is
  needed.

:code:`usability`
  Affects usability of any part of Charliecloud, including documentation and
  project organization.

Why was it closed?
~~~~~~~~~~~~~~~~~~

If the issue was resolved (i.e., bug fixed or enhancement/refactoring
implemented), there is no disposition tag. Otherwise, to explain why not,
choose *one disposition* from:

:code:`cantfix`
  The issue is not something we can resolve. Typically problems with other
  software, problems with containers in general that we can't work around, or
  not actionable due to clarity or other reasons. *Use caution when blaming a
  problem on user error. Often (or usually) there is a documentation or
  usability bug that caused the "user error".*

:code:`discussion`
  Converted to a discussion. The most common use is when someone asks a
  question rather than making a request for some change.

:code:`duplicate`
  Same as some other issue. In addition to this tag, duplicates should refer
  to the other issue in a comment to record the link. Of the duplicates, the
  better one should stay open (e.g., clearer reproduction steps); if they are
  roughly equal in quality, the older one should stay open.

:code:`moot`
  No longer relevant. Examples: withdrawn by reporter, fixed in current
  version (use :code:`duplicate` instead if it applies though), obsoleted by
  change in plans.

:code:`wontfix`
  We are not going to do this, and we won't merge PRs. Sometimes you'll want
  to tag and then wait a few days before closing, to allow for further
  discussion to catch mistaken tags.

:code:`worksforme`
  We cannot reproduce a bug, and it seems unlikely this will change given
  available information. Typically you'll want to tag, then wait a few days
  for clarification before closing. Bugs closed with this tag that do gain a
  reproducer later should definitely be re-opened. For some bugs, it really
  feels like they should be reproducible but we're missing it somehow; such
  bugs should be left open in hopes of new insight arising.

Deprecated labels
~~~~~~~~~~~~~~~~~

You might see these on old issues, but they are no longer in use.

* :code:`help wanted`: This tended to get stale and wasn't generating any
  leads.

* :code:`key issue`: Replaced by priority labels.

* :code:`question`: Replaced by Discussions. (If you report a bug that seems
  to be a discussion, we'll be happy to convert it to you.)


Test suite
==========

Timing the tests
----------------

The :code:`ts` utility from :code:`moreutils` is quite handy. The following
prepends each line with the elapsed time since the previous line::

  $ ch-test -s quick | ts -i '%M:%.S'

Note: a skipped test isn't free; I see ~0.15 seconds to do a skip.

:code:`ch-test` complains about inconsistent versions
-----------------------------------------------------

There are multiple ways to ask Charliecloud for its version number. These
should all give the same result. If they don't, :code:`ch-test` will fail.
Typically, something needs to be rebuilt. Recall that :code:`configure`
contains the version number as a constant, so a common way to get into this
situation is to change Git branches without rebuilding it.

Charliecloud is small enough to just rebuild everything with::

  $ ./autogen.sh && ./configure && make clean && make

Special images
--------------

For images not needed after completion of a test, tag them :code:`tmpimg`.
This leaves only one extra image at the end of the test suite.

Writing a test image using the standard workflow
------------------------------------------------

Summary
~~~~~~~

The Charliecloud test suite has a workflow that can build images by two
methods:

1. From a Dockerfile, using :code:`ch-image` or another builder (see
   :code:`common.bash:build_()`).

2. By running a custom script.

To create an image that will be built and unpacked and/or mounted, create a
file in :code:`examples` (if the image recipe is useful as an example) or
:code:`test` (if not) called :code:`{Dockerfile,Build}.foo`. This will create
an image tagged :code:`foo`. Additional tests can be added to the test suite
Bats files.

To create an image with its own tests, documentation, etc., create a directory
in :code:`examples`. In this directory, place
:code:`{Dockerfile,Build}[.foo]` to build the image and :code:`test.bats` with
your tests. For example, the file :code:`examples/foo/Dockerfile` will create
an image tagged :code:`foo`, and :code:`examples/foo/Dockerfile.bar` tagged
:code:`foo-bar`. These images also get the build and unpack/mount tests.

Additional directories can be symlinked into :code:`examples` and will be
integrated into the test suite. This allows you to create a site-specific test
suite. :code:`ch-test` finds tests at any directory depth; e.g.
:code:`examples/foo/bar/Dockerfile.baz` will create a test image tagged
:code:`bar-baz`.

Image tags in the test suite must be unique.

Order of processing; within each item, alphabetical order:

1. Dockerfiles in :code:`test`.
2. :code:`Build` files in :code:`test`.
3. Dockerfiles in :code:`examples`.
4. :code:`Build` files in :code:`examples`.

The purpose of doing :code:`Build` second is so they can leverage what has
already been built by a Dockerfile, which is often more straightforward.

How to specify when to include and exclude a test image
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Each of these image build files must specify its scope for building and
running, which must be greater than or equal than the scope of all tests in
any corresponding :code:`.bats` files. Exactly one of the following strings
must appear:

.. code-block:: none

  ch-test-scope: quick
  ch-test-scope: standard
  ch-test-scope: full

Other stuff on the line (e.g., comment syntax) is ignored.

Optional test modification directives are:

  :code:`ch-test-arch-exclude: ARCH`
    If the output of :code:`uname -m` matches :code:`ARCH`, skip the file.

  :code:`ch-test-builder-exclude: BUILDER`
    If using :code:`BUILDER`, skip the file.

  :code:`ch-test-builder-include: BUILDER`
    If specified, run only if using :code:`BUILDER`. Can be repeated to
    include multiple builders. If specified zero times, all builders are
    included.

  :code:`ch-test-need-sudo`
    Run only if user has sudo.

How to write a :code:`Dockerfile` recipe
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

It's a standard Dockerfile.

How to write a :code:`Build` recipe
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This is an arbitrary script or program that builds the image. It gets three
command line arguments:

  * :code:`$1`: Absolute path to directory containing :code:`Build`.

  * :code:`$2`: Absolute path and name of output image, without extension.
    This can be either:

    * Tarball compressed with gzip or xz; append :code:`.tar.gz` or
      :code:`.tar.xz` to :code:`$2`. If :code:`ch-test --pack-fmt=squash`,
      then this tarball will be unpacked and repacked as a SquashFS.
      Therefore, only use tarball output if the image build process naturally
      produces it and you would have to unpack it to get a directory (e.g.,
      :code:`docker export`).

    * Directory; use :code:`$2` unchanged. The contents of this directory will
      be packed without any enclosing directory, so if you want an enclosing
      directory, include one. Hidden (dot) files in :code:`$2` will be ignored.

  * :code:`$3`: Absolute path to temporary directory for use by the script.
    This can be used for whatever and need no be cleaned up; the test harness
    will delete it.

Other requirements:

  * The script may write only in two directories: (a) the parent directory of
    :code:`$2` and (b) :code:`$3`. Specifically, it may not write to the
    current working directory. Everything written to the parent directory of
    :code:`$2` must have a name starting with :code:`$(basename $2)`.

  * The first entry in :code:`$PATH` will be the Charliecloud under test,
    i.e., bare :code:`ch-*` commands will be the right ones.

  * Any programming language is permitted. To be included in the Charliecloud
    source code, a language already in the test suite dependencies is
    required.

  * The script must test for its dependencies and fail with appropriate error
    message and exit code if something is missing. To be included in the
    Charliecloud source code, all dependencies must be something we are
    willing to install and test.

  * Exit codes:

    * 0: Image successfully created.
    * 65: One or more dependencies were not met.
    * 126 or 127: No interpreter available for script language (the shell
      takes care of this).
    * else: An error occurred.


Building RPMs
=============

We maintain :code:`.spec` files and infrastructure for building RPMs in the
Charliecloud source code. This is for two purposes:

  1. We maintain our own Fedora RPMs (see `packaging guidelines
     <https://docs.fedoraproject.org/en-US/packaging-guidelines/>`_).

  2. We want to be able to build an RPM of any commit.

Item 2 is tested; i.e., if you break the RPM build, the test suite will fail.

This section describes how to build the RPMs and the pain we've hopefully
abstracted away.

Dependencies
------------

  * charliecloud
  * Python 3.6+
  * Either:

    * the provided example :code:`centos7` or :code:`centos8` image
    * a RHEL/CentOS 7 or newer container image with (note there are different
      python version names for the listed packages in RHEL/CentOS 8):
      * autoconf
      * automake
      * gcc
      * make
      * python36
      * python36-sphinx
      * python36-sphinx_rtd_theme
      * rpm-build
      * rpmlint
      * rsync


:code:`rpmbuild` wrapper script
-------------------------------

While building the Charliecloud RPMs is not too weird, we provide a script to
streamline it. The purpose is to (a) make it easy to build versions not
matching the working directory, (b) use an arbitrary :code:`rpmbuild`
directory, and (c) build in a Charliecloud container for non-RPM-based
environments.

The script must be run from the root of a Charliecloud Git working directory.

Usage::

  $ packaging/fedora/build [OPTIONS] IMAGE VERSION

Options:

  * :code:`--install` : Install the RPMs after building into the build
    environment.

  * :code:`--rpmbuild=DIR` : Use RPM build directory root :code:`DIR`
    (default: :code:`~/rpmbuild`).

For example, to build a version 0.9.7 RPM from the CentOS 7 image provided
with the test suite, on any system, and leave the results in
:code:`~/rpmbuild/RPMS` (note the test suite would also build the
necessary image directory)::

  $ bin/ch-image build -t centos7 -f ./examples/Dockerfile.centos7 ./examples
  $ bin/ch-convert centos7 $CH_TEST_IMGDIR/centos7
  $ packaging/fedora/build $CH_TEST_IMGDIR/centos7 0.9.7-1

To build a pre-release RPM of Git HEAD using the CentOS 7 image::

  $ bin/ch-image build -t centos7 -f ./examples/Dockerfile.centos7 ./examples
  $ bin/ch-convert centos7 $CH_TEST_IMGDIR/centos7
  $ packaging/fedora/build ${CH_TEST_IMGDIR}/centos7 HEAD

Gotchas and quirks
------------------

RPM versions and releases
~~~~~~~~~~~~~~~~~~~~~~~~~

If :code:`VERSION` is :code:`HEAD`, then the RPM version will be the content
of :code:`VERSION.full` for that commit, including Git gobbledygook, and the
RPM release will be :code:`0`. Note that such RPMs cannot be reliably upgraded
because their version numbers are unordered.

Otherwise, :code:`VERSION` should be a released Charliecloud version followed
by a hyphen and the desired RPM release, e.g. :code:`0.9.7-3`.

Other values of :code:`VERSION` (e.g., a branch name) may work but are not
supported.

Packaged source code and RPM build config come from different commits
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The spec file, :code:`build` script, :code:`.rpmlintrc`, etc. come from the
working directory, but the package source is from the specified commit. This
is what enables us to make additional RPM releases for a given Charliecloud
release (e.g. 0.9.7-2).

Corollaries of this policy are that RPM build configuration can be any or no
commit, and it's not possible to create an RPM of uncommitted source code.

Changelog maintenance
~~~~~~~~~~~~~~~~~~~~~

The spec file contains a manually maintained changelog. Add a new entry for
each new RPM release; do not include the Charliecloud release notes.

For released versions, :code:`build` verifies that the most recent changelog
entry matches the given :code:`VERSION` argument. The timestamp is not
automatically verified.

For other Charliecloud versions, :code:`build` adds a generic changelog entry
with the appropriate version stating that it's a pre-release RPM.


.. _build-ova:

Style hints
===========

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

Documentation
-------------

Heading underline characters:

  1. Asterisk, :code:`*`, e.g. "5. Contributor's guide"
  2. Equals, :code:`=`, e.g. "5.7 OCI technical notes"
  3. Hyphen, :code:`-`, e.g. "5.7.1 Gotchas"
  4. Tilde, :code:`~`, e.g. "5.7.1.1 Namespaces" (try to avoid)

.. _dependency-policy:

Dependency policy
-----------------

Specific dependencies (prerequisites) are stated elsewhere in the
documentation. This section describes our policy on which dependencies are
acceptable.

Generally
~~~~~~~~~

All dependencies must be stated and justified in the documentation.

We want Charliecloud to run on as many systems as practical, so we work hard
to keep dependencies minimal. However, because Charliecloud depends on new-ish
kernel features, we do depend on standards of similar vintage.

Core functionality should be available even on small systems with basic Linux
distributions, so dependencies for run-time and build-time are only the bare
essentials. Exceptions, to be used judiciously:

  * Features that add convenience rather than functionality may have
    additional dependencies that are reasonably expected on most systems where
    the convenience would be used.

  * Features that only work if some other software is present (example: the
    Docker wrapper scripts) can add dependencies of that other software.

The test suite is tricky, because we need a test framework and to set up
complex test fixtures. We have not yet figured out how to do this at
reasonable expense with dependencies as tight as run- and build-time, so there
are systems that do support Charliecloud but cannot run the test suite.

Building the documentation needs Sphinx features that have not made their way
into common distributions (i.e., RHEL), so we use recent versions of Sphinx
and provide a source distribution with pre-built documentation.

Building the RPMs should work on RPM-based distributions with a kernel new
enough to support Charliecloud. You might need to install additional packages
(but not from third-party repositories).


:code:`curl` vs. :code:`wget`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

C code
------

:code:`const`
~~~~~~~~~~~~~

The :code:`const` keyword is used to indicate that variables are read-only. It
has a variety of uses; in Charliecloud, we use it for `function pointer
arguments <https://softwareengineering.stackexchange.com/a/204720>`_ to state
whether or not the object pointed to will be altered by the function. For
example:

.. code-block:: c

  void foo(const char *in, char *out)

is a function that will not alter the string pointed to by :code:`in` but may
alter the string pointed to by :code:`out`. (Note that :code:`char const` is
equivalent to :code:`const char`, but we use the latter order because that's
what appears in GCC error messages.)

We do not use :code:`const` on local variables or function arguments passed by
value. One could do this to be more clear about what is and isn't mutable, but
it adds quite a lot of noise to the source code, and in our evaluations didn't
catch any bugs. We also do not use it on double pointers (e.g., :code:`char
**out` used when a function allocates a string and sets the caller's pointer
to point to it), because so far those are all out-arguments and C has
`confusing rules <http://c-faq.com/ansi/constmismatch.html>`_ about double
pointers and :code:`const`.

Lists
~~~~~

The general convention is to use an array of elements terminated by an element
containing all zeros (i.e., every byte is zero). While this precludes zero
elements within the list, it makes it easy to iterate:

.. code-block:: c

  struct foo { int a; float b; };
  struct foo *bar = ...;
  for (int i = 0; bar[i].a != 0; i++)
     do_stuff(bar[i]);

Note that the conditional checks that only one field of the struct (:code:`a`)
is zero; this loop leverages knowledge of this specific data structure that
checking only :code:`a` is sufficient.

Lists can be set either as literals:

.. code-block:: c

  struct foo bar[] = { {1, 2.0}, {3, 4.0}, {0, 0.0} };

or built up from scratch on the heap; the contents of this list are
equivalent (note the C99 trick to avoid create a :code:`struct foo` variable):

.. code-block:: c

  struct foo baz;
  struct foo *qux = list_new(sizeof(struct foo), 0);
  baz.a = 1;
  baz.b = 2.0;
  list_append((void **)&qux, &baz, sizeof(struct foo));
  list_append((void **)&qux, &((struct foo){3, 4.0}), sizeof(struct foo));

This form of list should be used unless some API requires something else.

.. warning::

  Taking the address of an array in C yields the address of the first element,
  which is the same thing. For example, consider this list of strings, i.e.
  pointers to :code:`char`:

  .. code-block:: c

    char foo[] = "hello";
    char **list = list_new(sizeof(char *), 0)
    list_append((void **)list, &foo, sizeof(char *));  // error!

  Because :code:`foo == &foo`, this will add to the list not a pointer to
  :code:`foo` but the *contents* of :code:`foo`, i.e. (on a machine with
  64-bit pointers) :code:`'h'`, :code:`'e'`, :code:`'l'`, :code:`'l'`,
  :code:`'o'`, :code:`'\0'` followed by two bytes of whatever follows
  :code:`foo` in memory.

  This would work because :code:`bar != &bar`:

  .. code-block:: c

    char foo[] = "hello";
    char bar = foo;
    char **list = list_new(sizeof(char *), 0)
    list_append((void **)list, &bar, sizeof(char *));  // OK

Logging
-------

Charliecloud uses reasonably standard log levels for its stderr logging. The
verbosity can be increased by up to three :code:`-v` command line arguments.
Both the Python and C code use the same levels by calling logging functions
named by level. The main error can be accompanied by a hint. The levels are:

  1. **FATAL**; always printed. Some error condition that makes it impossible
     to proceed. The program exits unsuccessfully immediately after printing
     the error. Examples: unknown image type, Dockerfile parse error.

  2. **WARNING**; always printed. Unexpected condition the user needs to know
     about but that should not stop the program. Examples: :code:`ch-run
     --mount` with a directory image (which does not use a mount point),
     unsupported Dockerfile instructions that are ignored.

  3. **INFO**; always printed. Chatter useful enough to always be printed.
     Example: progress messages during image download and unpacking. Note
     :code:`ch-run` is silent during normal operations and does not have any
     INFO logging.

  4. **VERBOSE**; printed if :code:`-v` or more. Diagnostic information useful
     for debugging user containers, the Charliecloud installation, and
     Charliecloud itself. Examples: :code:`ch-run --join` coordination
     progress, :code:`ch-image` internal paths, Dockerfile parse tree.

  5. **DEBUG**; printed if :code:`-vv` or more. More detailed diagnostic
     information useful for debugging Charliecloud. Examples: data structures
     unserialized from image registry metadata JSON, image reference parse
     tree.

  6. **TRACE**; printed if :code:`-vvv`. Grotesquely detailed diagnostic
     information for debugging Charliecloud, to the extent it interferes with
     normal use. A sensible person might use a `debugger
     <https://twitter.com/wesamo__/status/1464764461831663626>`_ instead.
     Examples: component-by-component progress of bind-mount target directory
     analysis/creation, text of image registry JSON, every single file
     unpacked from image layers.

There is no level ERROR; anything important the user needs to know about is
WARNING if we can safely proceed or FATAL if not.

.. warning::

   Do not use INFO for *output*. For example, the results of :code:`ch-image
   list` just use plain :code:`print()` to stdout.


OCI technical notes
===================

This section describes our analysis of the Open Container Initiative (OCI)
specification and implications for our implementations of :code:`ch-image`, and
:code:`ch-run-oci`. Anything relevant for users goes in the respective man
page; here is for technical details. The main goals are to guide Charliecloud
development and provide and opportunity for peer-review of our work.


ch-run-oci
----------

Currently, :code:`ch-run-oci` is only tested with Buildah. These notes
describe what we are seeing from Buildah's runtime expectations.

Gotchas
~~~~~~~

Namespaces
""""""""""

Buildah sets up its own user and mount namespaces before invoking the runtime,
though it does not change the root directory. We do not understand why. In
particular, this means that you cannot see the container root filesystem it
provides without joining those namespaces. To do so:

#. Export :code:`CH_RUN_OCI_LOGFILE` with some logfile path.
#. Export :code:`CH_RUN_OCI_DEBUG_HANG` with the step you want to examine
   (e.g., :code:`create`).
#. Run :code:`ch-build -b buildah`.
#. Make note of the PID in the logfile.
#. :code:`$ nsenter -U -m -t $PID bash`

Supervisor process and maintaining state
""""""""""""""""""""""""""""""""""""""""

OCI (and thus Buildah) expects a process that exists throughout the life of
the container. This conflicts with Charliecloud's lack of a supervisor process.

Bundle directory
~~~~~~~~~~~~~~~~

* OCI documentation (very incomplete): https://github.com/opencontainers/runtime-spec/blob/master/bundle.md

The bundle directory defines the container and is used to communicate between
Buildah and the runtime. The root filesystem (:code:`mnt/rootfs`) is mounted
within Buildah's namespaces, so you'll want to join them before examination.

:code:`ch-run-oci` has restrictions on bundle directory path so it can be
inferred from the container ID (see the man page). This lets us store state in
the bundle directory instead of maintaining a second location for container
state.

Example::

   # cd /tmp/buildah265508516
   # ls -lR . | head -40
   .:
   total 12
   -rw------- 1 root root 3138 Apr 25 16:39 config.json
   d--------- 2 root root   40 Apr 25 16:39 empty
   -rw-r--r-- 1 root root  200 Mar  9  2015 hosts
   d--x------ 3 root root   60 Apr 25 16:39 mnt
   -rw-r--r-- 1 root root   79 Apr 19 20:23 resolv.conf

   ./empty:
   total 0

   ./mnt:
   total 0
   drwxr-x--- 19 root root 380 Apr 25 16:39 rootfs

   ./mnt/rootfs:
   total 0
   drwxr-xr-x  2 root root 1680 Apr  8 14:30 bin
   drwxr-xr-x  2 root root   40 Apr  8 14:30 dev
   drwxr-xr-x 15 root root  720 Apr  8 14:30 etc
   drwxr-xr-x  2 root root   40 Apr  8 14:30 home
   [...]

Observations:

#. The weird permissions on :code:`empty` (000) and :code:`mnt` (100) persist
   within the namespaces, so you'll want to be namespace root to look around.

#. :code:`hosts` and :code:`resolv.conf` are identical to the host's.

#. :code:`empty` is still an empty directory with in the namespaces. What is
   this for?

#. :code:`mnt/rootfs` contains the container root filesystem. It is a tmpfs.
   No other new filesystems are mounted within the namespaces.

:code:`config.json`
~~~~~~~~~~~~~~~~~~~

* OCI documentation:

  * https://github.com/opencontainers/runtime-spec/blob/master/config.md
  * https://github.com/opencontainers/runtime-spec/blob/master/config-linux.md

This is the meat of the container configuration. Below is an example
:code:`config.json` along with commentary and how it maps to :code:`ch-run`
arguments. This was pretty-printed with :code:`jq . config.json`, and we
re-ordered the keys to match the documentation.

There are a number of additional keys that appear in the documentation but not
in this example. These are all unsupported, either by ignoring them or
throwing an error. The :code:`ch-run-oci` man page documents comprehensively
what OCI features are and are not supported.

.. code-block:: javascript

   {
     "ociVersion": "1.0.0",

We validate that this is "1.0.0".

.. code-block:: javascript

     "root": {
       "path": "/tmp/buildah115496812/mnt/rootfs"
     },

Path to root filesystem; maps to :code:`NEWROOT`. If key :code:`readonly` is
:code:`false` or absent, add :code:`--write`.

.. code-block:: javascript

     "mounts": [
       {
         "destination": "/dev",
         "type": "tmpfs",
         "source": "/dev",
         "options": [
           "private",
           "strictatime",
           "noexec",
           "nosuid",
           "mode=755",
           "size=65536k"
         ]
       },
       {
         "destination": "/dev/mqueue",
         "type": "mqueue",
         "source": "mqueue",
         "options": [
           "private",
           "nodev",
           "noexec",
           "nosuid"
         ]
       },
       {
         "destination": "/dev/pts",
         "type": "devpts",
         "source": "pts",
         "options": [
           "private",
           "noexec",
           "nosuid",
           "newinstance",
           "ptmxmode=0666",
           "mode=0620"
         ]
       },
       {
         "destination": "/dev/shm",
         "type": "tmpfs",
         "source": "shm",
         "options": [
           "private",
           "nodev",
           "noexec",
           "nosuid",
           "mode=1777",
           "size=65536k"
         ]
       },
       {
         "destination": "/proc",
         "type": "proc",
         "source": "/proc",
         "options": [
           "private",
           "nodev",
           "noexec",
           "nosuid"
         ]
       },
       {
         "destination": "/sys",
         "type": "bind",
         "source": "/sys",
         "options": [
           "rbind",
           "private",
           "nodev",
           "noexec",
           "nosuid",
           "ro"
         ]
       },
       {
         "destination": "/etc/hosts",
         "type": "bind",
         "source": "/tmp/buildah115496812/hosts",
         "options": [
           "rbind"
         ]
       },
       {
         "destination": "/etc/resolv.conf",
         "type": "bind",
         "source": "/tmp/buildah115496812/resolv.conf",
         "options": [
           "rbind"
         ]
       }
     ],

This says what filesystems to mount in the container. It is a mix; it has
tmpfses, bind-mounts of both files and directories, and other
non-device-backed filesystems. The docs suggest a lot of flexibility,
including stuff that won't work in an unprivileged user namespace (e.g.,
filesystems backed by a block device).

The things that matter seem to be the same as Charliecloud defaults.
Therefore, for now we just ignore mounts.

We do add :code:`--no-home` in OCI mode.

.. code-block:: javascript

     "process": {
       "terminal": true,

This says that Buildah wants a pseudoterminal allocated. Charliecloud does not
currently support that, so we error in this case.

However, Buildah can be persuaded to set this :code:`false` if you redirect
its standard input from :code:`/dev/null`, which is the current workaround.
Things work fine.

.. code-block:: javascript

       "cwd": "/",

Maps to :code:`--cd`.

.. code-block:: javascript

       "args": [
         "/bin/sh",
         "-c",
         "apk add --no-cache bc"
       ],

Maps to :code:`CMD [ARG ...]`. Note that we do not run :code:`ch-run` via the
shell, so there aren't worries about shell parsing.

.. code-block:: javascript

       "env": [
         "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
         "https_proxy=http://proxyout.lanl.gov:8080",
         "no_proxy=localhost,127.0.0.1,.lanl.gov",
         "HTTP_PROXY=http://proxyout.lanl.gov:8080",
         "HTTPS_PROXY=http://proxyout.lanl.gov:8080",
         "NO_PROXY=localhost,127.0.0.1,.lanl.gov",
         "http_proxy=http://proxyout.lanl.gov:8080"
       ],

Environment for the container. The spec does not say whether this is the
complete environment or whether it should be added to some default
environment.

We treat it as a complete environment, i.e., place the variables in a file and
then :code:`--unset-env='*' --set-env=FILE`.

.. code-block:: javascript

       "rlimits": [
         {
           "type": "RLIMIT_NOFILE",
           "hard": 1048576,
           "soft": 1048576
         }
       ]

Process limits Buildah wants us to set with :code:`setrlimit(2)`. Ignored.

.. code-block:: javascript

       "capabilities": {
         ...
       },

Long list of capabilities that Buildah wants. Ignored. (Charliecloud provides
security by remaining an unprivileged process.)

.. code-block:: javascript

       "user": {
         "uid": 0,
         "gid": 0
       },
     },

Maps to :code:`--uid=0 --gid=0`.

.. code-block:: javascript

     "linux": {
       "namespaces": [
         {
           "type": "pid"
         },
         {
           "type": "ipc"
         },
         {
           "type": "mount"
         },
         {
           "type": "user"
         }
       ],

Namespaces that Buildah wants. Ignored; Charliecloud just does user and mount.

.. code-block:: javascript

       "uidMappings": [
         {
           "hostID": 0,
           "containerID": 0,
           "size": 1
         },
         {
           "hostID": 1,
           "containerID": 1,
           "size": 65536
         }
       ],
       "gidMappings": [
         {
           "hostID": 0,
           "containerID": 0,
           "size": 1
         },
         {
           "hostID": 1,
           "containerID": 1,
           "size": 65536
         }
       ],

Describes the identity map between the namespace and host. Buildah wants it
much larger than Charliecloud's single entry and asks for container root to be
host root, which we can't do. Ignored.

.. code-block:: javascript

       "maskedPaths": [
         "/proc/acpi",
         "/proc/kcore",
         ...
       ],
       "readonlyPaths": [
         "/proc/asound",
         "/proc/bus",
         ...
       ]

Spec says to "mask over the provided paths ... so they cannot be read" and
"sed the provided paths as readonly". Ignored. (Unprivileged user namespace
protects us.)

.. code-block:: javascript

     }
   }

End of example.

State
~~~~~

The OCI spec does not say how the JSON document describing state should be
given to the caller. Buildah is happy to get it on the runtime's standard
output.

:code:`ch-run-oci` provides an OCI compliant state document. Status
:code:`creating` will never be returned, because the create operation is
essentially a no-op, and annotations are not supported, so the
:code:`annotations` key will never be given.

Additional sources
~~~~~~~~~~~~~~~~~~

* :code:`buildah` man page: https://github.com/containers/buildah/blob/master/docs/buildah.md
* :code:`buildah bud` man page: https://github.com/containers/buildah/blob/master/docs/buildah-bud.md
* :code:`runc create` man page: https://raw.githubusercontent.com/opencontainers/runc/master/man/runc-create.8.md
* https://github.com/opencontainers/runtime-spec/blob/master/runtime.md


ch-image
--------

pull
~~~~

Images pulled from registries come with OCI metadata, i.e. a "config blob".
This is stored verbatim in :code:`/ch/config.pulled.json` for debugging.
Charliecloud metadata, which includes a translated subset of the OCI config,
is kept up to date in :code:`/ch/metadata.json`.

push
~~~~

Image registries expect a config blob at push time. This blob consists of both
OCI runtime and image specification information.

* OCI run-time and image documentation:

  * https://github.com/opencontainers/runtime-spec/blob/master/config.md
  * https://github.com/opencontainers/image-spec/blob/master/config.md

Since various OCI features are unsupported by Charliecloud we push only what is
necessary to satisfy general image registry requirements.

The pushed config is created on the fly, referencing the image's metadata
and layer tar hash. For example, including commentary:

.. code-block:: javascript

    {
      "architecture": "amd64",
      "charliecloud_version": "0.26",
      "comment": "pushed with Charliecloud",
      "config": {},
      "container_config": {},
      "created": "2021-12-10T20:39:56Z",
      "os": "linux",
      "rootfs": {
        "diff_ids": [
          "sha256:607c737779a53d3a04cbd6e59cae1259ce54081d9bafb4a7ab0bc863add22be8"
        ],
        "type": "layers"
      },
      "weirdal": "yankovic"

The fields above are expected by the registry at push time, with the exception
of :code:`charliecloud_version` and :code:`weirdal`, which are Charliecloud
extensions.

.. code-block:: javascript

      "history": [
        {
          "created": "2021-11-17T02:20:51.334553938Z",
          "created_by": "/bin/sh -c #(nop) ADD file:cb5ed7070880d4c0177fbe6dd278adb7926e38cd73e6abd582fd8d67e4bbf06c in / ",
          "empty_layer": true
        },
        {
          "created": "2021-11-17T02:20:51.921052716Z",
          "created_by": "/bin/sh -c #(nop)  CMD [\"bash\"]",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:08Z",
          "created_by": "FROM debian:buster",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:19Z",
          "created_by": "RUN ['/bin/sh', '-c', 'apt-get update     && apt-get install -y        bzip2        wget     && rm -rf /var/lib/apt/lists/*']",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:19Z",
          "created_by": "WORKDIR /usr/local/src",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:19Z",
          "created_by": "ARG MC_VERSION='latest'",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:19Z",
          "created_by": "ARG MC_FILE='Miniconda3-latest-Linux-x86_64.sh'",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:21Z",
          "created_by": "RUN ['/bin/sh', '-c', 'wget -nv https://repo.anaconda.com/miniconda/$MC_FILE']",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:33Z",
          "created_by": "RUN ['/bin/sh', '-c', 'bash $MC_FILE -bf -p /usr/local']",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:33Z",
          "created_by": "RUN ['/bin/sh', '-c', 'rm -Rf $MC_FILE']",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:33Z",
          "created_by": "RUN ['/bin/sh', '-c', 'which conda && conda --version']",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:34Z",
          "created_by": "RUN ['/bin/sh', '-c', 'conda config --set auto_update_conda False']",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:14:34Z",
          "created_by": "RUN ['/bin/sh', '-c', 'conda config --add channels conda-forge']",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:15:07Z",
          "created_by": "RUN ['/bin/sh', '-c', 'conda install --yes obspy']",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:15:07Z",
          "created_by": "WORKDIR /",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:15:08Z",
          "created_by": "RUN ['/bin/sh', '-c', 'wget -nv http://examples.obspy.org/RJOB_061005_072159.ehz.new']",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:15:08Z",
          "created_by": "COPY ['hello.py'] -> '.'",
          "empty_layer": true
        },
        {
          "created": "2021-11-30T20:15:08Z",
          "created_by": "RUN ['/bin/sh', '-c', 'chmod 755 ./hello.py']"
        }
      ],
    }

The history section is collected from the image's metadata and
:code:`empty_layer` added to all entries except the last to represent a
single-layer image. This is needed because Quay checks that the number of
non-empty history entries match the number of pushed layers.

Miscellaneous notes
===================

Updating bundled Lark parser
----------------------------

In order to change the version of the bundled lark parser you must modify
multiple files. To find them, e.g. for version 0.11.3 (the regex is hairy to
catch both dot notation and tuples, but not the list of filenames in
:code:`lib/Makefile.am`)::

  $ misc/grep -E '0(\.|, )11(\.|, )3($|\s|\))'

What to do in each location should either be obvious or commented.


..  LocalWords:  milestoned gh nv cht Chacon's scottchacon mis cantfix tmpimg
..  LocalWords:  rootfs cbd cae ce bafb bc weirdal yankovic nop cb fbe adb fd
..  LocalWords:  abd bbf LOGFILE logfile
