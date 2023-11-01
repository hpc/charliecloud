# Note on how we use Git:
#
# Git is extremely flexible and can be configured in many ways, including
# various configuration files [1] as well as environment variables [2]. We do
# our best to use a fully-isolated Git that brings along no external
# configuration the user or system may have, by excluding configuration files
# other than Charliecloud’s and clearing the environment.
#
# Another gotcha that is not (yet?) documented is $PATH. git(1) re-executes
# itself in the same way that it was invoked; e.g., if you invoke it with
# plain “git”, which looks up the binary in the path, then sub-invocations
# will do the same and look up “git” again [3]. If somehow you use different
# paths to find the outer and inner Git — which is easy to do accidentally
# with subprocess — you can run a mixed-version Git, which is bad (see #1606).
# We work around this by looking up git(1) once and then calling it by its
# absolute path, with an empty environment including unset $PATH.
#
# Alternately, we could have sanitized the environment more carefully, passing
# through $PATH and perhaps other variables. This seemed difficult to do
# correctly (e.g., should we keep $LD_LIBRARY_PATH?), and it seemed unlikely
# that Git would be executing programs other than Git that weren’t readily
# available in the standard paths or using any non-standard features.
#
# [1]: https://git-scm.com/book/en/v2/Customizing-Git-Git-Configuration
# [2]: https://git-scm.com/book/en/v2/Git-Internals-Environment-Variables
# [3]: https://lore.kernel.org/git/E7D87B07-C416-4A58-8726-CCDA0907AC66@lanl.gov/t/#u

import configparser
import datetime
import glob
import hashlib
import itertools
import os
import pickle
import re
import shutil
import stat
import tempfile
import textwrap

import charliecloud as ch
import image as im
import filesystem as fs
import pull


## Constants ##

# Required versions.
DOT_MIN = (2, 30, 1)
GIT_MIN = (2, 28, 1)
GIT2DOT_MIN = (0, 8, 3)

# Git configuration. Note some of these are overridden in specific commands.
# Documentation for these variables: https://git-scm.com/docs/git-config
GIT_CONFIG = {
   # Do parallel checkouts with all cores.
   "checkout.workers":       "-1",
   # Prioritize write speed over data safety; i.e., increase the risk of cache
   # corruption on system crash while (hopefully) decreasing write speed.
   "core.fsync":             "none",
   # We want to keep access to commits on deleted branches so they are still
   # available for cache hits. This setting is necessary but not sufficient;
   # see branch_delete() below.
   "core.logAllRefUpdates":  "true",
   # Try to maximize “git add” speed.
   "core.looseCompression":  "0",
   # Enable incremental indexes [1]; it should speed things like “git add”.
   # [1]: https://git-scm.com/docs/git-update-index
   "core.splitIndex":        "true",
   # “ctime” marks when the file *or its inode* was last changed. Twiddling
   # the various metadata will alter this, so Git shouldn’t use it when
   # deciding if a file may have changed.
   "core.trustctime":        "false",
   # Enable the “untracked cache” [1], which saves directory mtimes to
   # eliminate the need to re-stat(2) in some cases.
   # [1]: https://git-scm.com/docs/git-update-index
   "core.untrackedCache":    "true",
   # Quick-and-dirty results suggest that commit is not faster after garbage
   # collection, and checkout is actually a little faster if *not* garbage
   # collected. Therefore, it’s not a high priority to run garbage collection.
   # Further, I would assume garbaging a lot of files rather than a few gives
   # better opportunities for delta compression. Our most file-ful example
   # image is obspy at about 50K files.
   "gc.auto":                "100000",
   # Leave packs larger than this alone during automatic GC. This is to avoid
   # excessive resource consumption during GC the user didn’t ask for.
   "gc.bigPackThreshold":    "12G",
   # Anything unreachable from a named branch or the reflog is unavailable to
   # the build cache, so we may as well delete it immediately. However, there
   # might be a concurrent Git operation in progress, so don’t use “now”.
   "gc.pruneExpire":         "12.hours.ago",
   # Use the newest index version, which does “simple pathname compression
   # that reduces index size by 30%-50% on large repositories” [1].
   # [1]: https://git-scm.com/docs/git-update-index
   "index.version":          "4",
   # Print logs in short format by default. This helps ensure consistency
   # across different systems and git versions.
   "log.decorate":           "short",
   # States on the reflog are available to the build cache, but the default
   # prune time is 90 and 30 days respectively, which seems too long.
   #"gc.reflogExpire":        "14.days.ago",  # changed my mind
   # In some quick-and-dirty tests (see issue #1412), pack.compression=1 is
   # 50% faster than the default 6 at the cost of 6% more size, while
   # Compression 0 is twice as fast but also over twice the size; 9 doubles
   # the time with no space savings. 1 seems like the right balance.
   "pack.compression":       "1",
   # These two are guesses based on the fact that HPC machines tend to have a
   # lot of memory and more caching is faster.
   "pack.deltaCacheLimit":   "4096",
   "pack.deltaCacheSize":    "1G",
   # These two are guesses based on [1] and its links, particularly [2].
   # [1]: https://stackoverflow.com/questions/28720151
   # [2]: https://web.archive.org/web/20170526024841/https://vcscompare.blogspot.com/2008/06/git-repack-parameters.html
   "pack.depth":             "36",
   "pack.window":            "24",
   # Our Git repo is purely local, so it doesn’t really matter who owns the
   # commits. Set these in case the user hasn’t configured them and they can’t
   # be guessed. (Issue #1535.)
   "user.email":             "charlie@localhost",
   "user.name":              "Charlie",
   # Always fail if Git doesn’t know who the user is, rather than guessing if
   # possible. Makes #1535 happen for everyone.
   "user.useConfigOnly":     "true",
}

# Placeholder for Git hash values that are unknown. This deliberately does not
# support str operations (e.g., indexing), so trying those will fail loudly.
GIT_HASH_UNKNOWN = -1


## Globals ##

# The active build cache.
cache = None

# Path to DOT output (.gv and .pdf will be appended)
dot_base = None

# Absolute path of Git binary we’re using.
git = None

# Default path within image to metadata pickle.
PICKLE_PATH = fs.Path("ch/git.pickle")


## Functions ##

def have_deps(required=True):
   """Return True if dependencies for the build cache are present, False
      otherwise. Note this does not include the --dot debugging option; that
      checks its own dependencies when invoked.

      This function also figures out which Git to use and sets the appropriate
      variables."""
   global git
   git = shutil.which("git")
   if (git is None):
      (ch.FATAL if required else ch.VERBOSE)("no git(1) found")
      return False
   # As of 2.34.1, we get: "git version 2.34.1\n".
   return ch.version_check([git, "--version"], GIT_MIN, required=required)

def have_dot():
   ch.version_check(["git2dot.py", "--version"], GIT2DOT_MIN)
   ch.version_check(["dot", "-V"], DOT_MIN)

def init(cli):
   # At this point --bucache is what the user wanted, either directly or via
   # --no-cache. If it’s None, chose the right default; otherwise, try what
   # the user asked for and fail if we can’t do it.
   if (cli.bucache != ch.Build_Mode.DISABLED):
      ok = have_deps(False)
      if (cli.bucache is None):
         cli.bucache = ch.Build_Mode.ENABLED if ok else ch.Build_Mode.DISABLED
         ch.VERBOSE("using default build cache mode")
      if (cli.bucache != ch.Build_Mode.DISABLED and not ok):
         ch.FATAL("insufficient Git for build cache mode: %s"
                  % cli.bucache.value)
   # Set cache appropriately. We could also do this with a factory method, but
   # that seems overkill.
   global cache
   if (cli.bucache == ch.Build_Mode.ENABLED):
      cache = Enabled_Cache(cli.cache_large)
   elif (cli.bucache == ch.Build_Mode.REBUILD):
      cache = Rebuild_Cache(cli.cache_large)
   elif (cli.bucache == ch.Build_Mode.DISABLED):
      cache = Disabled_Cache(cli.cache_large)
   else:
      assert False, "unreachable"
   ch.VERBOSE("build cache mode: %s" % cache)
   # DOT output path
   try:
      global dot_base
      dot_base = cli.dot
   except AttributeError:
      pass


## Supporting classes ##

class File_Metadata:

   # This class holds metadata we care about for a file (in the general sense,
   # not necessarily a regular file), along with methods for dealing with that
   # metadata for the build cache. This includes re-creating some files from
   # their metadata, for files that Git can’t store or breaks.
   #
   # Importantly, this class must support un-pickling of old versions of
   # itself, to support existing build caches on upgrade. At present, we do
   # this attribute-by-attribute, without explicit versioning. We omit
   # __slots__ so old versions with since-deleted attributes can be unpickled.
   #
   # Note that ctime can’t be restored: https://unix.stackexchange.com/a/36105
   #
   # Attributes corresponding directly to inode(7) fields (and pickled):
   #
   #   atime_ns
   #   mtime_ns
   #   mode
   #
   #   size .......... Size of the file in bytes. Note large file thresholds
   #                   vary between builds, so this attribute should not be
   #                   used to determine if a file is in large file storage.
   #                   WARNING: May be -1 if read from an old pickle.
   #
   # Other attributes stored in pickle:
   #
   #   children ...... Insertion-ordered mapping from child names to their
   #                   File_Metadata objects. Empty if non-directory, or upon
   #                   object creation (i.e., caller must assemble the tree).
   #
   #   dont_restore .. If True, file should not be restored (e.g., RPM
   #                   database cache files).
   #
   #   large_name .... If non-None, file is stored out-of-band as a large file
   #                   with this name. This is a function of all the
   #                   attributes that make file large-unique, i.e., two files
   #                   with the same large_name are considered the same file.
   #
   #   hardlink_to ... If non-None, file is a hard link to this other file,
   #                   stored as a Path object relative to the image root.
   #
   #   xattrs ........ Extended attributes of the file, stored as a dictionary.
   #                   The keys take the form “namespace.name”, where
   #                   “namespace” is the namespace the xattr belongs to (e.g.
   #                   “user” or “system”) and “name” is the actual name of the
   #                   xattr. The value in the dictionary is the value assigned
   #                   to the xattr.
   #
   # Attributes not stored (recomputed on unpickle):
   #
   #   image_root .... Absolute path to the image directory to which path is
   #                   relative. That is, image_root // path is the absolute
   #                   version of path.
   #
   #   path .......... Path to the file within the image, relative to the
   #                   image root. Empty for the image root itself. For
   #                   example, an image’s “/bin/true” has path “bin/true”.
   #
   #   path_abs ...... Absolute path to the file (under the host root).
   #
   #   st ............ Stat object for the file. Absent after un-pickling.

   def __init__(self, image_root, path):
      self.image_root = image_root
      self.path = path
      self.path_abs = image_root // path
      self.st = self.path_abs.stat_(False)
      # Note: Constructor not called during unpickle.
      for attr in ("atime_ns", "mtime_ns", "mode", "size"):
         setattr(self, attr, getattr(self.st, "st_" + attr))
      self.children = dict()
      self.dont_restore = False
      self.hardlink_to = None
      self.large_name = None
      self.xattrs = dict()
      if ch.save_xattrs:
         for xattr in ch.ossafe("can’t list xattrs: %s" % self.path_abs,
                                os.listxattr, self.path_abs,
                                follow_symlinks=False):
            self.xattrs[xattr] = \
               ch.ossafe(("can’t get xattr: %s: %s"
                                       % (self.path_abs, xattr)),
                         os.getxattr, self.path_abs, xattr,
                         follow_symlinks=False)

   def __getstate__(self):
      return { a:v for (a,v) in self.__dict__.items()
                   if (a not in { "image_root", "path", "path_abs", "st" }) }

   @property
   def empty_dir_p(self):
      """True if I represent either an empty directory, or a directory that
         contains only children where empty_dir_p is true. E.g., the root of a
         directory tree containing only empty directories returns true."""
      # In principle this could do a lot of recursion, but in practice I’m
      # guessing it’s not too much.
      if (not stat.S_ISDIR(self.mode)):
         return False  # not a directory
      # True if no children (truly empty directory), or each child is unstored
      # or empty_dir_p (recursively empty directory tree).
      return all((c.unstored or c.empty_dir_p) for c in self.children.values())

   @property
   def unstored(self):
      """True if I represent something not stored, either ignored by Git or
         deleted by us before committing."""
      return (   stat.S_ISFIFO(self.mode)
              or stat.S_ISSOCK(self.mode)
              or self.large_name is not None
              or self.hardlink_to is not None)

   @classmethod
   def git_prepare(class_, image_root, large_file_thresh,
                   path=None, hardlinks=None):
      """Recursively walk the given image root, prepare it for a Git commit,
         and return the resulting File_Metadata tree describing it. This is
         mostly reversed by git_restore_walk(); anything not is noted.

         path is the path relative to image_root currently being examined;
         hardlinks is a dictionary used to track what hard link groups have
         been seen already. External callers should pass None.

         For each file, in this order:

           1. Record file metadata, specifically mode and timestamps, because
              Git does not save metadata beyond a limited executable bit.
              (More may be saved in the future; see issue #1287.)

              This captures FIFOs (named pipes), which are ignored by Git.

              Exception: Sockets are ignored. Like FIFOs, sockets are ignored
              by Git, but there isn’t a meaningful way to re-create them.
              Their presence in a container image that is not in use, which
              this image shouldn’t be, most likely reflects a bug in
              something. We do print a warning in this case.

           2. For directories, record the number of children. Git does not
              save empty directories, so this is used to re-create them.

           3. For devices, exit with error. Such files should not appear in
              unprivileged container images, so their presence means something
              is wrong.

           4. For non-directories with link count greater than 1 (i.e., hard
              links), do nothing when the first link is encountered, but
              second and subsequent links are deleted, to be restored on
              checkout. (Git splits multiply-linked files into separate
              files, and directories cannot be hard-linked [1].)

           5. Files special due to their name:

              a. Names starting in “.git” are special to Git. Therefore,
                 except at the root where “.git” files support the cache’s Git
                 worktree, rename them to begin with “.weirdal_” instead.

              b. Files matching the pattern /var/lib/rpm/__db.* are Berkeley
                 DB database support files used by RPM. Sometimes, something
                 mishandles the last-modified dates on these files, fooling
                 Git into thinking they have not been modified, and so they
                 don’t get committed or restored, which confuses BDB/RPM.
                 Fortunately, they can be safely deleted, and that’s a simple
                 workaround, so we do it. See issue #1351.

         Return the File_Metadata tree, and if write is True, also save it in
         “ch/git.pickle”.

         [1]: https://en.wikipedia.org/wiki/Hard_link#Limitations"""
      # Setup.
      if (path is None):
         assert (hardlinks is None)
         path = fs.Path()
         hardlinks = dict()
      fm = class_(image_root, path)
      if (fm.path == im.GIT_DIR):
         # skip Git stuff at image root
         fm.dont_restore = True
         return fm
      # Ensure minimum permissions. Some tools like to make files with mode
      # 000, because root ignores the permissions bits.
      fm.path_abs.chmod_min(fm.st)
      # Validate file type and recurse if needed. (Don’t use os.walk() because
      # it’s iterative, and our algorithm is better expressed recursively.)
      if   (   stat.S_ISREG(fm.mode)
            or stat.S_ISLNK(fm.mode)
            or stat.S_ISFIFO(fm.mode)):
         # RPM databases get corrupted. Easy fix is delete them. See #1351.
         if (path.match("var/lib/rpm/__db.*")):
            ch.VERBOSE("deleting, see issue #1351: %s" % path)
            fm.path_abs.unlink()
            fm.dont_restore = True
            return fm
      elif (   stat.S_ISSOCK(fm.mode)):
         ch.WARNING("socket in image, deleting: %s" % path)
         fm.path_abs.unlink()
         fm.dont_restore = True
         return fm
      elif (   stat.S_ISCHR(fm.mode)
            or stat.S_ISBLK(fm.mode)):
         ch.FATAL("device files invalid in image: %s" % path)
      elif (   stat.S_ISDIR(fm.mode)):
         entries = sorted(fm.path_abs.listdir())
         for i in entries:
            # Recurse
            fm.children[i] = class_.git_prepare(image_root, large_file_thresh,
                                                path // i, hardlinks)
      else:
         ch.FATAL("unexpected file type in image: %x: %s"
                  % (stat.IFMT(fm.mode), path))
      # Deal with hard links (directories can’t be hard-linked).
      if (fm.st.st_nlink > 1 and not stat.S_ISDIR(fm.mode)):
         if ((fm.st.st_dev, fm.st.st_ino) in hardlinks):
            ch.DEBUG("hard link: deleting subsequent: %d %d %s"
                     % (fm.st.st_dev, fm.st.st_ino, path))
            fm.hardlink_to = hardlinks[(fm.st.st_dev, fm.st.st_ino)]
            fm.path_abs.unlink_()
            return fm
         else:
            ch.DEBUG("hard link: recording first: %d %d %s"
                     % (fm.st.st_dev, fm.st.st_ino, path))
            hardlinks[(fm.st.st_dev, fm.st.st_ino)] = path
      # Deal with large files. This comparison is a little sloppy (no files
      # named “git.pickle” are large, not just the one in /ch), but it works
      # for now.
      if (    fm.size >= large_file_thresh
          and stat.S_ISREG(fm.mode)
          and fm.path.name != PICKLE_PATH.name
          and fm.hardlink_to is None):
         fm.large_name = fm.large_prepare()
      else:
         fm.large_name = None
      # Remove empty directories. Git will ignore them, including leaving them
      # there when switching the worktree to a different branch, which is bad.
      if (fm.empty_dir_p):
         fm.path_abs.rmdir_()
         return fm
      # Remove FIFOs for the same reason.
      if (stat.S_ISFIFO(fm.mode)):
         fm.path_abs.unlink()
         return fm
      # Rename if necessary.
      if (path.git_incompatible_p):
         ch.DEBUG("renaming: %s -> %s" % (path, path.git_escaped))
         fm.path_abs.rename_(fm.path_abs.git_escaped)
      # Done.
      return fm

   @classmethod
   def unpickle(self, image_root, data=None):
      if (data is None):
         data = (image_root // PICKLE_PATH).file_read_all(text=False)
      fm_tree = pickle.loads(data)
      fm_tree.unpickle_fix(image_root, path=fs.Path("."))
      return fm_tree

   def get(self, path):
      "Return the File_Metadata object at path."
      fm = self
      for name in path.parts:
         fm = fm.children[name]
      return fm

   def git_restore(self, quick):
      #ch.TRACE(self.str_for_log())  # output is extreme even for TRACE?
      # Do-nothing case. Exclude RPM databases explicitly because old caches
      # can have them left over without being tagged don’t restore.
      if (self.dont_restore or self.path.match("var/lib/rpm/__db.*")):
         if (not quick and self.path != im.GIT_DIR):
            ch.INFO("ignoring un-restorable file: /%s" % self.path)
         return
      # Make sure I exist, and with the correct name.
      if (self.hardlink_to is not None):
         # This relies on prepare and restore having the same traversal order,
         # so the first (stored) link is always available by the time we get
         # to subsequent (unstored) links.
         target = self.image_root // self.hardlink_to
         ch.DEBUG("hard link: restoring: %s -> %s" % (self.path_abs, target))
         ch.ossafe("can’t hardlink: %s -> %s" % (self.path_abs,
                                                       target),
                   os.link, target, self.path_abs, follow_symlinks=False)
      elif (self.large_name is not None):
         self.large_restore()
      elif (self.empty_dir_p):
         ch.ossafe("can’t mkdir: %s" % self.path, os.mkdir, self.path_abs)
      elif (stat.S_ISFIFO(self.mode)):
         ch.ossafe("can’t make FIFO: %s" % self.path, os.mkfifo, self.path_abs)
      elif (self.path.git_incompatible_p):
         self.path_abs.git_escaped.rename_(self.path_abs)
      for (xattr, val) in self.xattrs.items():
         self.path_abs.setxattr(xattr, val, follow_symlinks=False)
      # Recurse children.
      if (len(self.children) > 0):
         for child in self.children.values():
            child.git_restore(quick)
      # Restore my metadata.
      if ((   not quick                      # Git broke metadata
           or self.hardlink_to is not None   # we just made the hardlink
           or stat.S_ISDIR(self.mode)        # maybe just created or modified
           or stat.S_ISFIFO(self.mode))      # we just made the FIFO
          and not stat.S_ISLNK(self.mode)):  # can’t not follow symlinks
         ch.ossafe("can’t restore times: %s" % self.path_abs, os.utime,
                   self.path_abs, ns=(self.atime_ns, self.mtime_ns))
         ch.ossafe("can’t restore mode: %s" % self.path_abs, os.chmod,
                   self.path_abs, stat.S_IMODE(self.mode))

   def large_name_get(self):
      "Return my name for use in large file storage."
      assert (self.size >= 0)
      h = hashlib.md5()
      for attr in ("mtime_ns", "mode", "size", "path"):
         h.update(bytes(repr(getattr(self, attr)).encode("UTF-8")))
      # The digest is unique, but add an encoded path to aid debugging.
      return (  h.hexdigest() + "%"
              + str(self.path).replace("/", "%"))[:ch.FILENAME_MAX_CHARS]

   def large_names(self):
      "Return a set containing the large names of myself and all descendants."
      if (self.large_name is None):
         names = set()
      else:
         names = { self.large_name }
      for c in self.children.values():
         names |= c.large_names()
      return names

   def large_prepare(self):
      """Move my file to large file storage, or delete it if it already
         exists, then return the appropriate large name."""
      large_name = self.large_name_get()
      target = ch.storage.build_large_path(large_name)
      if (target.exists_()):
         op = "found"
         self.path_abs.unlink_()
      else:
         op = "moving to"
         self.path_abs.rename_(target)
      ch.DEBUG("large file: %s: %s: %s" % (self.path, op, large_name))
      return large_name

   def large_restore(self):
      "Restore large file from OOB storage."
      target = ch.storage.build_large_path(self.large_name)
      ch.DEBUG("large file: %s: copying: %s" % (self.path_abs, self.large_name))
      fs.copy(target, self.path_abs)

   def pickle(self):
      (self.image_root // PICKLE_PATH) \
         .file_write(pickle.dumps(self, protocol=4))

   def str_for_log(self):
      # Truncate reported time to seconds.
      fmt = "%Y-%m-%d.%H:%M:%S"
      mstr = datetime.datetime.fromtimestamp(self.mtime_ns // 1e9).strftime(fmt)
      astr = datetime.datetime.fromtimestamp(self.mtime_ns // 1e9).strftime(fmt)
      return ("%s%s %s [%d %d %s %s %s %s %s] %s %s"
              % ("  " * len(self.path), stat.filemode(self.mode),
                 self.path.name, self.size, len(self.children),
                 "dont_restore" if self.dont_restore else "-",
                 "empty_dir" if self.empty_dir_p else "-",
                 "unstored" if self.unstored else "-",
                 mstr, astr,
                 self.hardlink_to if self.hardlink_to else "-",
                 self.large_name if self.large_name else "-"))

   def unpickle_fix(self, image_root, path):
      "Does no I/O."
      # old: large_name, size, xattrs: no such attribute
      if (not (hasattr(self, "large_name"))):
         self.large_name = None
      if (not (hasattr(self, "size"))):
         self.size = -1
      if (not (hasattr(self, "xattrs"))):
         self.xattrs = dict()
      # old: hardlink_to: stored as string
      if (isinstance(self.hardlink_to, str)):
         self.hardlink_to = fs.Path(self.hardlink_to)
      # old: children, name: just a list, and instances know their names
      if (isinstance(self.children, list)):
         children_new = dict()
         for c in self.children:
            children_new[c.name] = c
            delattr(c, "name")
         self.children = children_new
      # all: set non-stored attributes
      self.image_root = image_root
      self.path = path
      self.path_abs = image_root // path
      # recurse
      for (name, child) in self.children.items():
         child.unpickle_fix(image_root, path // name)

   def update(self, path):
      "Recompute the File_Metadata object at path in the tree rooted by me."
      # FIXME: Can’t handle anything other than regular, non-large files that
      # don’t need renaming.
      assert (stat.S_ISDIR(self.mode) and len(path) >= 1)
      fm = self
      for name in path.parts[:-1]:
         fm = fm.children[name]
      fm.children[path.name] = self.__class__(self.image_root, path)
      assert (stat.S_ISREG(fm.children[path.name].mode))


class State_ID:

   __slots__ = ('id_')

   def __init__(self, id_):
      # Constructor should only be called internally, so verify id_ type.
      assert (isinstance(id_, bytes))
      self.id_ = id_

   @classmethod
   def from_parent(class_, psid, input_):
      """Return the State_ID corresponding to parent State_ID psid and data
         input_ describing the transition, which can be either bytes or str."""
      h = hashlib.md5(psid.id_)
      if (isinstance(input_, str)):
         input_ = input_.encode("UTF-8")
      h.update(input_)
      return class_(h.digest())

   @classmethod
   def from_text(class_, text):
      """The argument is stringified; then this string must end with 32 hex
         digits, possibly interspersed with other characters. Any preceding
         characters are ignored."""
      text = re.sub(r"[^0-9A-Fa-f]", "", str(text))[-32:]
      if (len(text) < 32):
         ch.FATAL("state ID too short: %s" % text)
      try:
         b = bytes.fromhex(text)
      except ValueError:
         ch.FATAL("state ID: malformed hex: %s" % text);
      return class_(b)

   @property
   def short(self):
      return str(self)[:4]

   def __eq__(self, other):
      return self.id_ == other.id_

   def __hash__(self):
      return hash(self.id_)

   def __str__(self):
      s = self.id_.hex().upper()
      return ":".join((s[0:4], s[4:8], s[8:16], s[16:24], s[24:32]))


## Main classes ##

class Enabled_Cache:

   root_id =   State_ID.from_text("4A6F:73C3:A9204361:7061626C:616E6361")

   __slots__ = ("bootstrap_ct",
                "file_metadata",
                "large_threshold")

   def __init__(self, large_threshold):
      self.bootstrap_ct = 0
      self.large_threshold = large_threshold
      if (not os.path.isdir(self.root)):
         self.root.mkdir()
      ls = self.root.listdir()
      if (len(ls) == 0):
         self.bootstrap()      # empty; initialize a new cache
      elif (not {"HEAD", "objects", "refs"} <= ls):
         # Non-empty but not an existing cache.
         # See: https://git-scm.com/docs/gitrepository-layout
         ch.FATAL("storage broken: not a build cache: %s" % self.root)
      else:
         self.configure()         # updates config if needed
      self.worktrees_fix()

   def __str__(self):
      return ("enabled (large=%g)" % self.large_threshold)

   @property
   def root(self):
      return ch.storage.build_cache

   @staticmethod
   def branch_name_ready(ref):
      return ref.for_path

   @staticmethod
   def branch_name_unready(ref):
      return ref.for_path + "#"

   @staticmethod
   def commit_hash_p(commit_ish):
      """Return True if commit_ish looks like a commit hash, False otherwise.
         Note this is a text-based heuristic only. It will return True for
         hashes that don’t exist in the repo, and false positives for
         branch/tag names that look like hashes."""
      return (re.search(r"^[0-9a-f]{7,}$", commit_ish) is not None)

   def adopt(self, img):
      self.worktree_adopt(img, "root")
      img.metadata_load()
      img.metadata_save()
      log = "IMPORT %s" % img.ref
      sid = self.sid_from_parent(self.root_id, log)
      gh = self.commit(img.unpack_path, sid, log, [])
      self.ready(img)
      return (sid, gh)

   def bootstrap(self):
      ch.INFO("initializing empty build cache")
      self.bootstrap_ct += 1
      # Initialize bare repo. Don’t use wrapper because the build cache
      # doesn’t exist yet.
      ch.cmd_quiet([git, "init", "--bare", "-b", "root", self.root], env={})
      self.configure()
      # Create empty root commit. This is done in a strange way with no real
      # working directory at all, because (1) cloning the bucache doesn’t
      # clone the config, which we care about, and (2) worktrees cannot be
      # used on empty repositories.
      # See: https://stackoverflow.com/a/29396902/396038
      try:
         with tempfile.TemporaryDirectory(prefix="weirdal.") as td:
            env = { "GIT_DIR": self.root,
                    "GIT_WORK_TREE": td,
                    "GIT_INDEX_FILE": "%s/bootstrap-index" % td }
            self.git(["read-tree", "--empty"], env=env)
            # Note: complaints about empty commits go to stdout, not stderr.
            self.git(["commit", "--allow-empty",
                                "-m", "ROOT\n\n%s" % self.root_id], env=env)
      except OSError as x:
         ch.FATAL("can’t create or delete temporary directory: %s: %s"
                  % (x.filename, x.strerror))

   def branch_delete(self, branch):
      """Delete branch branch if it exists; otherwise, do nothing. This
         removes only the branch ref; its commits remain until garbage
         collected."""
      # Note: in a typical Git working directory, HEAD has followed the branch
      # around, so when we delete a branch ref *and necessarily its reflog
      # too*, that branch’s commits remain accessible via HEAD’s reflog until
      # the reflog entries expire. However, in our case, it’s the worktree
      # HEAD that did the following, and that reflog goes away when the
      # worktree is deleted, so the branch’s commits become inaccessible
      # immediately upon branch deletion. Here, the first “update-ref”
      # shenanigan logs the branch tip in the bare repo’s HEAD reflog, keeping
      # the commits accessible. The second puts HEAD back where it was.
      branches = [branch]
      if (self.ready_p(branch) and (self.cached_p(branch))):
         branches.append(self.unready_of(branch))
         # Tag deleted branch. This is allows images to be recovered with
         # “undelete.” Note that the “-f” flag overwrites existing tags with the
         # same name, meaning we only track the most recently deleted branch.
         self.git(["tag", "-a", "-f", "&%s" % branch, branch, "-m", "''"])
      for brnch in branches:
         if (self.git(["show-ref", "--quiet", "--heads", brnch],
                     fail_ok=True).returncode == 0): # branch found
            head_old = self.git(["rev-parse", "HEAD"]).stdout.strip()
            self.git(["update-ref", "HEAD", brnch])
            self.git(["update-ref", "HEAD", head_old])
            self.git(["branch", "-D", brnch])


   def branch_nocheckout(self, src_ref, dest):
      """Create ready branch for Ref src_ref pointing to dest, which can
         be either an Ref or a Git commit reference (as a string)."""
      if (isinstance(dest, im.Reference)):
         dest = self.branch_name_ready(dest)
      # Some versions of Git won’t let us update a branch that’s already
      # checked out, so detach that worktree if it exists.
      src_img = im.Image(src_ref)
      if (src_img.unpack_exist_p):
         self.git(["checkout", "--detach"], cwd=src_img.unpack_path)
      self.git(["branch", "-f", self.branch_name_ready(src_ref), dest])

   def cached_p(self, git_id):
      """True iff image corresponding to “git_id” is in the cache."""
      return self.find_commit(git_id)[1] != None

   def checkout(self, image, git_hash, base_image):
      # base_image used in other subclasses
      self.worktree_add(image, git_hash)
      self.git_restore(image.unpack_path, [], False)

   def checkout_ready(self, image, git_hash, base_image=None):
      """“checkout()” followed by “ready()” is an operation that appears several
         times throughout the code, so we wrap it here."""
      self.checkout(image, git_hash, base_image)
      self.ready(image)

   def commit(self, path, sid, msg, files):
      # Commit image at path into the build cache. If set files is empty, any
      # and all image content may have been changed. Otherwise, assume files
      # lists the only files in the image that have changed. These must be
      # relative paths relative to the image root (i.e., path), may only be
      # regular files, and get none of the special handling we have for
      # general image content.
      #
      # WARNING: files must be empty for the first image commit.
      self.git_prepare(path, files)
      t = ch.Timer()
      if (len(files) == 0):
         git_files = ["-A"]
      else:
         git_files = list(files) + ["ch/git.pickle"]
      self.git(["add"] + git_files, cwd=path)
      t.log("prepared index")
      t = ch.Timer()
      self.git(["commit", "-q", "--allow-empty",
                          "-m", "%s\n\n%s" % (msg, sid)], cwd=path)
      t.log("committed")
      # “git commit” does print the new commit’s hash without “-q”, but it
      # also prints every file commited, which is rather enormous for us.
      # Therefore, retrieve the hash separately.
      cp = self.git(["rev-parse", "--short", "HEAD"], cwd=path)
      git_hash = cp.stdout.strip()
      self.git_restore(path, files, True)
      return git_hash

   def commit_find_deleted(self, git_id):
         deleted = self.git(["log", "--format=%h%n%B", "-n", "1",
                           "&%s" % git_id],fail_ok=True)
         if (deleted.returncode == 0):
            # Commit was previously deleted but is still cached. Get info.
            sid = State_ID.from_text(deleted.stdout)
            commit = deleted.stdout.split("\n", maxsplit=1)[0]
         else:
            sid = None
            commit = None
         return (sid, commit)

   def configure(self):
      # Configuration.
      path = self.root // "config"
      fp = path.open_("r+")
      config = configparser.ConfigParser()
      config.read_file(fp, source=path)
      changed = False
      for (k, v) in GIT_CONFIG.items():
         (s, k) = k.lower().split(".", maxsplit=1)
         if (config.get(s, k, fallback=None) != v):
            changed = True
            try:
               config.add_section(s)
            except configparser.DuplicateSectionError:
               pass
            config.set(s, k, v)
      if (changed):
         ch.VERBOSE("writing updated Git config")
         fp.seek(0)
         fp.truncate()
         ch.ossafe("can’t write Git config: %s" % path, config.write, fp)
      ch.close_(fp)
      # Ignore list entries:
      #
      #   1. Git has no default gitignore, but cancel any global gitignore rules
      #      the user might have. https://stackoverflow.com/a/26681066
      #
      #   2. The oddly-named GIT_DIR.
      #
      # It is easier to just write the list we want every time, rather than
      # trying to figure out if an update is needed.
      (self.root // "info/exclude").file_write("!*\n%s\n" % im.GIT_DIR)
      # Remove old .gitignore files from all commits. While there are nice
      # tools to do this (e.g. “git filter-repo”), we don’t want to depend on
      # an external tool. Thus, the options seem to be “filter-branch” or
      # “export” followed by “import”. Around half of the “filter-branch” man
      # page is devoted to explaining why not to use it, so we use the latter.
      #
      # NOTE: Without --reflog, “fast-export” will omit commits on unnamed
      # branches (i.e., accessible only via reflog), but with it, we get
      # “commit” instructions in the stream with no branch name, which
      # “fast-import” won’t accept. Therefore, we just delete those commits,
      # to prevent deleted .gitignore files from creeping back in. (I couldn’t
      # figure out how to fix this for “filter-branch” either, which I didn’t
      # want to use anyway for the reasons above.)
      if (ch.storage.bucache_needs_ignore_upgrade.exists_()):
         ch.INFO("upgrading build cache to v6+, some cached data may be lost",
                 "see release notes for v0.32")
         text = self.git(["fast-export", "--no-data", "--", "--all"],
                         encoding="UTF-8").stdout
         #fs.Path("/tmp/old").file_write(text)
         # There is a bug in Git that loses files that become directories [1].
         # We work around this by moving delete commands within each commit to
         # be first. This makes a number of assumptions about the output of
         # “fast-export” that are true only for us, e.g. that it’s all
         # line-based, including data like commit messages.
         #
         # [1]: https://lore.kernel.org/git/6486D136-23D8-4C90-AEDA-DD037A5CD2B5@lanl.gov/T/#t
         lines = text.split("\n")
         data_p = re.compile(r"^[DM] ")
         i = 0
         while i < len(lines):
            if (data_p.search(lines[i])):
               j = i + 1
               while (data_p.search(lines[j])):
                  j += 1
               lines[i:j] = sorted(lines[i:j], key=lambda x: x[0])
               i = j - 1
            i += 1
         text = "\n".join(lines)
         text = re.sub(r"^(D|M [0-7]+ [0-9a-f]+) \.(git|weirdal_)ignore$",
                       "#\g<0>", text, flags=re.MULTILINE)
         #fs.Path("/tmp/new").file_write(text)
         self.git(["fast-import", "--force"], input=text)
         self.git(["reflog", "expire", "--all", "--expire=now"])
         ch.storage.bucache_needs_ignore_upgrade.unlink()

   def find_commit(self, git_id):
      """Return (state ID, commit) of commit-ish git_id, or (None, None) if it
         doesn’t exist."""
      # Note abbreviated commit hash %h is automatically long enough to avoid
      # collisions.
      cp = self.git(["log", "--format=%h%n%B", "-n", "1", git_id],
                    fail_ok=True)
      if (cp.returncode == 0):  # branch exists
         sid = State_ID.from_text(cp.stdout)
         commit = cp.stdout.split("\n", maxsplit=1)[0]
      else:
         sid = None
         commit = None
      ch.VERBOSE("commit-ish %s: %s %s" % (git_id, commit, sid))
      return (sid, commit)

   def find_deleted_image(self, image):
      return self.commit_find_deleted(image.ref.for_path)

   def find_image(self, image):
      """Return (state ID, commit) of branch tip for image, or (None, None) if
         no such branch."""
      return self.find_commit(image.ref.for_path)

   def find_sid(self, sid, branch):
      """Return the hash of the commit matching State_ID, or None if no such
         commit exists. First search branch, then if not found, the
         entire repo including commits not reachable from any branch."""
      commit = self.find_sid_(sid, branch)
      if (commit is None):
         commit = self.find_sid_(sid)
      ch.VERBOSE("commit for %s: %s" % (sid, commit))
      return commit

   def find_sid_(self, sid, branch=None):
      """Return the hash of the most recent commit matching State_ID sid, or
         None if no such commit exists. If branch is given, search only that
         branch; otherwise, search the entire repo, including commits not
         reachable from any branch."""
      argv = ["log", "--grep", sid, "-F", "--format=%h", "-n", "1"]
      if (branch is not None):
         fail_ok = True
         argv += [branch]
      else:
         fail_ok = False
         argv += ["--all", "--reflog"]
      cp = self.git(argv, fail_ok=fail_ok)
      if (cp.returncode != 0 or len(cp.stdout) == 0):
         return None
      else:
         return cp.stdout.split(maxsplit=1)[0]

   def garbageinate(self):
      ch.INFO("collecting cache garbage")
      t = ch.Timer()
      # Expire the reflog with a recent time instead of now in case there is a
      # parallel Git operation in progress.
      self.git(["-c", "gc.bigPackthreshold=0", "-c", "gc.pruneExpire=now",
                "-c", "gc.reflogExpire=now", "gc"], quiet=False)
      t.log("collected garbage")
      t = ch.Timer()
      digests = self.git(["rev-list", "--all", "--reflog",
                                      "--date-order"]).stdout.split("\n")
      assert (digests[-1] == "")  # trailing newline
      digests[-2:] = []           # discard root commit and trailing newline
      p = ch.Progress("enumerating large files", "commits", 1, len(digests))
      larges_used = set()
      for d in digests:
         data = self.git(["show", "%s:%s" % (d, PICKLE_PATH)],
                         encoding=None).stdout
         fm = File_Metadata.unpickle(fs.Path("/DUMMY"), data)
         larges_used |= fm.large_names()
         p.update(1)
      p.done()
      t.log("enumerated large files")
      t = ch.Timer()
      ch.INFO("found %d large files used; deleting others" % len(larges_used))
      for l in ch.storage.build_large.listdir():
         if (l not in larges_used):
            (ch.storage.build_large // l).unlink_()
      t.log("deleted unused large files")

   def git(self, argv, cwd=None, quiet=True, *args, **kwargs):
      """Run the given git(1) command with appropriate environment and return
         the resulting CompletedProcess object. If cwd is None, run with CWD
         set to the build cache bare repo; otherwise, it must be the path to
         an unpacked image. If quiet is true, read Git’s stdout and return it
         in cp.stdout; otherwise, leave Git’s stdout unchanged. Any additional
         arguments are passed through to ch.cmd_stdout()."""
      if (cwd is None):
         cwd = self.root
      else:
         if ("env" not in kwargs):
            kwargs["env"] = dict()
         kwargs["env"].update({ "GIT_DIR": str(cwd // im.GIT_DIR),
                                "GIT_WORK_TREE": str(cwd) })
      return (ch.cmd_stdout if quiet else ch.cmd)([git] + argv, cwd=cwd,
                                                  *args, **kwargs)

   def git_prepare(self, unpack_path, files, write=True):
      """Prepare unpack_path for Git operations (see
         File_Metadata.git_prepare() for lots of details). If files is None,
         regenerate self.file_metadata by walking the directory tree.
         Otherwise, update metadata only for files in files."""
      t = ch.Timer()
      if (len(files) == 0):
         self.file_metadata = File_Metadata.git_prepare(unpack_path,
                                                        self.large_threshold)
      else:
         for path in files:
            self.file_metadata.update(path)
      t.log("gathered file metadata")
      if (write):
         self.file_metadata.pickle()

   def git_restore(self, unpack_path, files, quick):
      """Opposite of git_prepare. If files is non-empty, only restore those
         files. If quick, assuming that unpack_path is unchanged since
         file_metadata was collected earlier in this process, rather than the
         directory being checked out from Git, i.e., only restore things that
         we broke in git_prepare() (e.g., renaming .git files), not things
         that Git breaks (e.g., file permissions). Otherwise (i.e., not
         quick), read the File_Metadata tree the pickled file and do a full
         restore. This method will dirty the Git working directory."""
      t = ch.Timer()
      if (not quick):
         self.file_metadata = File_Metadata.unpickle(unpack_path)
      if (len(files) == 0):
         self.file_metadata.git_restore(quick)
      else:
         for path in files:
            self.file_metadata.get(path).git_restore(quick)
      t.log("restored file metadata (%s)" % ("quick" if quick else "full"))

   def pull_eager(self, img, src_ref, last_layer=None):
      """Pull image, always checking if the repository version is newer. This
         is the pull operation invoked from the command line."""
      pullet = pull.Image_Puller(img, src_ref)
      pullet.download()  # will use dlcache if appropriate
      dl_sid = self.sid_from_parent(self.root_id, pullet.sid_input)
      dl_git_hash = self.find_sid(dl_sid, img.ref.for_path)
      if (dl_git_hash is not None):
         # Downloaded image is in cache, check it out.
         ch.INFO("pulled image: found in build cache")
         # Remove tag for previously deleted branch, if it exists.
         self.tag_delete(img.ref.for_path, fail_ok=True)
         self.checkout_ready(img, dl_git_hash)
      else:
         # Unpack and commit downloaded image. This also creates the worktree.
         ch.INFO("pulled image: adding to build cache")
         self.pull_lazy(img, src_ref, last_layer, pullet)

   def pull_lazy(self, img, src_ref, last_layer=None, pullet=None):
      """Pull img from src_ref if it does not exist in the build cache, i.e.,
         do not ask the registry if there is a newer version. This is the pull
         operation invoked by FROM. If pullet is not None, use that
         Image_Puller and do not download anything (i.e., assume
         Image_Puller.download() has already been called)."""
      if (pullet is None):
         # a young hen, especially one less than one year old
         pullet = pull.Image_Puller(img, src_ref)
         pullet.download()
      pullet.unpack(last_layer)
      sid = self.sid_from_parent(self.root_id, pullet.sid_input)
      pullet.done()
      self.worktree_adopt(img, "root")
      commit = self.commit(img.unpack_path, sid, "PULL %s" % src_ref, [])
      self.ready(img)
      if (img.ref != src_ref):
         self.branch_nocheckout(src_ref, img.ref)
      return (sid, commit)

   def ready(self, image):
      (_, git_hash) = self.find_deleted_image(image)
      if (not (git_hash is None)):
         self.tag_delete(image.ref.for_path) # Branch was deleted.
      self.git(["checkout", "-B", self.branch_name_ready(image.ref)],
               cwd=image.unpack_path)
      self.branch_delete(self.branch_name_unready(image.ref))

   def ready_p(self, branch):
      return (not branch.endswith("#"))

   def reset(self):
      if (self.bootstrap_ct >= 1):
         ch.WARNING("not resetting brand-new cache")
      else:
         # Kill any Git garbage collection that may be running, to avoid race
         # conditions while deleting the cache (see issue #1406). Open
         # directly to avoid a TOCTOU race.
         pid_path = ch.storage.build_cache // "gc.pid"
         try:
            fp = open(pid_path, "rt", encoding="UTF-8")
            text = ch.ossafe("can’t read: %s" % pid_path, fp.read)
            pid = int(text.split()[0])
            ch.INFO("stopping build cache garbage collection, PID %d" % pid)
            ch.kill_blocking(pid)
            ch.close_(fp)
         except FileNotFoundError:
            # no PID file, therefore no GC running
            pass
         except OSError as x:
            ch.FATAL("can’t open GC PID file: %s: %s" % (pid_path, x.strerror))
         # Delete images that are worktrees referring back to the build cache.
         ch.INFO("deleting build cache")
         for d in ch.storage.unpack_base.listdir():
            dotgit = ch.storage.unpack_base // d // im.GIT_DIR
            if (os.path.exists(dotgit)):
               ch.VERBOSE("deleting cached image: %s" % d)
               (ch.storage.unpack_base // d).rmtree()
         # Delete build cache.
         self.root.rmtree()
         ch.storage.build_large.rmtree()
         # Create new.
         self.root.mkdir()
         ch.storage.build_large.mkdir()
         self.bootstrap()

   def rollback(self, path):
      """Restore path to the last committed state, including both tracked and
         untracked files."""
      ch.INFO("something went wrong, rolling back ...")
      self.git_prepare(path, [], write=False)
      t = ch.Timer()
      self.git(["reset", "--hard", "HEAD"], cwd=path, quiet=False)
      self.git(["clean", "-fdq"], cwd=path, quiet=False)
      t.log("reverted worktree")
      self.git_restore(path, [], False)

   def sid_from_parent(self, *args):
      # This lets us intercept the call and return None in disabled mode.
      return State_ID.from_parent(*args)

   def status_char(self, miss):
      "Return single character to indicate whether miss is true or not."
      if (miss is None):
         return " "
      elif (miss):
         return "."
      else:
         return "*"

   def summary_print(self):
      # state IDs
      msgs = self.git(["log", "--all", "--reflog", "--format=format:%b"]).stdout
      states = set()
      for msg in msgs.splitlines():
         if (msg != ""):
            states.add(State_ID.from_text(msg))
      # branches (FIXME: how to count unnamed branch tips?)
      image_ct = self.git(["branch", "--list"]).stdout.count("\n")
      # file count and size on disk
      (file_ct, byte_ct) = fs.Path(self.root).du()
      commit_ct = int(self.git(["rev-list", "--all", "--reflog",
                                            "--count"]).stdout)
      (file_ct, file_suffix) = ch.si_decimal(file_ct)
      (byte_ct, byte_suffix) = ch.si_binary_bytes(byte_ct)
      # print it
      print("named images:   %5d" % image_ct)
      print("state IDs:      %5d" % len(states))
      print("large files:    %5d" % len(ch.storage.build_large.listdir()))
      print("commits:        %5d" % commit_ct)
      print("internal files: %5d %s" % (file_ct, file_suffix))
      print("disk used:      %5d %s" % (byte_ct, byte_suffix))
      # some information directly from Git
      if (ch.log_level >= ch.Log_Level.VERBOSE):
         out = self.git(["count-objects", "-vH"]).stdout
         print("Git statistics:")
         print(textwrap.indent(out, "  "), end="")
         out = (self.root // "config").file_read_all()
         print("Git config:")
         print(textwrap.indent(out, "  "), end="")

   def tag_delete(self, tag, *args, **kwargs):
      """Delete specified git tag. Used for recovering deleted branches."""
      return self.git(["tag", "-d", "&%s" % tag], *args, **kwargs)

   def tree_dot(self):
      have_dot()
      path_gv = fs.Path(dot_base + ".gv")
      path_pdf = fs.Path(dot_base + ".pdf")
      if (not path_gv.is_absolute()):
         path_gv = os.getcwd() // path_gv
         path_pdf = os.getcwd() // path_pdf
      ch.VERBOSE("writing %s" % path_gv)
      ch.cmd_quiet(
["git2dot.py",
 "--range", "--all --reflog --topo-order",
 "--font-name", "Nimbus Mono",
 "-d", 'graph[rankdir="TB", bgcolor="white"]',
 "-d", 'edge[dir=forward, arrowsize=0.5]',
 "--bedge", '[color=gray80, dir=none]',
 "--bnode", '[label="{label}", shape=box, height=0.20, color=gray80]',
 "--cnode", '[label="{label}", shape=box, color=black, fillcolor=white]',
 "--mnode", '[label="{label}", shape=box, color=black, fillcolor=white]',
 "-D", "@SID@", "([0-9A-F]{4}):",
 "-l", "@SID@|%s", str(path_gv)], cwd=self.root)
      ch.VERBOSE("writing %s" % path_pdf)
      ch.cmd_quiet(["dot", "-Tpdf", "-o%s" % path_pdf, str(path_gv)])

   def tree_print(self):
      # Note the percent codes are interpreted by Git.
      # See: https://git-scm.com/docs/git-log#_pretty_formats
      args = ["log", "--graph", "--all", "--reflog", "--topo-order"]
      if (ch.log_level == ch.Log_Level.INFO):
         # ref names, subject (instruction), branch heads.
         fmt = "%C(auto)%d %Creset%<|(77,trunc)%s"
         args.append("--decorate-refs=refs/heads")
      else:
         # ref names, short commit hash, subject (instruction), body (state ID)
         # FIXME: The body contains a trailing newline I can’t figure out how
         # to remove.
         fmt = "%C(auto)%d%C(yellow) %h %Creset%s %b"
      self.git(args + ["--format=%s" % fmt], quiet=False)
      print()  # blank line to separate from summary

   def unpack_delete(self, image, missing_ok=False):
      """Wrapper for Image.unpack_delete() that first detaches the work tree's
         head. If we delete an image's unpack path without first detaching HEAD,
         the corresponding work tree must also be deleted before the bucache
         branch. This involves multiple calls to worktrees_fix(), which is
         clunky, so we use this method instead."""
      if (not image.unpack_exist_p and missing_ok):
         return
      (_, commit) = self.find_commit(image.ref.for_path)
      if (commit is not None):
         # Off with her head!
         self.git(["checkout", "%s" % commit], cwd=image.unpack_path)
      image.unpack_delete()

   def unready_of(self, branch):
      if (self.ready_p(branch)):
         return branch + "#"
      else:
         return branch

   def worktree_add(self, image, base):
      if (image.unpack_cache_linked):
         self.git_prepare(image.unpack_path, [], write=False)  # clean worktree
         if (self.commit_hash_p(base) and base == self.worktree_head(image)):
            ch.VERBOSE("already checked out: %s %s" % (image.unpack_path, base))
         else:
            ch.INFO("updating existing image ...")
            t = ch.Timer()
            self.git(["checkout", "-B", self.branch_name_unready(image.ref),
                      base], cwd=image.unpack_path)
            t.log("adjusted worktree")
      else:
         ch.INFO("copying image from cache ...")
         image.unpack_clear()
         t = ch.Timer()
         self.git(["worktree", "add", "-f", "-B",
                   self.branch_name_unready(image.ref),
                   image.unpack_path, base])
         # Move GIT_DIR from default location to where we want it.
         git_dir_default = image.unpack_path // ".git"
         git_dir_new = image.unpack_path // im.GIT_DIR
         git_dir_new.parent.mkdir_()
         git_dir_default.rename_(git_dir_new)
         t.log("created worktree")

   def worktree_adopt(self, image, base):
      """Create a new worktree with the contents of existing directory
         image.unpack_path. Note shenanigans because “git worktree add”
         *cannot* use an existing directory but shutil.copytree *must* create
         its own directory (until Python 3.8, and we have to support 3.6). So
         we use some renaming."""
      if (os.path.isdir(ch.storage.image_tmp)):
         ch.WARNING("temporary image still exists, deleting",
                    "maybe a previous command crashed?")
         ch.storage.image_tmp.rmtree()
      image.unpack_path.rename_(ch.storage.image_tmp)
      self.worktree_add(image, base)
      (image.unpack_path // im.GIT_DIR).rename(   ch.storage.image_tmp
                                               // im.GIT_DIR)
      image.unpack_path.rmtree()
      ch.storage.image_tmp.rename_(image.unpack_path)

   def worktree_head(self, image):
      cp = self.git(["rev-parse", "--short", "HEAD"],
                    fail_ok=True, cwd=image.unpack_path)
      if (cp.returncode != 0):
         return None
      else:
         return cp.stdout.strip()

   def worktrees_fix(self):
      """Git stores pointers (paths) both from the main repository to each
         worktree, and in the other direction from each worktree back to the
         main repo. These are absolute paths, so if the storage directory gets
         moved, they need updating. Also, worktrees can disappear without
         telling Git. This method cleans all that up.

         This method does roughly the same thing as “git worktree repair” and
         “git worktree prune”, but we do it manually [1,2] because we know more
         about what is going on than Git does: (1) which images are worktrees
         vs. plain directories; (2) which images changed from worktree to plain
         directory w/o telling Git; (3) where the worktrees and main repo are
         relative to one another.

         In particular, I don’t see a simple way to trust the exit code of
         “git worktree repair” without doing most of this work first anyway.

         [1]: https://git-scm.com/docs/git-worktree
         [2]: https://git-scm.com/docs/gitrepository-layout"""
      t = ch.Timer()
      wt_actuals = { fs.Path(i).parts[-(len(im.GIT_DIR)+1)]
                     for i in glob.iglob(str(   ch.storage.unpack_base
                                             // "*" // im.GIT_DIR)) }
      wt_gits =    { fs.Path(i).name
                     for i in glob.iglob("%s/worktrees/*" % self.root) }
      # Delete worktree data for images that no longer exist or aren’t
      # Git-enabled any more.
      wt_gits_deleted = wt_gits - wt_actuals
      for wt in wt_gits_deleted:
         (ch.storage.build_cache // "worktrees" // wt).rmtree()
      ch.VERBOSE("deleted %d stale worktree metadatas" % len(wt_gits_deleted))
      wt_gits -= wt_gits_deleted
      assert (wt_gits == wt_actuals)
      # If storage directory moved, repair all the paths.
      if (len(wt_gits) > 0):
         wt_dir_stored = fs.Path((   ch.storage.build_cache
                                  // "worktrees"
                                  // next(iter(wt_gits))
                                  // "gitdir").file_read_all())
         if (not wt_dir_stored.is_relative_to(ch.storage.root)):
            for wt in wt_actuals:
               wt_repo_dir = ch.storage.build_cache // "worktrees" // wt
               wt_img_git = ch.storage.unpack_base // wt // im.GIT_DIR
               wt_img_git.file_write("gitdir: %s\n" % str(wt_repo_dir))
               (wt_repo_dir // "gitdir").file_write(str(wt_img_git) + "\n")
            ch.VERBOSE("fixed %d worktrees" % len(wt_actuals))
      t.log("re-linked worktrees")


class Rebuild_Cache(Enabled_Cache):

   def __str__(self):
      return ("rebuild (large=%g)" % self.large_threshold)

   def find_sid(self, sid, branch):
      return None


class Disabled_Cache(Rebuild_Cache):

   def __init__(self, *args):
      pass

   def __str__(self):
      return "disabled"

   def checkout(self, image, git_hash, base_image):
      ch.INFO("copying image ...")
      image.unpack_clear()
      image.copy_unpacked(base_image)

   def commit(self, path, *args):
      self.permissions_fix(path)
      return None

   def find_image(self, *args):
      return (None, None)

   def permissions_fix(self, path):
      # Some distributions create unreadable files; e.g., CentOS 7 after
      # installing “openssh”:
      #
      #   $ ls -lh /scratch/reidpr.ch/img/centos_7ch/usr/bin/ssh-agent
      #   ---x--s--x 1 reidpr reidpr 374K Nov 24  2021 [...]/ssh-agent
      #
      # This makes the image un-copyable, so it can’t be used as a base image.
      #
      # Enabled_Cache takes care of this in git_prepare(), and
      # --force=fakeroot bypasses it in some other way I haven’t looked into.
      for (dir_, subdirs, files) in ch.walk(path):
         for i in itertools.chain(subdirs, files):
            (dir_ // i).chmod_min()

   def pull_lazy(self, img, src_ref, last_layer=None, pullet=None):
      if (pullet is None and os.path.exists(img.unpack_path)):
         ch.VERBOSE("base image already exists, skipping pull")
      else:
         if (pullet is None):
            pullet = pull.Image_Puller(img, src_ref)
            pullet.download()
         img.unpack_clear()
         pullet.unpack(last_layer)
         pullet.done()
      return (None, None)

   def ready(self, *args):
      pass

   def rollback(self, path):
      self.permissions_fix(path)

   def sid_from_parent(self, *args):
      return None

   def worktree_add(self, *args):
      pass

   def worktree_adopt(self, *args):
      pass

   def worktrees_prune(self, *args):
      pass
