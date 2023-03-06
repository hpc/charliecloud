import errno
import fcntl
import getpass
import hashlib
import json
import os
import pathlib
import re
import pprint
import shutil
import stat
import tarfile
import version

import charliecloud as ch


## Constants ##

# Storage directory format version. We refuse to operate on storage
# directories with non-matching versions. Increment this number when the
# format changes non-trivially.
#
# To see the directory formats in released versions:
#
#   $ git grep -F 'STORAGE_VERSION =' $(git tag | sort -V)
STORAGE_VERSION = 5


## Globals ##

# True if we lock storage directory to prevent concurrent access; false for no
# locking (which is very YOLO and may break the storage directory).
storage_lock = True


## Classes ##

class Path(pathlib.PosixPath):
   """Stock Path objects have the very weird property that appending an
      *absolute* path to an existing path ignores the left operand, leaving
      only the absolute right operand:

        >>> import pathlib
        >>> a = pathlib.Path("/foo/bar")
        >>> a.joinpath("baz")
        PosixPath('/foo/bar/baz')
        >>> a.joinpath("/baz")
        PosixPath('/baz')

      This is contrary to long-standing UNIX/POSIX, where extra slashes in a
      path are ignored, e.g. the path "foo//bar" is equivalent to "foo/bar".
      It seems to be inherited from os.path.join().

      Even with the relatively limited use of Path objects so far, this has
      caused quite a few bugs. IMO it's too difficult and error-prone to
      manually manage whether paths are absolute or relative. Thus, this
      subclass introduces a new operator "//" which does the right thing,
      i.e., if the right operand is absolute, that fact is ignored. E.g.:

        >>> a = Path("/foo/bar")
        >>> a.joinpath_posix("baz")
        Path('/foo/bar/baz')
        >>> a.joinpath_posix("/baz")
        Path('/foo/bar/baz')
        >>> a // "/baz"
        Path('/foo/bar/baz')
        >>> "/baz" // a
        Path('/baz/foo/bar')

      We introduce a new operator because it seemed like too subtle a change
      to the existing operator "/" (which we disable to avoid getting burned
      here in Charliecloud). An alternative was "+" like strings, but that led
      to silently wrong results when the paths *were* strings (components
      concatenated with no slash)."""

   # Name of the gzip(1) to use; set on first call of file_gzip().
   gzip = None

   def __floordiv__(self, right):
      return self.joinpath_posix(right)

   def __len__(self):
      return self.parts.__len__()

   def __rfloordiv__(self, left):
      left = Path(left)
      return left.joinpath_posix(self)

   def __rtruediv__(self, left):
      return NotImplemented

   def __truediv__(self, right):
      return NotImplemented

   @property
   def first(self):
      """Return my first component, or if I have no components (i.e.,
         Path(".")), return None."""
      try:
         return self.parts[0]
      except IndexError:
         return None

   @property
   def git_escaped(self):
      "Return a copy of me escaped for Git storage."
      assert (self.git_incompatible_p)
      return self.with_name(self.name.replace(".git", ".weirdal_"))

   @property
   def git_incompatible_p(self):
      "Return True if I can’t be stored in Git because of my name."
      return self.name.startswith(".git")

   @classmethod
   def gzip_set(cls):
      """Set gzip class attribute on first call to file_gzip().

         Note: We originally thought this could be accomplished WITHOUT
         calling a class method (by setting the attribute, e.g. “self.gzip =
         'foo'”), but it turned out that this would only set the attribute for
         the single instance. To set self.gzip for all instances, we need the
         class method."""
      if (cls.gzip is None):
         if (shutil.which("pigz") is not None):
            cls.gzip = "pigz"
         elif (shutil.which("gzip") is not None):
            cls.gzip = "gzip"
         else:
            ch.FATAL("can’t find path to gzip or pigz")

   def add_suffix(self, suff):
      """Returns the path object restulting from appending the specified
         suffix to the end of the path name. E.g. Path(foo).add_suffix(".txt")
         returns Path("foo.txt)."""
      return Path(str(self) + suff)

   def chdir(self):
      "Change CWD to path and return previous CWD. Exit on error."
      old = ch.ossafe(os.getcwd, "can’t get cwd(2)")
      ch.ossafe(os.chdir, "can’t chdir: %s" % self.name, self)
      return Path(old)

   def chmod_min(self, st=None):
      """Set my permissions to at least 0o700 for directories and 0o400
         otherwise. If given, st is a stat object for self, to avoid another
         stat(2) call if unneeded. Return the new file mode (complete, not
         just permission bits).

         For symlinks, do nothing, because we don’t want to follow symlinks
         and follow_symlinks=False (or os.lchmod) is not supported on some
         (all?) Linux. (Also, symlink permissions are ignored on Linux, so it
         doesn’t matter anyway.)"""
      if (st is None):
         st = self.stat_(False)
      if (stat.S_ISLNK(st.st_mode)):
         return st.st_mode
      perms_old = stat.S_IMODE(st.st_mode)
      perms_new = perms_old | (0o700 if stat.S_ISDIR(st.st_mode) else 0o400)
      if (perms_new != perms_old):
         ch.VERBOSE("fixing permissions: %s: %03o -> %03o"
                 % (self, perms_old, perms_new))
         ch.ossafe(os.chmod, "can’t chmod: %s" % self, self, perms_new)
      return (st.st_mode | perms_new)

   def copytree(self, *args, **kwargs):
      "Wrapper for shutil.copytree() that exits on the first error."
      shutil.copytree(str(self), copy_function=ch.copy2, *args, **kwargs)

   def disk_bytes(self):
      """Return the number of disk bytes consumed by path. Note this is
         probably different from the file size."""
      return self.stat().st_blocks * 512

   def du(self):
      """Return a tuple (number of files, total bytes on disk) for everything
         under path. Warning: double-counts files with multiple hard links."""
      file_ct = 1
      byte_ct = self.disk_bytes()
      for (dir_, subdirs, files) in os.walk(self):
         file_ct += len(subdirs) + len(files)
         byte_ct += sum(Path(dir_ + "/" + i).disk_bytes()
                        for i in subdirs + files)
      return (file_ct, byte_ct)

   def exists_(self, links=False):
      "Return True if I exist, False otherwise. Iff links, follow symlinks."
      try:
         # Don’t wrap self.exists() because that always follows symlinks. Use
         # os.stat() b/c it has follow_symlinks in 3.6, unlike self.stat().
         os.stat(self, follow_symlinks=links)
      except FileNotFoundError:
         return False
      except OSError as x:
         ch.FATAL("can’t stat: %s: %s" % (self, x.strerror))
      return True

   def file_ensure_exists(self):
      """If the final element of path exists (without dereferencing if it’s a
         symlink), do nothing; otherwise, create it as an empty regular file."""
      if (not os.path.lexists(self)): # no substitute for lexists() in pathlib.
         fp = self.open_("w")
         ch.close_(fp)

   def file_gzip(self, args=[]):
      """Run pigz(1) if it’s available, otherwise gzip(1), on file at path and
         return the file's new name. Pass args to the gzip executable. This
         lets us gzip files (a) in parallel if pigz(1) is installed and
         (b) without reading them into memory."""
      path_c = self.add_suffix(".gz")
      # On first call, remember first available of pigz and gzip using class
      # attribute 'gzip'.
      Path.gzip_set()
      # Remove destination if it already exists, because “gzip --force” does
      # several other things too. Also, pigz(1) sometimes confusingly reports
      # “Inappropriate ioctl for device” if destination already exists.
      if (path_c.exists()):
         path_c.unlink()
      # Compress.
      ch.cmd([self.gzip] + args + [str(self)])
      # Zero out GZIP header timestamp, bytes 4–7 zero-indexed inclusive [1],
      # to ensure layer hash is consistent. See issue #1080.
      # [1]: https://datatracker.ietf.org/doc/html/rfc1952 §2.3.1
      fp = path_c.open_("r+b")
      ch.ossafe(fp.seek, "can’t seek: %s" % fp, 4)
      ch.ossafe(fp.write, "can’t write: %s" % fp, b'\x00\x00\x00\x00')
      ch.close_(fp)
      return path_c

   def file_hash(self):
      """Return the hash of data in file at path, as a hex string with no
         algorithm tag. File is read in chunks and can be larger than memory."""
      fp = self.open_("rb")
      h = hashlib.sha256()
      while True:
         data = ch.ossafe(fp.read, "can’t read: %s" % self.name, 2**18)
         if (len(data) == 0):
            break  # EOF
         h.update(data)
      ch.close_(fp)
      return h.hexdigest()

   def file_read_all(self, text=True):
      """Return the contents of file at path, or exit with error. If text, read
         in "rt" mode with UTF-8 encoding; otherwise, read in mode "rb"."""
      if (text):
         mode = "rt"
         encoding = "UTF-8"
      else:
         mode = "rb"
         encoding = None
      fp = self.open_(mode, encoding=encoding)
      data = ch.ossafe(fp.read, "can't read: %s" % self.name)
      ch.close_(fp)
      return data

   def file_size(self, follow_symlinks=False):
      "Return the size of file at path in bytes."
      st = ch.ossafe(os.stat, "can’t stat: %s" % self.name,
                  self, follow_symlinks=follow_symlinks)
      return st.st_size

   def file_write(self, content):
      if (isinstance(content, str)):
         content = content.encode("UTF-8")
      fp = self.open_("wb")
      ch.ossafe(fp.write, "can’t write: %s" % self.name, content)
      ch.close_(fp)

   def grep_p(self, rx):
      """Return True if file at path contains a line matching regular
         expression rx, False if it does not."""
      rx = re.compile(rx)
      try:
         with open(self, "rt") as fp:
            for line in fp:
               if (rx.search(line) is not None):
                  return True
         return False
      except OSError as x:
         ch.FATAL("can’t read %s: %s" % (self.name, x.strerror))

   def hardlink(self, target):
      try:
         os.link(target, self)  # no super().hardlink_to() until 3.10
      except OSError as x:
         ch.FATAL("can’t hard link: %s -> %s: %s" % (self, target, x.strerror))

   def is_relative_to(self, *other):
      try:
         return super().is_relative_to(*other)
      except AttributeError:
         # pathlib.Path.is_relative_to() was introduced in 3.9. If not
         # available, use the standard library’s trivial definition in terms
         # of relative_to().
         try:
            self.relative_to(*other)
            return True
         except ValueError:
            return False

   def joinpath_posix(self, other):
      # This method is a hot spot, so the hairiness is due to optimizations.
      # It runs about 30% faster than the naïve verson below.
      if (isinstance(other, Path)):
         other_parts = other._parts
         if (len(other_parts) > 0 and other_parts[0] == "/"):
            other_parts = other_parts[1:]
      elif (isinstance(other, str)):
         other_parts = other.split("/")
         if (len(other_parts) > 0 and len(other_parts[0]) == 0):
            other_parts = other_parts[1:]
      else:
         ch.INFO(type(other))
         assert False, "unknown type"
      return self._from_parsed_parts(self._drv, self._root,
                                     self._parts + other_parts)
      # Naïve implementation for reference.
      #other = Path(other)
      #if (other.is_absolute()):
      #   other = other.relative_to("/")
      #   assert (not other.is_absolute())
      #return self.joinpath(other)

   def json_from_file(self, msg):
      ch.DEBUG("loading JSON: %s: %s" % (msg, self))
      text = self.file_read_all()
      ch.TRACE("text:\n%s" % text)
      try:
         data = json.loads(text)
         ch.DEBUG("result:\n%s" % pprint.pformat(data, indent=2))
      except json.JSONDecodeError as x:
         ch.FATAL("can’t parse JSON: %s:%d: %s" % (self.name, x.lineno, x.msg))
      return data

   def listdir(self):
      """Return set of entries in directory path, as strings, without self (.)
         and parent (..). We considered changing this to use os.scandir() for
         #992, but decided that the advantages it offered didn’t warrant the
         effort required to make the change."""
      return set(ch.ossafe(os.listdir, "can’t list: %s" % self.name, self))

   def strip(self, left=0, right=0):
      """Return a copy of myself with n leading components removed. E.g.:

           >>> a = Path("/a/b/c")
           >>> a.strip(left=1)
           Path("a/b/c")
           >>> a.strip(right=1)
           Path("/a/b")
           >>> a.strip(left=1, right=1)
           Path("a/b")

         It is an error if I don’t have at least left + right components,
         i.e., you can strip a path down to nothing but not further."""
      assert (len(self.parts) >= left + right)
      return Path(*self.parts[left:len(self.parts)-right])

   def mkdir_(self):
      ch.TRACE("ensuring directory: %s" % self)
      try:
         super().mkdir(exist_ok=True)
      except FileExistsError as x:
         ch.FATAL("can’t mkdir: exists and not a directory: %s" % x.filename)
      except OSError as x:
         ch.FATAL("can’t mkdir: %s: %s: %s" % (self.name, x.filename,
                                               x.strerror))

   def mkdirs(self, exist_ok=True):
      ch.TRACE("ensuring directories: %s" % self.name)
      try:
         os.makedirs(self, exist_ok=exist_ok)
      except OSError as x:
         ch.FATAL("can’t mkdir: %s: %s: %s" % (self.name, x.filename,
                                               x.strerror))

   def open_(self, mode, *args, **kwargs):
      return ch.ossafe(super().open,
                       "can't open for %s: %s" % (mode, self.name),
                       mode, *args, **kwargs)

   def rename_(self, name_new):
      if (Path(name_new).exists()):
         ch.FATAL("can’t rename: destination exists: %s" % name_new)
      ch.ossafe(super().rename,
                "can’t rename: %s -> %s" % (self.name, name_new),
                name_new)

   def rmdir_(self):
      ch.ossafe(super().rmdir, "can’t rmdir: %s" % self.name)

   def rmtree(self):
      if (self.is_dir()):
         ch.TRACE("deleting directory: %s" % self.name)
         try:
            shutil.rmtree(self)
         except OSError as x:
            ch.FATAL("can’t recursively delete directory %s: %s: %s"
                     % (self.name, x.filename, x.strerror))
      else:
         assert False, "unimplemented"

   def stat_(self, links):
      """An error-checking version of stat(). Note that we cannot simply
         change the definition of stat() to be ossafe, as the exists() method
         in pathlib relies on an OSError check.

         See: https://github.com/python/cpython/blob/3.10/Lib/pathlib.py#L1291

         NOTE: We also cannot just call super().stat here because the
         follow_symlinks kwarg is absent in pathlib for Python 3.6, which we
         want to retain compatibility with."""
      return ch.ossafe(os.stat, "can’t stat: %s" % self, self,
                    follow_symlinks=links)

   def symlink(self, target, clobber=False):
      if (clobber and self.is_file()):
         self.unlink_()
      try:
         super().symlink_to(target)
      except FileExistsError:
         if (not self.is_symlink()):
            ch.FATAL("can’t symlink: source exists and isn't a symlink: %s"
                     % self.name)
         if (self.readlink() != target):
            ch.FATAL("can’t symlink: %s exists; want target %s but existing is %s"
                     % (self.name, target, self.readlink()))
      except OSError as x:
         ch.FATAL("can’t symlink: %s -> %s: %s" % (self.name, target,
                                                   x.strerror))

   def unlink_(self, *args, **kwargs):
      ch.ossafe(super().unlink, "can't unlink: %s" % self.name)


class Storage:

   """Source of truth for all paths within the storage directory. Do not
      compute any such paths elsewhere!"""

   __slots__ = ("lockfile_fp",
                "root")

   def __init__(self, storage_cli):
      self.root = storage_cli
      if (self.root is None):
         self.root = self.root_env()
      if (self.root is None):
         self.root = self.root_default()
      if (not self.root.is_absolute()):
         self.root = os.getcwd() // self.root

   @property
   def build_cache(self):
      return self.root // "bucache"

   @property
   def build_large(self):
      return self.root // "bularge"

   @property
   def download_cache(self):
      return self.root // "dlcache"

   @property
   def image_tmp(self):
      return self.root // "imgtmp"

   @property
   def lockfile(self):
      return self.root // "lock"

   @property
   def mount_point(self):
      return self.root // "mnt"

   @property
   def unpack_base(self):
      return self.root // "img"

   @property
   def upload_cache(self):
      return self.root // "ulcache"

   @property
   def valid_p(self):
      """Return True if storage present and seems valid, even if old, False
         otherwise. This answers “is the storage directory real”, not “can
         this storage directory be used”; it should return True for more or
         less any Charliecloud storage directory we might feasibly come
         across, even if it can't be upgraded. See also #1147."""
      return (os.path.isdir(self.unpack_base) and
              os.path.isdir(self.download_cache))

   @property
   def version_file(self):
      return self.root // "version"

   @staticmethod
   def root_default():
      # FIXME: Perhaps we should use getpass.getch.user() instead of the $USER
      # environment variable? It seems a lot more robust. But, (1) we'd have
      # to match it in some scripts and (2) it makes the documentation less
      # clear becase we have to explain the fallback behavior.
      return Path("/var/tmp/%s.ch" % ch.user())

   @staticmethod
   def root_env():
      if ("CH_GROW_STORAGE" in os.environ):
         # Avoid surprises if user still has $CH_GROW_STORAGE set (see #906).
         ch.FATAL("$CH_GROW_STORAGE no longer supported; use $CH_IMAGE_STORAGE")
      if (not "CH_IMAGE_STORAGE" in os.environ):
         return None
      path = Path(os.environ["CH_IMAGE_STORAGE"])
      if (not path.is_absolute()):
         ch.FATAL("$CH_IMAGE_STORAGE: not absolute path: %s" % path)
      return path

   def build_large_path(self, name):
      return self.build_large // name

   def init(self):
      """Ensure the storage directory exists, contains all the appropriate
         top-level directories & metadata, and is the appropriate version."""
      # WARNING: This function contains multiple calls to self.lock(). The
      # point is to lock as soon as we know the storage directory exists, and
      # definitely before writing anything, to reduce the race conditions that
      # surely exist. Ensure new code paths also call self.lock().
      if (not os.path.isdir(self.root)):
         op = "initializing"
         v_found = None
      else:
         op = "upgrading"  # not used unless upgrading
         if (not self.valid_p):
            if (os.path.exists(self.root) and not self.root.listdir()):
               hint = "let Charliecloud create %s; see FAQ" % self.root.name
            else:
               hint = None
            ch.FATAL("storage directory seems invalid: %s" % self.root, hint=hint)
         v_found = self.version_read()
      if (v_found == STORAGE_VERSION):
         ch.VERBOSE("found storage dir v%d: %s" % (STORAGE_VERSION, self.root))
         self.lock()
      elif (v_found in {None, 1, 2, 3, 4}):  # initialize/upgrade
         ch.INFO("%s storage directory: v%d %s"
                 % (op, STORAGE_VERSION, self.root))
         self.root.mkdir_()
         self.lock()
         self.download_cache.mkdir_()
         self.build_cache.mkdir_()
         self.build_large.mkdir_()
         self.unpack_base.mkdir_()
         self.upload_cache.mkdir_()
         for old in self.unpack_base.iterdir():
            new = old.parent // str(old.name).replace(":", "+")
            if (old != new):
               if (new.exists()):
                  ch.FATAL("can't upgrade: already exists: %s" % new)
               old.rename(new)
         self.version_file.file_write("%d\n" % STORAGE_VERSION)
      else:                         # can't upgrade
         ch.FATAL("incompatible storage directory v%d: %s"
                  % (v_found, self.root),
                  'you can delete and re-initialize with "ch-image reset"')
      self.validate_strict()

   def lock(self):
      """Lock the storage directory. Charliecloud does not at present support
         concurrent use of ch-image(1) against the same storage directory."""
      # File locking on Linux is a disaster [1, 2]. Currently, we use POSIX
      # fcntl(2) locking, which has major pitfalls but should be fine for our
      # use case. It apparently works on NFS [3] and does not require
      # cleanup/stealing like a lock file would.
      #
      # [1]: https://apenwarr.ca/log/20101213
      # [2]: http://0pointer.de/blog/projects/locking.html
      # [3]: https://stackoverflow.com/a/22411531
      if (not storage_lock):
         return
      self.lockfile_fp = self.lockfile.open_("w")
      try:
         fcntl.lockf(self.lockfile_fp, fcntl.LOCK_EX | fcntl.LOCK_NB)
      except OSError as x:
         if (x.errno in { errno.EACCES, errno.EAGAIN }):
            ch.FATAL("storage directory is already in use",
                     "concurrent instances of ch-image cannot share the same storage directory")
         else:
            ch.FATAL("can't lock storage directory: %s" % x.strerror)

   def manifest_for_download(self, image_ref, digest):
      if (digest is None):
         digest = "skinny"
      return (   self.download_cache
              // ("%s%%%s.manifest.json" % (image_ref.for_path, digest)))

   def fatman_for_download(self, image_ref):
      return self.download_cache // ("%s.fat.json" % image_ref.for_path)

   def reset(self):
      if (self.valid_p):
         self.root.rmtree()
         self.init()  # largely for debugging
      else:
         ch.FATAL("%s not a builder storage" % (self.root));

   def unpack(self, image_ref):
      return self.unpack_base // image_ref.for_path

   def validate_strict(self):
      """Validate storage directory structure; if something is wrong, exit
         with an error message. This is a strict validation; the version must
         be current, the structure of the directory must be current, and
         nothing unexpected may be present. However, it is not comprehensive.
         The main purpose is to check for bad upgrades and other programming
         errors, not meddling."""
      ch.DEBUG("validating storage directory: %s" % self.root)
      msg_prefix = "invalid storage directory"
      # Check that all expected files exist, and no others. Note that we don't
      # verify file *type*, assuming that kind of error is rare.
      entries = self.root.listdir()
      for entry in { i.name for i in (self.build_cache,
                                      self.build_large,
                                      self.download_cache,
                                      self.unpack_base,
                                      self.upload_cache,
                                      self.version_file) }:
         try:
            entries.remove(entry)
         except KeyError:
            ch.FATAL("%s: missing file or directory: %s" % (msg_prefix, entry))
      entries -= { i.name for i in (self.lockfile, self.mount_point) }
      if (len(entries) > 0):
         ch.FATAL("%s: extraneous file(s): %s"
               % (msg_prefix, " ".join(sorted(entries))))
      # check version
      v_found = self.version_read()
      if (v_found != STORAGE_VERSION):
         ch.FATAL("%s: version mismatch: %d expected, %d found"
               % (msg_prefix, STORAGE_VERSION, v_found))
      # check that no image directories have “:” in filename
      assert isinstance(self.unpack_base, Path) # remove if test suite passes
      imgs = self.unpack_base.listdir()
      imgs_bad = set()
      for img in imgs:
         if (":" in img):  # bad char check b/c problem here is bad upgrade
            ch.FATAL("%s: storage directory broken: bad image dir name: %s"
                     % (msg_prefix, img), ch.BUG_REPORT_PLZ)

   def version_read(self):
      if (os.path.isfile(self.version_file)):
          # WARNING: version_file might not be Path
         text = self.version_file.file_read_all()
         try:
            return int(text)
         except ValueError:
            ch.FATAL('malformed storage version: "%s"' % text)
      else:
         return 1


class TarFile(tarfile.TarFile):

   # This subclass augments tarfile.TarFile to add safety code. While the
   # tarfile module docs [1] say “do not use this class [TarFile] directly”,
   # they also say “[t]he tarfile.open() function is actually a shortcut” to
   # class method TarFile.open(), and the source code recommends subclassing
   # TarFile [2].
   #
   # It's here because the standard library class has problems with symlinks
   # and replacing one file type with another; see issues #819 and #825 as
   # well as multiple unfixed Python bugs [e.g. 3,4,5]. We work around this
   # with manual deletions.
   #
   # [1]: https://docs.python.org/3/library/tarfile.html
   # [2]: https://github.com/python/cpython/blob/2bcd0fe7a5d1a3c3dd99e7e067239a514a780402/Lib/tarfile.py#L2159
   # [3]: https://bugs.python.org/issue35483
   # [4]: https://bugs.python.org/issue19974
   # [5]: https://bugs.python.org/issue23228

   # Need new method name because add() is called recursively and we don't
   # want those internal calls to get our special sauce.
   def add_(self, name, **kwargs):
      def filter_(ti):
         assert (ti.name == "." or ti.name[:2] == "./")
         if (ti.name.startswith("./.git") or ti.name == "./ch/git.pickle"):
            ch.DEBUG("omitting from push: %s" % ti.name)
            return None
         self.fix_member_uidgid(ti)
         return ti
      kwargs["filter"] = filter_
      super().add(name, **kwargs)

   def clobber(self, targetpath, regulars=False, symlinks=False, dirs=False):
      assert (regulars or symlinks or dirs)
      try:
         st = os.lstat(targetpath)
      except FileNotFoundError:
         # We could move this except clause after all the stat.S_IS* calls,
         # but that risks catching FileNotFoundError that came from somewhere
         # other than lstat().
         st = None
      except OSError as x:
         ch.FATAL("can't lstat: %s" % targetpath, targetpath)
      if (st is not None):
         if (stat.S_ISREG(st.st_mode)):
            if (regulars):
               Path(targetpath).unlink_()
         elif (stat.S_ISLNK(st.st_mode)):
            if (symlinks):
               Path(targetpath).unlink_()
         elif (stat.S_ISDIR(st.st_mode)):
            if (dirs):
               Path(targetpath).rmtree()
         else:
            ch.FATAL("invalid file type 0%o in previous layer; see inode(7): %s"
                     % (stat.S_IFMT(st.st_mode), targetpath))

   @staticmethod
   def fix_link_target(ti, tb):
      """Deal with link (symbolic or hard) weirdness or breakage. If it can be
         fixed, fix it; if not, abort the program."""
      src = Path(ti.name)
      tgt = Path(ti.linkname)
      fix_ct = 0
      # Empty target not allowed; have to check string b/c "" -> Path(".").
      if (len(ti.linkname) == 0):
         ch.FATAL("rejecting link with empty target: %s: %s" % (tb, ti.name))
      # Fix absolute link targets.
      if (tgt.is_absolute()):
         if (ti.issym()):
            # Change symlinks to relative for correct interpretation inside or
            # outside the container.
            kind = "symlink"
            new = (  Path(*(("..",) * (len(src.parts) - 1)))
                   // Path(*(tgt.parts[1:])))
         elif (ti.islnk()):
            # Hard links refer to tar member paths; just strip leading slash.
            kind = "hard link"
            new = tgt.relative_to("/")
         else:
            assert False, "not a link"
         ch.DEBUG("absolute %s: %s -> %s: changing target to: %s"
               % (kind, src, tgt, new))
         tgt = new
         fix_ct = 1
      # Reject links that climb out of image (FIXME: repair instead).
      if (".." in os.path.normpath(src // tgt).split("/")):
         ch.FATAL("rejecting too many up-levels: %s: %s -> %s" % (tb, src, tgt))
      # Done.
      ti.linkname = str(tgt)
      return fix_ct

   @staticmethod
   def fix_member_uidgid(ti):
      assert (ti.name[0] != "/")  # absolute paths unsafe but shouldn't happen
      if (not (ti.isfile() or ti.isdir() or ti.issym() or ti.islnk())):
         ch.FATAL("invalid file type: %s" % ti.name)
      ti.uid = 0
      ti.uname = "root"
      ti.gid = 0
      ti.gname = "root"
      if (ti.mode & stat.S_ISUID):
         ch.VERBOSE("stripping unsafe setuid bit: %s" % ti.name)
         ti.mode &= ~stat.S_ISUID
      if (ti.mode & stat.S_ISGID):
         ch.VERBOSE("stripping unsafe setgid bit: %s" % ti.name)
         ti.mode &= ~stat.S_ISGID

   def makedir(self, tarinfo, targetpath):
      # Note: This gets called a lot, e.g. once for each component in the path
      # of the member being extracted.
      ch.TRACE("makedir: %s" % targetpath)
      self.clobber(targetpath, regulars=True, symlinks=True)
      super().makedir(tarinfo, targetpath)

   def makefile(self, tarinfo, targetpath):
      ch.TRACE("makefile: %s" % targetpath)
      self.clobber(targetpath, symlinks=True, dirs=True)
      super().makefile(tarinfo, targetpath)

   def makelink(self, tarinfo, targetpath):
      ch.TRACE("makelink: %s -> %s" % (targetpath, tarinfo.linkname))
      self.clobber(targetpath, regulars=True, symlinks=True, dirs=True)
      super().makelink(tarinfo, targetpath)
