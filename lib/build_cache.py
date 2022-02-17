import enum
import hashlib
import os
import pickle
import re
import stat
import tempfile

import charliecloud as ch
import pull


## Constants ##

# Required versions.
DOT_MIN = (2, 40, 1)
GIT_MIN = (2, 34, 1)
GIT2DOT_MIN = (0, 8, 3)


## Globals ##

# The active build cache.
cache = None


## Functions ##

def have_deps():
   """Return True if dependencies for the build cache are present, False
      otherwise. Note this does not include the --dot debugging option; that
      checks its own dependencies when invoked."""
   # As of 2.34.1, we get: "git version 2.34.1\n".
   return ch.version_check(["git", "--version"], GIT_MIN, required=False)

def init(cli):
   # At this point --bucache is what the user wanted, either directly or via
   # --no-cache. If it's None, chose the right default; otherwise, try what
   # the user asked for and fail if we can't do it.
   if (cli.bucache != ch.Build_Mode.DISABLED):
      ok = have_deps()
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


## Supporting classes ##

class File_Metadata:

   # Note: ctime cannot be restored: https://unix.stackexchange.com/a/36105

   __slots__ = ('atime_ns',
                'children',
                'mtime_ns',
                'mode',
                'name')

   def __init__(self, name, st):
      self.name = name
      self.atime_ns = st.st_atime_ns
      self.children = list()  # so we can keep it sorted
      self.mtime_ns = st.st_mtime_ns
      self.mode = st.st_mode

   @property
   def empty_dir_p(self):
      """True if I represent either an empty directory, or a directory that
         contains only children where empty_dir_p is true. E.g., the root of a
         directory tree containing only empty directories returns true."""
      # In principle this could do a lot of recursion, but in practice I'm
      # guessing it's not too much.
      if (not stat.S_ISDIR(self.mode)):
         return False  # not a directory
      # True if no children (truly empty directory) or each child is
      # empty_dir_p (recursively empty directory tree).
      return all(child.empty_dir_p for child in self.children)

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

   def __eq__(self, other):
      return self.id_ == other.id_

   def __hash__(self):
      return hash(self.id_)

   def __str__(self):
      s = self.id_.hex().upper()
      return ":".join((s[0:4], s[4:8], s[8:16], s[16:24], s[24:32]))


## Main classes ##

class Enabled_Cache:

   root_id = State_ID.from_text("4A6F:73C3:A9204361:7061626C:616E6361")

   __slots__ = ("bootstrap_ct")

   def __init__(self):
      self.bootstrap_ct = 0
      if (not os.path.isdir(self.root)):
         ch.mkdir(self.root)
      ls = ch.listdir(self.root)
      if (len(ls) == 0):
         self.bootstrap()  # empty; initialize a new cache
      elif (not {"HEAD", "objects", "refs"} <= ls):
         # Non-empty but not an existing cache.
         # See: https://git-scm.com/docs/gitrepository-layout
         ch.FATAL("storage broken: not a build cache: %s" % self.root)

   @property
   def root(self):
      return ch.storage.build_cache

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
            cwd = ch.chdir(td)
            ch.cmd_quiet(["git", "checkout", "-q", "-b", "root"])
            ch.cmd_quiet(["git", "commit", "--allow-empty",
                          "-m", "root\n\n%s" % self.root_id])
            ch.cmd_quiet(["git", "push", "-q", "origin", "root"])
            ch.chdir(cwd)
      except OSError as x:
         ch.FATAL("can't create or delete temporary directory: %s: %s"
                  % (x.filename, x.strerror))

   def branch(self, new, base):
      "Create branch new pointing to base, replacing any existing branch new."
      ch.cmd_quiet(["git", "branch", "-f", new, base], cwd=self.root)

   def checkout(self, image, git_hash):
      self.worktree_add(image, git_hash)
      self.git_restore(image.unpack_path)

   def commit(self, path, sid, msg):
      fm = self.git_prepare(path)
      cwd = ch.chdir(path)
      t = ch.Timer()
      ch.cmd_quiet(["git", "add", "-A"])
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
      ch.chdir(cwd)
      self.git_restore(path, fm)
      return git_hash

   def find_image(self, image):
      """Return (state ID, commit) of branch tip for image, or (None, None) if
         no such branch."""
      # Note abbreviated commit hash %h is automatically long enough to avoid
      # collisions.
      cp = ch.cmd_stdout(["git", "log", "--format=%h%n%B", "-n", "1",
                          image.ref.for_path], fail_ok=True, cwd=self.root)
      if (cp.returncode == 0):  # branch exists
         sid = State_ID.from_text(cp.stdout)
         commit = cp.stdout.split("\n", maxsplit=1)[0]
         commit_short = commit[:7]
      else:
         sid = None
         commit = None
         commit_short = 'lol'
      ch.VERBOSE("branch: %s: %s %s" % (image.ref.for_path, commit_short, sid))
      return (sid, commit)

   def find_sid(self, sid, branch):
      """Return the hash of the commit matching State_ID, or None if no such
         commit exists. First search branch branch, then if not found, the
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
      ch.cmd_quiet(["git", "gc", "--prune=now"], cwd=self.root)
      t.log("collected garbage")

   def git_prepare(self, unpack_path):
      """Recursively walk the given unpack path and prepare it for a Git
         commit. For each file, in this order:

           1. Record file metadata, specifically mode and timestamps, because
              Git does not save metadata beyond a limited executable bit.
              (More may be saved in the future; see issue #FIXME.)

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

           4. For non-directories with link count greater than 1, print a
              warning. They will become multiple separate files when the
              cached state is restored. (This may change in the future; see
              issue #FIXME.)

              Note: Directories cannot be hard-linked [1].

           5. Filenames starting in “.git” are special to Git. Therefore,
              except at the root where “.git” files support the cache’s Git
              worktree, rename them to begin with “.weirdal_” instead.

         Return the File_Metadata tree and also save it in “ch/git.pickle”.

         [1]: https://en.wikipedia.org/wiki/Hard_link#Limitations"""
      t = ch.Timer()
      cwd = ch.chdir(unpack_path)
      met = self.git_prepare_walk(None, ".", os.lstat("."))
      ch.file_write("ch/git.pickle", pickle.dumps(met, protocol=4))
      ch.chdir(cwd)
      t.log("gathered metadata")
      return met

   def git_prepare_walk(self, parent, name, st):
      """Return a File_Metadata object describing file name and its children
         (if name is a directory), and rename files as described in
         git_preserve(). Changes CWD during operation but does restore it."""
      # While the standard library provides a similar function os.walk() that
      # is internally recursive, it must be used iteratively.
      fm = File_Metadata(name, st)
      path = name if parent is None else "%s/%s" % (parent, name)
      # Validate file type and recurse if necessary.
      if   (   stat.S_ISREG(st.st_mode)
            or stat.S_ISLNK(st.st_mode)
            or stat.S_ISFIFO(st.st_mode)):
         pass  # stat(2) gave us all we needed
      elif (   stat.S_ISSOCK(st.st_mode)):
         ch.WARNING("socket in image, will be ignored: %s" % path)
      elif (   stat.S_ISCHR(st.st_mode)
            or stat.S_ISBLK(st.st_mode)):
         ch.FATAL("device files invalid in image: %s" % path)
      elif (   stat.S_ISDIR(st.st_mode)):
         entries = sorted(ch.listdir(name))
         cwd = ch.chdir(name)
         for i in entries:
            if (not (parent is None and i.startswith(".git"))):
               fm.children.append(self.git_prepare_walk(path, i, os.lstat(i)))
         ch.chdir(cwd)
      else:
         ch.FATAL("unexpected file type in image: %x: %s"
                  % (stat.IFMT(st.st_mode), path))
      # Validate link count.
      if (not stat.S_ISDIR(st.st_mode) and st.st_nlink > 1):
         ch.WARNING("hard links may become multiple files: %s" % name)
      # Rename if necessary.
      if (name.startswith(".weirdal_")):
         ch.WARNING("file starts with sentinel, will be renamed: %s" % name)
      if (name.startswith(".git")):
         name_new = name.replace(".git", ".weirdal_")
         ch.VERBOSE("renaming: %s -> %s" % (name, name_new))
         ch.rename(name, name_new)
      # Done.
      return fm

   def git_restore(self, unpack_path, fm=None):
      """Opposite of git_prepare. If fm is non-None, do a quick restore,
         assuming that unpack_path is unchanged since fm was returned from
         git_prepare, rather than the directory being checked out from Git.
         I.e. only restore things that we broke in git_prepare() (e.g.,
         renaming .git files), not things that Git breaks (e.g., file
         permissions). Otherwise (i.e., fm is None), read the File_Metadata
         tree from “ch/git.pickle” under unpack_path and do a full restore.
         This method will dirty the Git working directory."""
      t = ch.Timer()
      cwd = ch.chdir(unpack_path)
      if (fm is not None):
         quick=True
      else:
         quick=False
         fm = pickle.loads(ch.file_read("ch/git.pickle", text=False))
      self.git_restore_walk(None, fm, quick)
      ch.chdir(cwd)
      t.log("restored metadata (%s)" % ("quick" if quick else "full"))

   def git_restore_walk(self, parent, fm, quick):
      "Changes CWD but restores it."
      assert (parent is not None or fm.name == ".")
      path = fm.name if parent is None else "%s/%s" % (parent, fm.name)
      # Restore self.
      if (not quick):
         if (fm.name.startswith(".git")):
            # re-create with escaped name so renaming need not be conditional
            name = fm.name.replace(".git", ".weirdal_")
         else:
            name = fm.name
         if (fm.empty_dir_p):
            ch.ossafe(os.mkdir, "can't mkdir: %s" % path, name)
         elif (stat.S_ISFIFO(fm.mode)):
            ch.ossafe(os.mkfifo, "can't make FIFO: %s" % path, name)
      if (fm.name.startswith(".git")):
         ch.rename(fm.name.replace(".git", ".weirdal_"), fm.name)
      if (not quick):
         if (stat.S_ISSOCK(fm.mode)):
            ch.WARNING("ignoring socket in image: %s" % path)
         if (os.utime in os.supports_follow_symlinks):
            ch.ossafe(os.utime, "can't restore times: %s" % path, fm.name,
                      ns=(fm.atime_ns, fm.mtime_ns), follow_symlinks=False)
         if (os.chmod in os.supports_follow_symlinks):
            ch.ossafe(os.chmod, "can't restore mode: %s" % path, fm.name,
                      stat.S_IMODE(fm.mode), follow_symlinks=False)
      # Recurse children.
      if (len(fm.children) > 0):
         cwd = ch.chdir(fm.name)  # works at top level b/c fm.name is "."
         for child in fm.children:
            self.git_restore_walk(path, child, quick)
         ch.chdir(cwd)

   def pull(self, image, last_layer=None):
      self.worktree_add(image, "root")
      # a young hen, especially one less than one year old
      pullet = pull.Image_Puller(image)
      pullet.pull_to_unpacked(last_layer)
      sid = State_ID.from_parent(self.root_id, pullet.sid_input)
      pullet.done()
      commit = self.commit(image.unpack_path, sid, 'PULL %s' % image.ref)
      self.ready(image)
      return (sid, commit)

   def ready(self, image):
      ... # FIXME

   def reset(self):
      if (self.bootstrap_ct >= 1):
         ch.WARNING("not resetting brand-new cache")
      else:
         ch.INFO("deleting build cache")
         ch.rmtree(self.root)
         ch.mkdir(self.root)
         self.bootstrap()

   def status_char(self, miss):
      "Return single character to indicate whether miss is true or not."
      return "." if miss else "*"

   def summary_print(self):
      cwd = ch.chdir(self.root)
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
      (file_ct, byte_ct) = ch.du(self.root)
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

   def tree_print(self):
      # Note the percent codes are interpreted by Git.
      # See: https://git-scm.com/docs/git-log#_pretty_formats
      if (ch.verbose == 0):
         # ref names, subject (instruction)
         fmt = "%C(auto)%d %Creset%s"
      else:
         # ref names, short commit hash, subject (instruction), body (state ID)
         # FIXME: The body contains a trailing newline I can't figure out how
         # to remove.
         fmt = "%C(auto)%d%C(yellow) %h %Creset%s %b"
      ch.cmd_base(["git", "log", "--graph", "--all", "--reflog",
                   "--topo-order", "--format=%s" % fmt], cwd=self.root)
      print()  # blank line to separate from summary

   def tree_dot(self):
      ch.version_check(["git2dot.py", "--version"], GIT2DOT_MIN)
      ch.version_check(["dot", "-V"], DOT_MIN)
      ch.INFO("writing ./build-cache.gv")
      ch.cmd_quiet(["git2dot.py",
                    "--cnode", '[label="{label}", color="bisque", shape="box"]',
                    "-d", 'graph[rankdir="TB", fontsize=10.0, bgcolor="white"]',
                    "-l", "%h|%s",
                    "%s/build-cache.gv" % os.getcwd()], cwd=self.root)
      ch.INFO("writing ./build-cache.pdf")
      ch.cmd_quiet(["dot", "-Tpdf", "-obuild-cache.pdf", "build-cache.gv"])

   def worktree_add(self, image, base):
      t = ch.Timer()
      image.unpack_clear()
      ch.cmd_quiet(["git", "worktree", "add", "-f", "-B", image.ref.for_path,
                    image.unpack_path, base], cwd=self.root)
      t.log("created worktree")


class Rebuild_Cache(Enabled_Cache):

   ...


class Disabled_Cache(Rebuild_Cache):

   def status_char(self, miss):
      return " "
