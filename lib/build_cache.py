import configparser
import enum
import hashlib
import os
import pickle
import re
import stat
import tempfile
import textwrap
import time

import charliecloud as ch
import pull


## Constants ##

# Required versions.
DOT_MIN = (2, 30, 1)
GIT_MIN = (2, 28, 1)
GIT2DOT_MIN = (0, 8, 3)

# Git configuration. Note some of these are overridden in specific commands.
# Documentation for these variables: https://git-scm.com/docs/git-config
GIT_CONFIG = {
   # Try to maximize “git add” speed.
   "core.looseCompression":  "0",
   # Quick-and-dirty results suggest that commit is not faster after garbage
   # collection, and checkout is actually a little faster if *not* garbage
   # collected. Therefore, it's not a high priority to run garbage collection.
   # Further, I would assume garbaging a lot of files rather than a few gives
   # better opportunities for delta compression. Our most file-ful example
   # image is obspy at about 50K files.
   "gc.auto":                "100000",
   # Leave packs larger than this alone during automatic GC. This is to avoid
   # excessive resource consumption during GC the user didn't ask for.
   "gc.bigPackThreshold":    "12G",
   # Anything unreachable from a named branch or the reflog is unavailable to
   # the build cache, so we may as well delete it immediately. However, there
   # might be a concurrent Git operation in progress, so don’t use “now”.
   "gc.pruneExpire":         "12.hours.ago",
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
}


## Globals ##

# The active build cache.
cache = None

# Path to DOT output (.gv and .pdf will be appended)
dot_base = None


## Functions ##

def have_deps(required=True):
   """Return True if dependencies for the build cache are present, False
      otherwise. Note this does not include the --dot debugging option; that
      checks its own dependencies when invoked."""
   # As of 2.34.1, we get: "git version 2.34.1\n".
   return ch.version_check(["git", "--version"], GIT_MIN, required=required)

def have_dot():
   ch.version_check(["git2dot.py", "--version"], GIT2DOT_MIN)
   ch.version_check(["dot", "-V"], DOT_MIN)

def init(cli):
   # At this point --bucache is what the user wanted, either directly or via
   # --no-cache. If it's None, chose the right default; otherwise, try what
   # the user asked for and fail if we can't do it.
   if (cli.bucache != ch.Build_Mode.DISABLED):
      ok = have_deps(False)
      if (cli.bucache is None):
         cli.bucache = ch.Build_Mode.ENABLED if ok else ch.Build_Mode.DISABLED
         ch.VERBOSE("using default build cache mode")
      if (cli.bucache != ch.Build_Mode.DISABLED and not ok):
         ch.FATAL("insufficient Git for build cache mode: %s"
                  % cli.bucache.value)
   ch.VERBOSE("build cache mode: %s" % cli.bucache.value)
   # Set cache appropriately. We could also do this with a factory method, but
   # that seems overkill.
   global cache
   if (cli.bucache == ch.Build_Mode.ENABLED):
      cache = Enabled_Cache()
   elif (cli.bucache == ch.Build_Mode.REBUILD):
      cache = Rebuild_Cache()
   elif (cli.bucache == ch.Build_Mode.DISABLED):
      cache = Disabled_Cache()
   else:
      assert False, "unreachable"
   # DOT output path
   try:
      global dot_base
      dot_base = cli.dot
   except AttributeError:
      pass


## Supporting classes ##

class File_Metadata:

   # Note: ctime cannot be restored: https://unix.stackexchange.com/a/36105

   # Note/FIXME: Because children is a list, rather than e.g. a dictionary
   # that maps names to child objects, we cannot efficiently access the
   # children by name. See get() and set(). Changing that attribute's type
   # requires either bumping the storage directory version or automagically
   # converting on un-pickle. Because currently (9/19/2022) our performance
   # requirements are not large, I don't think the hassle of doing either of
   # these is merited.
   #
   # A related design problem is that this class is externally mucked with a
   # lot, e.g. by build_cache.git_prepare_walk() and .git_restore_walk().

   __slots__ = ('atime_ns',
                'children',
                'dont_restore',
                'hardlink_to',
                'mtime_ns',
                'mode',
                'name')

   def __init__(self, path, st):
      # The if/else here accounts for when 'path' represents '.', in which
      # case path.name returns '' and str(path) returns '.'.
      if (len(path.parts) < 1):     # path represents '.'
         self.name = str(path)
      else:
         self.name = path.parts[-1] # name is file basename
      self.atime_ns = st.st_atime_ns
      self.dont_restore = False
      self.children = list()  # so we can keep it sorted
      self.hardlink_to = None
      self.mtime_ns = st.st_mtime_ns
      self.mode = st.st_mode

   @property
   def unstored(self):
      """True if I represent something not stored, either ignored by Git or
         deleted by us before committing."""
      return (   stat.S_ISFIFO(self.mode)
              or stat.S_ISSOCK(self.mode)
              or self.hardlink_to is not None)

   @property
   def empty_dir_p(self):
      """True if I represent either an empty directory, or a directory that
         contains only children where empty_dir_p is true. E.g., the root of a
         directory tree containing only empty directories returns true."""
      # In principle this could do a lot of recursion, but in practice I'm
      # guessing it's not too much.
      if (not stat.S_ISDIR(self.mode)):
         return False  # not a directory
      # True if no children (truly empty directory), or each child is unstored
      # or empty_dir_p (recursively empty directory tree).
      return all((c.hardlink_to is not None or c.empty_dir_p)
                 for c in self.children)

   def get(self, path):
      """Return the File_Metadata object at path. Slow; see comment."""
      assert (len(path.parts) >= 1)
      for c in self.children:
         if (c.name == path.first):
            if (len(path.parts) == 1):
               return c
            else:
               return c.get(path.lstrip(1))
      assert False, "unreachable code reached"

   def set(self, path, fm):
      """Set the File_Metadata object at path to fm. Slow; see comment."""
      assert (len(path.parts) >= 1)
      for (i, c) in enumerate(self.children):
         if (c.name == path.first):
            if (len(path.parts) == 1):
               self.children[i] = fm  # WARNING: iteration now broken
            else:
               c.set(path.lstrip(1), fm)
            break


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
   import_id = State_ID.from_text("5061:756C:204D6F72:70687900:00000000")

   __slots__ = ("bootstrap_ct",
                "file_metadata")

   def __init__(self):
      self.bootstrap_ct = 0
      if (not os.path.isdir(self.root)):
         self.root.mkdir()
      ls = self.root.listdir()
      if (len(ls) == 0):
         self.bootstrap()  # empty; initialize a new cache
      elif (not {ch.Path(i) for i in ["HEAD", "objects", "refs"]} <= ls):
         # Non-empty but not an existing cache.
         # See: https://git-scm.com/docs/gitrepository-layout
         ch.FATAL("storage broken: not a build cache: %s" % self.root)
      self.configure()  # every open so configuration is up to date
      # Prune stale worktrees that might have been left around after failed
      # builds or other interruptions.
      ch.cmd_quiet(["git", "worktree", "prune"], cwd=self.root)

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
      gh = self.commit(img.unpack_path, self.import_id,
                       "IMPORT %s" % img.ref, [])
      self.ready(img)
      return (self.import_id, gh)

   def bootstrap(self):
      ch.INFO("initializing empty build cache")
      self.bootstrap_ct += 1
      # Initialize bare repo
      ch.cmd_quiet(["git", "init", "--bare", "-b", "root", self.root])
      # Create empty root commit. There is probably a way to do this directly
      # in the bare repo, but brief searching makes it seem pretty hairy.
      try:
         with tempfile.TemporaryDirectory(prefix="weirdal.") as td:
            ch.cmd_quiet(["git", "clone", "-q", self.root, td])
            cwd = ch.Path(td).chdir()
            ch.cmd_quiet(["git", "checkout", "-q", "-b", "root"])
            # Git has no default gitignore, but cancel any global gitignore
            # rules the user might have. https://stackoverflow.com/a/26681066
            ch.Path(".gitignore").file_write("!*\n")
            ch.cmd_quiet(["git", "add", ".gitignore"])
            ch.cmd_quiet(["git", "commit", "-m", "ROOT\n\n%s" % self.root_id])
            ch.cmd_quiet(["git", "push", "-q", "origin", "root"])
            cwd.chdir()
      except OSError as x:
         ch.FATAL("can't create or delete temporary directory: %s: %s"
                  % (x.filename, x.strerror))

   def branch_delete(self, branch):
      "Delete branch branch if it exists; otherwise, do nothing."
      if (ch.cmd_quiet(["git", "show-ref", "--quiet", "--heads", branch],
                       cwd=self.root, fail_ok=True) == 0):
         ch.cmd_quiet(["git", "branch", "-D", branch], cwd=self.root)


   def branch_nocheckout(self, src_ref, dest):
      """Create ready branch for Image_Ref src_ref pointing to dest, which can
         be either an Image_Ref or a Git commit reference (as a string)."""
      if (isinstance(dest, ch.Image_Ref)):
         dest = self.branch_name_ready(dest)
      # Some versions of Git won't let us update a branch that's already
      # checked out, so detach that worktree if it exists.
      src_img = ch.Image(src_ref)
      if (src_img.unpack_exist_p):
         ch.cmd_quiet(["git", "checkout", "--detach"], cwd=src_img.unpack_path)
      ch.cmd_quiet(["git", "branch", "-f", self.branch_name_ready(src_ref),
                    dest], cwd=self.root)

   def checkout(self, image, git_hash, base_image):
      # base_image used in other subclasses
      self.worktree_add(image, git_hash)
      self.git_restore(image.unpack_path, [], False)

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
      cwd = path.chdir()
      t = ch.Timer()
      if (len(files) == 0):
         git_files = ["-A"]
      else:
         git_files = list(files) + ["ch/git.pickle"]
      ch.cmd_quiet(["git", "add"] + git_files)
      t.log("prepared index")
      t = ch.Timer()
      ch.cmd_quiet(["git", "commit", "-q", "--allow-empty",
                    "-m", "%s\n\n%s" % (msg, sid)])
      t.log("committed")
      # "git commit" does print the new commit's hash without "-q", but it
      # also prints every file commited, which is rather enormous for us.
      # Therefore, retrieve the hash separately.
      cp = ch.cmd_stdout(["git", "rev-parse", "--short", "HEAD"])
      git_hash = cp.stdout.strip()
      cwd.chdir()
      self.git_restore(path, files, True)
      return git_hash

   def configure(self):
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
         ch.ossafe(config.write, "can’t write Git config: %s" % path, fp)
      ch.close_(fp)

   def find_commit(self, path, git_id):
      """Return (state ID, commit) of commit-ish git_id in directory path, or
         (None, None) if it doesn’t exist.."""
      # Note abbreviated commit hash %h is automatically long enough to avoid
      # collisions.
      cp = ch.cmd_stdout(["git", "log", "--format=%h%n%B", "-n", "1", git_id],
                         fail_ok=True, cwd=path)
      if (cp.returncode == 0):  # branch exists
         sid = State_ID.from_text(cp.stdout)
         commit = cp.stdout.split("\n", maxsplit=1)[0]
      else:
         sid = None
         commit = None
      ch.VERBOSE("commit-ish %s in %s: %s %s" % (git_id, path, commit, sid))
      return (sid, commit)

   def find_image(self, image):
      """Return (state ID, commit) of branch tip for image, or (None, None) if
         no such branch."""
      return self.find_commit(self.root, image.ref.for_path)

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
      argv = ["git", "log", "--grep", sid, "-F", "--format=%h", "-n", "1"]
      if (branch is not None):
         fail_ok = True
         argv += [branch]
      else:
         fail_ok = False
         argv += ["--all", "--reflog"]
      cp = ch.cmd_stdout(argv, fail_ok=fail_ok, cwd=self.root)
      if (cp.returncode != 0 or len(cp.stdout) == 0):
         return None
      else:
         return cp.stdout.split(maxsplit=1)[0]

   def garbageinate(self):
      ch.INFO("collecting cache garbage")
      t = ch.Timer()
      # Expire the reflog with a recent time instead of now in case there is a
      # parallel Git operation in progress.
      ch.cmd(["git", "-c", "gc.bigPackthreshold=0", "-c", "gc.pruneExpire=now",
                     "-c", "gc.reflogExpire=now", "gc"], cwd=self.root)
      t.log("collected garbage")

   def git_prepare(self, unpack_path, files, write=True):
      """Recursively walk the given unpack path and prepare it for a Git
         commit. Most of this is reversed by git_restore(); anything not
         reversed is noted. For each file, in this order:

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
                 don't get committed or restored, which confuses BDB/RPM.
                 Fortunately, they can be safely deleted, and that's a simple
                 workaround, so we do it. See issue #1351.

         Return the File_Metadata tree, and if write is True, also save it in
         “ch/git.pickle”.

         [1]: https://en.wikipedia.org/wiki/Hard_link#Limitations"""
      t = ch.Timer()
      cwd = unpack_path.chdir()
      if (len(files) == 0):
         self.file_metadata = self.git_prepare_walk(dict(), None, ch.Path("."),
                                                    os.lstat("."))
      else:
         for path in files:
            self.file_metadata.set(path, File_Metadata(path, path.lstat()))
      if (write):
         ch.Path("ch/git.pickle").file_write(pickle.dumps(self.file_metadata,
                                                          protocol=4))
      cwd.chdir()
      t.log("gathered file metadata")

   def git_prepare_walk(self, hardlinks, parent, f_path, st):
      """Return a File_Metadata object describing file name and its children
         (if name is a directory), and rename files as described in
         git_prepare(). Changes CWD during operation but does restore it."""
      # While the standard library provides a similar function os.walk() that
      # is internally recursive, it must be used iteratively.
      fm = File_Metadata(f_path, st)
      path = fm.name if parent is None else "%s/%s" % (parent, fm.name)
      # Ensure minimum permissions. Some tools like to make files with mode
      # 000, because root ignores the permissions bits.
      f_path.chmod_min(0o700 if stat.S_ISDIR(st.st_mode) else 0o400, st) # see #1455
      # Validate file type and recurse if necessary.
      if   (   stat.S_ISREG(st.st_mode)
            or stat.S_ISLNK(st.st_mode)
            or stat.S_ISFIFO(st.st_mode)):
         # normally nothing to do here on these file types
         if (path.startswith("./var/lib/rpm/__db.")):
            ch.VERBOSE("deleting, see issue #1351: %s" % path)
            f_path.unlink() # change to fm.path.unlink() once issue #1455 is
                            # closed
            fm.dont_restore = True
            return fm
      elif (   stat.S_ISSOCK(st.st_mode)):
         ch.WARNING("socket in image, will be ignored: %s" % path)
      elif (   stat.S_ISCHR(st.st_mode)
            or stat.S_ISBLK(st.st_mode)):
         ch.FATAL("device files invalid in image: %s" % path)
      elif (   stat.S_ISDIR(st.st_mode)):
         entries = sorted(f_path.listdir()) # FIXME: see issue #1455
         cwd = f_path.chdir() # once #1455 is closed, this line should get
                              # changed to 'fm.path.chdir()'.
         for i in entries:
            if (not (parent is None and str(i).startswith(".git"))):
               fm.children.append(self.git_prepare_walk(hardlinks, path,
                                                        i, os.lstat(i)))
         cwd.chdir()
      else:
         ch.FATAL("unexpected file type in image: %x: %s"
                  % (stat.IFMT(st.st_mode), path))
      # Deal with hard links.
      if (not stat.S_ISDIR(st.st_mode) and st.st_nlink > 1):
         if ((st.st_dev, st.st_ino) in hardlinks):
            ch.TRACE("hard link: deleting subsequent: %d %d %s"
                     % (st.st_dev, st.st_ino, path))
            fm.hardlink_to = hardlinks[(st.st_dev, st.st_ino)]
            f_path.unlink() # f_path -> fm.path (issue #1455)
         else:
            ch.TRACE("hard link: recording first: %d %d %s"
                     % (st.st_dev, st.st_ino, path))
            hardlinks[(st.st_dev, st.st_ino)] = path
      # Remove empty directories. Git will ignore them, including leaving them
      # there if switch the worktree to a different branch, which is bad.
      if (fm.empty_dir_p):
         f_path.rmdir_() # f_path -> fm.path (issue #1455)
         return fm  # can't do anything else after it's gone
      # Remove FIFOs for the same reason.
      if (stat.S_ISFIFO(st.st_mode)):
         f_path.unlink() # f_path -> fm.path (issue #1455)
      # Rename if necessary.
      if (fm.name.startswith(".weirdal_")):
         ch.WARNING("file starts with sentinel, will be renamed: %s" % fm.name)
      if (fm.name.startswith(".git")):
         name_new = fm.name.replace(".git", ".weirdal_")
         ch.VERBOSE("renaming: %s -> %s" % (fm.name, name_new))
         f_path.rename_(name_new) # f_path -> fm.path (issue #1455)
      # Done.
      return fm

   def git_restore(self, unpack_path, files, quick):
      """Opposite of git_prepare. If files is non-empty, only restore those
         files. If quick, assuming that unpack_path is unchanged since
         file_metadata was collected earlier in this process, rather than the
         directory being checked out from Git. I.e. only restore things that
         we broke in git_prepare() (e.g., renaming .git files), not things
         that Git breaks (e.g., file permissions). Otherwise (i.e., not
         quick), read the File_Metadata tree from “ch/git.pickle” under
         unpack_path and do a full restore. This method will dirty the Git
         working directory."""
      t = ch.Timer()
      cwd = unpack_path.chdir()
      if (not quick):
         self.file_metadata = pickle.loads(ch.Path("ch/git.pickle").file_read_all(text=False))
      if (len(files) == 0):
         self.git_restore_walk(unpack_path, None, self.file_metadata, quick)
      else:
         for path in files:
            self.git_restore_walk(path, path.parent,
                                  self.file_metadata.get(path), quick)
      cwd.chdir()
      t.log("restored file metadata (%s)" % ("quick" if quick else "full"))

   def git_restore_walk(self, root, parent, fm, quick):
      "Changes CWD but restores it."
      assert (parent is not None or fm.name == ".")
      path = fm.name if parent is None else "%s/%s" % (parent, fm.name)
      if (fm.dont_restore):
         assert (not stat.S_ISDIR(fm.mode))  # directories need recursion
         return
      # Make sure I exist, and with the correct name.
      if (not quick):
         if (fm.name.startswith(".git")):
            # re-create with escaped name so renaming need not be conditional
            name = fm.name.replace(".git", ".weirdal_")
         else:
            name = fm.name
      if (fm.empty_dir_p):
         ch.ossafe(os.mkdir, "can't mkdir: %s" % path, fm.name)
      if (stat.S_ISFIFO(fm.mode)):
         ch.ossafe(os.mkfifo, "can't make FIFO: %s" % path, fm.name)
      if (fm.hardlink_to is not None and not os.path.exists(fm.name)):
         # This relies on prepare and restore having the same traversal order,
         # so the first (stored) link is always available by the time we get
         # to subsequent (unstored) links.
         target = root // fm.hardlink_to
         ch.TRACE("hard link: restoring: %s -> %s" % (path, target))
         ch.ossafe(os.link, "can't hardlink: %s -> %s" % (path, target),
                   target, fm.name, follow_symlinks=False)
      if (fm.name.startswith(".git")):
         ch.Path(fm.name.replace(".git", ".weirdal_")).rename_(fm.name)
      if (not quick):
         if (stat.S_ISSOCK(fm.mode)):
            ch.WARNING("ignoring socket in image: %s" % path)
      # Recurse children.
      if (len(fm.children) > 0):
         cwd = ch.Path(fm.name).chdir() # works at top level b/c fm.name is "."
         for child in fm.children:
            self.git_restore_walk(root, path, child, quick)
         cwd.chdir()
      # Restore my metadata.
      if ((   not quick                     # Git broke metadata
           or fm.hardlink_to is not None    # we just made the hardlink
           or stat.S_ISDIR(fm.mode)         # maybe just created / new hardlink
           or stat.S_ISFIFO(fm.mode))       # we just made the FIFO
          and not stat.S_ISLNK(fm.mode)):   # can't not follow symlinks
         ch.ossafe(os.utime, "can't restore times: %s" % path, fm.name,
                   ns=(fm.atime_ns, fm.mtime_ns))
         ch.ossafe(os.chmod, "can't restore mode: %s" % path, fm.name,
                   stat.S_IMODE(fm.mode))

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
         self.checkout(img, dl_git_hash, None)
         self.ready(img)
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
      self.worktree_add(img, "root")
      pullet.unpack(last_layer)
      sid = self.sid_from_parent(self.root_id, pullet.sid_input)
      pullet.done()
      commit = self.commit(img.unpack_path, sid, "PULL %s" % src_ref, [])
      self.ready(img)
      if (img.ref != src_ref):
         self.branch_nocheckout(src_ref, img.ref)
      return (sid, commit)

   def ready(self, image):
      ch.cmd_quiet(["git", "checkout", "-B", self.branch_name_ready(image.ref)],
                   cwd=image.unpack_path)
      self.branch_delete(self.branch_name_unready(image.ref))

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
            text = ch.ossafe(fp.read, "can’t read: %s" % pid_path)
            pid = int(text.split()[0])
            ch.INFO("stopping build cache garbage collection, PID %d" % pid)
            ch.kill_blocking(pid)
            ch.close_(fp)
         except FileNotFoundError:
            # no PID file, therefore no GC running
            pass
         except OSError as x:
            FATAL("can’t open GC PID file: %s: %s" % (pid_path, x.strerror))
         # Delete images that are worktrees referring back to the build cache.
         ch.INFO("deleting build cache")
         for d in ch.storage.unpack_base.listdir():
            dotgit = ch.storage.unpack_base // d // ".git"
            if (os.path.exists(dotgit)):
               ch.VERBOSE("deleting cached image: %s" % d)
               (ch.storage.unpack_base // d).rmtree()
         # Create new build cache.
         self.root.rmtree()
         self.root.mkdir()
         self.bootstrap()

   def rollback(self, path):
      """Restore path to the last committed state, including both tracked and
         untracked files."""
      ch.INFO("rolling back ...")
      self.git_prepare(path, [], write=False)
      t = ch.Timer()
      ch.cmd_quiet(["git", "reset", "--hard", "HEAD"], cwd=path)
      ch.cmd_quiet(["git", "clean", "-fdq"], cwd=path)
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
      cwd = ch.Path(self.root).chdir()
      # state IDs
      msgs = ch.cmd_stdout(["git", "log",
                            "--all", "--reflog", "--format=format:%b"]).stdout
      states = set()
      for msg in msgs.splitlines():
         if (msg != ""):
            states.add(State_ID.from_text(msg))
      # branches (FIXME: how to count unnamed branch tips?)
      image_ct = ch.cmd_stdout(["git", "branch", "--list"]).stdout.count("\n")
      # file count and size on disk
      (file_ct, byte_ct) = ch.Path(self.root).du()
      commit_ct = int(ch.cmd_stdout(["git", "rev-list",
                                     "--all", "--reflog", "--count"]).stdout)
      (file_ct, file_suffix) = ch.si_decimal(file_ct)
      (byte_ct, byte_suffix) = ch.si_binary_bytes(byte_ct)
      # print it
      print("named images:  %4d" % image_ct)
      print("state IDs:     %4d" % len(states))
      print("commits:       %4d" % commit_ct)
      print("files:         %4d %s" % (file_ct, file_suffix))
      print("disk used:     %4d %s" % (byte_ct, byte_suffix))
      # some information directly from Git
      if (ch.verbose >= 1):
         out = ch.cmd_stdout(["git", "count-objects", "-vH"]).stdout
         print("Git statistics:")
         print(textwrap.indent(out, "  "), end="")
         out = (self.root // "config").file_read_all()
         print("Git config:")
         print(textwrap.indent(out, "  "), end="")

   def tree_print(self):
      # Note the percent codes are interpreted by Git.
      # See: https://git-scm.com/docs/git-log#_pretty_formats
      if (ch.verbose == 0):
         # ref names, subject (instruction)
         fmt = "%C(auto)%d %Creset%<|(77,trunc)%s"
      else:
         # ref names, short commit hash, subject (instruction), body (state ID)
         # FIXME: The body contains a trailing newline I can't figure out how
         # to remove.
         fmt = "%C(auto)%d%C(yellow) %h %Creset%s %b"
      ch.cmd_base(["git", "log", "--graph", "--all", "--reflog",
                   "--topo-order", "--format=%s" % fmt], cwd=self.root)
      print()  # blank line to separate from summary

   def tree_dot(self):
      have_dot()
      path_gv = ch.Path(dot_base + ".gv")
      path_pdf = ch.Path(dot_base + ".pdf")
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

   def worktree_add(self, image, base):
      if (image.unpack_cache_linked):
         self.git_prepare(image.unpack_path, [], write=False)  # clean worktree
         if (    self.commit_hash_p(base)
             and base == self.find_commit(image.unpack_path, "HEAD")[1]):
            ch.VERBOSE("already checked out: %s %s" % (image.unpack_path, base))
         else:
            ch.INFO("updating existing image ...")
            t = ch.Timer()
            ch.cmd_quiet(["git", "checkout",
                          "-B", self.branch_name_unready(image.ref), base],
                         cwd=image.unpack_path)
            t.log("adjusted worktree")
      else:
         ch.INFO("copying image from cache ...")
         image.unpack_clear()
         t = ch.Timer()
         ch.cmd_quiet(["git", "worktree", "add", "-f",
                       "-B", self.branch_name_unready(image.ref),
                       image.unpack_path, base], cwd=self.root)
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
      for i in { ".git", ".gitignore" }:
         (image.unpack_path // i).rename_(ch.storage.image_tmp // i)
      image.unpack_path.rmdir_()
      ch.storage.image_tmp.rename_(image.unpack_path)

   def worktree_get_head(self, image):
      cp = ch.cmd_stdout(["git", "rev-parse", "--short", "HEAD"],
                         cwd=image.unpack_path, fail_ok=True)
      if (cp.returncode != 0):
         return None
      else:
         return cp.stdout.strip()

   def worktrees_prune(self):
      "Remove Git metadata for deleted worktrees."
      ch.cmd_quiet(["git", "worktree", "prune"], cwd=self.root)


class Rebuild_Cache(Enabled_Cache):

   def find_sid(self, sid, branch):
      return None


class Disabled_Cache(Rebuild_Cache):

   def __init__(self):
      pass

   def checkout(self, image, git_hash, base_image):
      ch.INFO("copying image ...")
      image.unpack_clear()
      image.copy_unpacked(base_image)

   def commit(self, *args):
      return None

   def find_image(self, *args):
      return (None, None)

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

   def rollback(self, *args):
      pass

   def sid_from_parent(self, *args):
      return None

   def worktree_add(self, *args):
      pass

   def worktree_adopt(self, *args):
      pass

   def worktrees_prune(self, *args):
      pass
