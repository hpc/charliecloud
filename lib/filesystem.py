import errno
import fcntl
import fnmatch
import glob
import hashlib
import json
import os
import re
import pprint
import shutil
import stat
import struct
import tarfile

import charliecloud as ch


## Constants ##

# Storage directory format version. We refuse to operate on storage
# directories with non-matching versions. Increment this number when the
# format changes non-trivially.
#
# To see the directory formats in released versions:
#
#   $ git grep -E '^STORAGE_VERSION =' $(git tag | sort -V)
STORAGE_VERSION = 7


## Globals ##

# True if we lock storage directory to prevent concurrent access; false for no
# locking (which is very YOLO and may break the storage directory).
storage_lock = True


### Functions ###

def copy(src, dst, follow_symlinks=False):
   """Copy file src to dst. Wrapper function providing same signature as
      shutil.copy2(). See Path.copy() for lots of gory details. Accepts
      follow_symlinks, but the only valid value is False."""
   assert (not follow_symlinks)
   if (isinstance(src, str)):
      src = Path(src)
   if (isinstance(dst, str)):
      dst = Path(dst)
   src.copy(dst)


## Classes ##

class Path(os.PathLike):
   """Path class roughly corresponding to pathlib.PosixPath. While it does
      subclass os.PathLike, it does not subclass anything in pathlib because:

        1. Only in 3.12 does pathlib.Path actually support subclasses [1].
           Before then it can be done, but it’s messy and brittle.

        2. pathlib.Path seems overcomplicated for our use case and is often
           slow.

      This class implements (incompletely) the pathlib.PosixPath API, with
      many extensions and two important differences:

        1. Trailing slash. Objects remember whether a trailing slash is
           present, and append it when str() or repr().

           “/” is considered to *not* have a trailing slash. Subprograms might
           interpret this differently. Notably, rsync(1) *does* interpret “/”
           as trailing-slashed.

        2. Path join operator. This class uses the “//” operator, not “/”, for
           joining paths, with different semantics.

           When appending an absolute path to a pathlib.PosixPath object, the
           left operand is ignored, leaving only the absolute right operand:

             >>> import pathlib
             >>> a = pathlib.Path("/foo/bar")
             >>> a / "baz"
             PosixPath('/foo/bar/baz')
             >>> a / "/baz"
             PosixPath('/baz')

           This is contrary to long-standing UNIX/POSIX, where extra slashes
           in a path are ignored, e.g. “/foo//bar” is equivalent to
           “/foo/bar”. os.path.join() behaves the same way. This behavior
           caused quite a few Charliecloud bugs. IMO it’s too error-prone to
           manually manage whether paths are absolute or relative.

           Thus, joins paths with “//”, which does the right thing, i.e., if
           the right operand is absolute, that fact is just ignored. E.g.:

             >>> a = Path("/foo/bar")
             >>> a // "/baz"
             Path('/foo/bar/baz')
             >>> "/baz" // a
             Path('/baz/foo/bar')

           We used a different operator because it seemed a source of
           confusion to change the behavior of “/” (which is not provided by
           this class). An alternative was “+” like strings, but that led to
           silently wrong results when the paths *were* strings (simple string
           concatenation with no slash).

      [1]: https://docs.python.org/3/whatsnew/3.12.html#pathlib"""

   # Store the path as a string. Assume:
   #
   #   1. No multiple slashes.
   #   2. Length at least one character.
   #   3. Does not begin with redundant “./” (but can be just “.”).
   #
   # Call self._tidy() if these can’t be assumed.
   __slots__ = ("path",)

   # Name of the gzip(1) to use for file_gzip(); set on first call.
   gzip = None

   def __init__(self, *segments):
      """e.g.:

           >>> Path("/a/b")
           Path('/a/b')
           >>> Path("/", "a", "b")
           Path('/a/b')
           >>> Path("/", "a", "b", "/")
           Path('/a/b/')
           >>> Path("a/b")
           Path('a/b')
           >>> Path("/a/b/")
           Path('/a/b/')
           >>> Path("//")
           Path('/')
           >>> Path("")
           Path('.')
           >>> Path("./a")
           Path('a')"""
      segments = [    (i.__fspath__() if isinstance(i, os.PathLike) else i)
                  for i in segments]
      self.path = "/".join(segments)
      self._tidy()

   ## Internal ##

   @classmethod
   def _gzip_set(cls):
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

   def _tidy(self):
      "Repair self.path assumptions (see attribute docs above)."
      if (self.path == ""):
         self.path = "."
      else:
         self.path = re.sub(r"/{2,}", "/", self.path)
         self.path = re.sub(r"^\./", "", self.path)

   ## pathlib.PosixPath API ##

   def __eq__(self, other):
      """e.g.:

           >>> a1 = Path("a")
           >>> a2 = Path("a")
           >>> b = Path("b")
           >>> a1 == a1
           True
           >>> a1 is a1
           True
           >>> a1 == a2
           True
           >>> a1 is a2
           False
           >>> a1 == b
           False
           >>> a1 != b
           True
           >>> Path("a") == Path("a/")
           False
           >>> Path("a") == Path("a/").untrailed
           True
           >>> Path("") == Path(".")
           True
           >>> Path("/") == Path("//")
           True
           >>> Path("a/b") == Path("a//b") == Path("a///b")
           True"""
      return (self.path == other.path)

   def __fspath__(self):
      return self.path

   def __hash__(self):
      return hash(self.path)

   def __repr__(self):
      """e.g.:

           >>> repr(Path("a"))
           "Path('a')"
           >>> repr(Path("a'b"))
           'Path("a\\'b")'
      """
      return 'Path(%s)' % repr(self.path)

   def __str__(self):
      """e.g.:

           >>> str(Path("a"))
           'a'"""
      return self.path

   @property
   def name(self):
      """e.g.:

           >>> Path("a").name
           'a'
           >>> Path("/a/b").name
           'b'
           >>> Path("a/b").name
           'b'
           >>> Path("a/b/").name
           'b'

         Note: Unlike pathlib.Path, dot and slash return themselves:

           >>> Path("/").name
           '/'
           >>> Path(".").name
           '.'
      """
      if (self.root_p):
         return "/"
      return self.untrailed.path.rpartition("/")[-1]

   @property
   def parent(self):
      """e.g.:

           >>> Path("/a/b").parent
           Path('/a')
           >>> Path("a/b").parent
           Path('a')
           >>> Path("/a").parent
           Path('/')
           >>> Path("a/b/").parent
           Path('a')
           >>> Path("a").parent
           Path('.')
           >>> Path(".").parent
           Path('.')

         Note that the parent of “/” is “/”, per POSIX:

           >>> Path("/").parent
           Path('/')"""
      if (self.root_p):
         return self.deepcopy()
      (parent, slash, _) = self.untrailed.path.rpartition("/")
      if (parent != ""):
         return self.__class__(parent)
      elif (slash == "/"):  # absolute path with single non-root component
         return self.__class__("/")
      else:                 # relative path with single component
         return self.__class__(".")

   @property
   def parts(self):
      """e.g.:

           >>> Path("/a/b").parts
           ['/', 'a', 'b']
           >>> Path("a/b/").parts
           ['a', 'b']
           >>> Path("/").parts
           ['/']
           >>> Path(".").parts
           []"""
      if (self.path == "."):
         return []
      ret = self.path.split("/")
      if (ret[0] == ""):
         ret[0] = "/"
      if (ret[-1] == ""):
         del ret[-1]
      return ret

   def exists(self, links=False):
      """Return True if I exist, False otherwise. Iff links, follow symlinks.

           >>> Path("/").exists()
           True
           >>> Path("/doesnotexist").exists()
           False
           >>> Path("/proc/self/cmdline").exists(False)
           True"""
      try:
         os.stat(self, follow_symlinks=links)
      except FileNotFoundError:
         return False
      except OSError as x:
         ch.FATAL("can’t stat: %s: %s" % (self, x.strerror))
      return True

   def glob(self, pattern):
      oldcwd = self.chdir()
      # No root_dir in glob.glob() until 3.10.
      ret = glob.glob(pattern, recursive=True)
      oldcwd.chdir()
      return ret

   def hardlink_to(self, target):
      ch.ossafe(os.link, "can’t hard link: %s -> %s", target, self)

   def is_absolute(self):
      return (self.path[0] == "/")

   def is_dir(self):
      """e.g.:

           >>> Path("/proc").is_dir()
           True
           >>> Path("/proc/self").is_dir()
           True
           >>> Path("/proc/cmdline").is_dir()
           False
           >>> Path("/doesnotexist").is_dir()
           False"""
      return os.path.isdir(self)

   def is_relative_to(self, other):
      """e.g.:

           >>> Path("/a/b").is_relative_to("/a")
           True
           >>> Path("/a/b/").is_relative_to("/a")
           True
           >>> Path("/a/b").is_relative_to("/c")
           False
           >>> Path("/a/b").is_relative_to("c")
           False"""
      try:
         self.relative_to(other)
         return True
      except ValueError:
         return False

   def match(self, pattern):
      """e.g.:

         >>> a = Path("/foo/bar.txt")
         >>> a.match("*.txt")
         True
         >>> a.match("*.TXT")
         False"""
      return fnmatch.fnmatchcase(self.__fspath__(), pattern)

   def mkdir(self):
      ch.TRACE("ensuring directory: %s" % self)
      if (self.is_dir()):
         return  # target exists and is a directory, do nothing
      try:
         os.mkdir(self)
      except FileExistsError as x:
         ch.FATAL("can’t mkdir: exists and not a directory: %s" % x.filename)
      except OSError as x:
         ch.FATAL("can’t mkdir: %s: %s" % (x.filename, x.strerror))

   def open(self, mode, *args, **kwargs):
      return ch.ossafe(open, "can’t open for %s: %s" % (mode, self),
                       self, mode, *args, **kwargs)

   def relative_to(self, other):
      """e.g. absolute paths:

           >>> a = Path("/a/b")
           >>> a.relative_to(Path("/"))
           Path('a/b')
           >>> a.relative_to("/a")
           Path('b')
           >>> Path("/a/b/").relative_to("/a")
           Path('b/')

         e.g. relative paths:

           >>> a = Path("a/b")
           >>> a.relative_to("a")
           Path('b')

         e.g. problems:

           >>> Path("/a/b").relative_to("a")
           Traceback (most recent call last):
             ...
           ValueError: Can't mix absolute and relative paths
           >>> Path("/a/b").relative_to("/c")
           Traceback (most recent call last):
             ...
           ValueError: /a/b not a subpath of /c

      """
      if (isinstance(other, Path)):
         other = other.untrailed.__fspath__()
      common = os.path.commonpath([self, other])
      if (common != other):
         raise ValueError("%s not a subpath of %s" % (self, other))
      return self.__class__(self.path[  len(other)
                                      + (0 if other == "/" else 1):])

   def rename(self, path_new):
      path_new = self.__class__(path_new)
      ch.ossafe(os.rename, "can’t rename: %s -> %s" % (self, path_new),
                self, path_new)
      return path_new

   def resolve(self):
      """e.g.:

         >>> import os
         >>> real = Path("/proc/%d" % os.getpid())
         >>> link = Path("/proc/self")
         >>> link.resolve() == real
         True"""
      return self.__class__(os.path.realpath(self))

   def rmdir(self):
      ch.ossafe(os.rmdir, "can’t rmdir: %s" % self, self)

   def stat(self, links):
      """e.g.:

           >>> import stat
           >>> st = Path("/proc/self").stat(False)
           >>> stat.S_ISDIR(st.st_mode)
           False
           >>> stat.S_ISLNK(st.st_mode)
           True
           >>> st = Path("/proc/self").stat(True)
           >>> stat.S_ISDIR(st.st_mode)
           True
           >>> stat.S_ISLNK(st.st_mode)
           False"""
      return ch.ossafe(os.stat, "can’t stat: %s" % self, self,
                       follow_symlinks=links)

   def symlink_to(self, target, clobber=False):
      if (clobber and self.is_file()):
         self.unlink()
      try:
         super().symlink_to(target)
      except FileExistsError:
         if (not self.is_symlink()):
            ch.FATAL("can’t symlink: source exists and isn’t a symlink: %s"
                     % self)
         if (self.readlink() != target):
            ch.FATAL("can’t symlink: %s exists; want target %s but existing is %s"
                     % (self, target, self.readlink()))
      except OSError as x:
         ch.FATAL("can’t symlink: %s -> %s: %s" % (name, target, x.strerror))

   def unlink(self, missing_ok=False):
      if (missing_ok and not self.exists()):
         return
      ch.ossafe(os.unlink, "can’t unlink: %s" % self, self)

   def with_name(self, name_new):
      """e.g.:

           >>> Path("a").with_name("b")
           Path('b')
           >>> Path("a/b").with_name("c")
           Path('a/c')
           >>> Path(".").with_name("a")
           Path('a')

         Not available for “/” because this would change an absolute path to
         relative, and that seems too surprising:

           >>> Path("/").with_name("a")
           Traceback (most recent call last):
             ...
           ValueError: with_name() invalid for /"""
      if (self.root_p):
         raise ValueError("with_name() invalid for /")
      return self.parent // name_new

   ## Extensions ##

   def __floordiv__(self, right):
      left = self.path
      try:
         right = right.__fspath__()
      except AttributeError:
         pass  # assume right is a string
      return self.__class__(left + "/" + right)

   def __len__(self):
      """The length of a Path is the number of components, including the root
         directory. “.” has zero components.

           >>> len(Path("a"))
           1
           >>> len(Path("/"))
           1
           >>> len(Path("/a"))
           2
           >>> len(Path("a/b"))
           2
           >>> len(Path("/a/b"))
           3
           >>> len(Path("/a/"))
           2
           >>> len(Path("."))
           0"""
      return len(self.parts)

   def __rfloordiv__(self, left):
      return self.__class__(left).__floordiv__(self)

   @property
   def empty_p(self):
      return (self.path == ".")

   @property
   def git_compatible_p(self):
      """Return True if my filename can be stored in Git, false otherwise.

         >>> Path("/gitignore").git_compatible_p
         True
         >>> Path("/.gitignore").git_compatible_p
         False"""
      return (not self.name.startswith(".git"))

   @property
   def git_escaped(self):
      """Return a copy of me escaped for Git storage, possibly unchanged.

         >>> Path("/gitignore").git_escaped
         Path('/gitignore')
         >>> Path("/.gitignore").git_escaped
         Path('/.weirdal_ignore')
         >>> Path("/.gitignore/").git_escaped
         Path('/.weirdal_ignore/')

      """
      ret = self.with_name(self.name.replace(".git", ".weirdal_"))
      if (self.trailed_p):
         ret.path += "/"
      return ret

   @property
   def root_p(self):
      return (self.path == "/")

   @property
   def first(self):
      """Return my first component as a new Path object, e.g.:

           >>> a = Path("/")
           >>> b = a.first
           >>> b
           Path('/')
           >>> a == b
           True
           >>> a is b
           False
           >>> Path("").first
           Path('.')
           >>> Path("./a").first
           Path('a')
           >>> Path("a/b").first
           Path('a')"""
      if (self.root_p):
         return self.deepcopy()
      return self.__class__(self.path.partition("/")[0])

   @property
   def trailed_p(self):
      """e.g.:

           >>> Path("a").trailed_p
           False
           >>> Path("a/").trailed_p
           True
           >>> Path("/").trailed_p
           False
           >>> (Path("a") // "b").trailed_p
           False
           >>> (Path("a/") // "b").trailed_p
           False
           >>> (Path("a") // "b/").trailed_p
           True
           >>> (Path("a") // "/").trailed_p
           True"""
      return (self.path != "/" and self.path[-1] == "/")

   @property
   def untrailed(self):
      """Return self with trailing slash removed (if any). E.g.:

         >>> Path("a").untrailed
         Path('a')
         >>> Path("a/").untrailed
         Path('a')
         >>> Path("/").untrailed
         Path('/')
         >>> Path(".").untrailed
         Path('.')"""
      if (self.root_p):
         return self.deepcopy()
      else:
         return self.__class__(self.path.rstrip("/"))

   @staticmethod
   def stat_bytes_all(paths):
      "Return concatenation of metadata_bytes() on each given Path object."
      md = bytearray()
      for path in paths:
         md += path.stat_bytes_recursive()
      return md

   def chdir(self):
      "Change CWD to path and return previous CWD. Exit on error."
      old = ch.ossafe(os.getcwd, "can’t getcwd(2)")
      ch.ossafe(os.chdir, "can’t chdir(2): %s" % self, self)
      return self.__class__(old)

   def chmod_min(self, st=None):
      """Set my permissions to at least 0o700 for directories and 0o400
         otherwise. If given, st is a stat object for self, to avoid another
         stat(2) call. Return the new file mode (permissions and file type).

         For symlinks, do nothing, because we don’t want to follow symlinks
         and follow_symlinks=False (or os.lchmod) is not supported on some
         (all?) Linux. (Also, symlink permissions are ignored on Linux, so it
         doesn’t matter anyway.)"""
      if (st is None):
         st = self.stat(False)
      if (stat.S_ISLNK(st.st_mode)):
         return st.st_mode
      perms_old = stat.S_IMODE(st.st_mode)
      perms_new = perms_old | (0o700 if stat.S_ISDIR(st.st_mode) else 0o400)
      if (perms_new != perms_old):
         ch.VERBOSE("fixing permissions: %s: %03o -> %03o"
                 % (self, perms_old, perms_new))
         ch.ossafe(os.chmod, "can’t chmod: %s" % self, self, perms_new)
      return (st.st_mode | perms_new)

   def copy(self, dst):
      """Copy file myself to dst, including metadata, overwriting dst if it
         exists. dst must be the actual destination path, i.e., it may not be
         a directory. Does not follow symlinks.

         If (a) src is a regular file, (b) src and dst are on the same
         filesystem, and (c) Python is version ≥3.8, then use
         os.copy_file_range() [1,2], which at a minimum does an in-kernel data
         transfer. If that filesystem also (d) supports copy-on-write [3],
         then this is a very fast lazy reflink copy.

         [1]: https://docs.python.org/3/library/os.html#os.copy_file_range
         [2]: https://man7.org/linux/man-pages/man2/copy_file_range.2.html
         [3]: https://elixir.bootlin.com/linux/latest/A/ident/remap_file_range
      """
      src_st = self.stat(False)
      # dst is not a directory, so parent must be on the same filesystem. We
      # *do* want to follow symlinks on the parent.
      dst_dev = dst.parent.stat(True).st_dev
      if (    stat.S_ISREG(src_st.st_mode)
          and src_st.st_dev == dst_dev
          and hasattr(os, "copy_file_range")):
         # Fast path. The same-filesystem restriction is because reliable
         # copy_file_range(2) between filesystems seems quite new (maybe
         # kernel 5.18?).
         try:
            if (dst.exists()):
               # If dst is a symlink, we get OLOOP from os.open(). Delete it
               # unconditionally though, for simplicity.
               dst.unlink()
            src_fd = os.open(self, os.O_RDONLY|os.O_NOFOLLOW)
            dst_fd = os.open(dst, os.O_WRONLY|os.O_NOFOLLOW|os.O_CREAT)
            # I’m not sure why we need to loop this -- there’s no explanation
            # of *when* fewer bytes than requested would be copied -- but the
            # man page example does.
            remaining = src_st.st_size
            while (remaining > 0):
               copied = os.copy_file_range(src_fd, dst_fd, remaining)
               if (copied == 0):
                  ch.FATAL("zero bytes copied: %s -> %s" % (self, dst))
               remaining -= copied
            os.close(src_fd)
            os.close(dst_fd)
         except OSError as x:
            ch.FATAL("can’t copy data (fast): %s -> %s: %s"
                     % (self, dst, x.strerror))
      else:
         # Slow path.
         try:
            shutil.copyfile(self, dst, follow_symlinks=False)
         except OSError as x:
            ch.FATAL("can’t copy data (slow): %s -> %s: %s"
                     % (self, dst, x.strerror))
      try:
         # Metadata.
         shutil.copystat(self, dst, follow_symlinks=False)
      except OSError as x:
         ch.FATAL("can’t copy metadata: %s -> %s" % (self, dst, x.strerror))

   def copytree(self, *args, **kwargs):
      "Wrapper for shutil.copytree() that exits on the first error."
      shutil.copytree(self, copy_function=copy, *args, **kwargs)

   def deepcopy(self):
      """Return a copy of myself. E.g.:

           >>> a = Path("a")
           >>> b = a.deepcopy()
           >>> b
           Path('a')
           >>> a == b
           True
           >>> a is b
           False"""
      return self.__class__(self.path)

   def disk_bytes(self):
      """Return the number of disk bytes consumed by path. Note this is
         probably different from the file size."""
      return self.stat().st_blocks * 512

   def du(self):
      """Return a tuple (number of files, total bytes on disk) for everything
         under path. Warning: double-counts files with multiple hard links and
         any shared data extents."""
      file_ct = 1
      byte_ct = self.disk_bytes()
      for (dir_, subdirs, files) in ch.walk(self):
         file_ct += len(subdirs) + len(files)
         byte_ct += sum((self.__class__(dir_) // i).disk_bytes()
                        for i in subdirs + files)
      return (file_ct, byte_ct)

   def file_ensure_exists(self):
      """If the final element of path exists (without dereferencing if it’s a
         symlink), do nothing; otherwise, create it as an empty regular file."""
      if (not os.path.lexists(self)):
         fp = self.open("w")
         ch.close_(fp)

   def file_gzip(self, args=[]):
      """Run pigz(1) if it’s available, otherwise gzip(1), on file at path and
         return the file’s new name. Pass args to the gzip executable. This
         lets us gzip files (a) in parallel if pigz(1) is installed and
         (b) without reading them into memory."""
      path_c = self.suffix_add(".gz")
      # On first call, remember first available of pigz and gzip using class
      # attribute 'gzip'.
      self.__class__.gzip_set()
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
      fp = path_c.open("r+b")
      ch.ossafe(fp.seek, "can’t seek: %s" % fp, 4)
      ch.ossafe(fp.write, "can’t write: %s" % fp, b'\x00\x00\x00\x00')
      ch.close_(fp)
      return path_c

   def file_hash(self):
      """Return the hash of data in file at path, as a hex string with no
         algorithm tag. File is read in chunks and can be larger than memory.

           >>> Path("/dev/null").file_hash()
           'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
      """
      fp = self.open("rb")
      h = hashlib.sha256()
      while True:
         data = ch.ossafe(fp.read, "can’t read: %s" % self, 2**18)
         if (len(data) == 0):  # EOF
            break
         h.update(data)
      ch.close_(fp)
      return h.hexdigest()

   def file_read_all(self, text=True):
      """Return the contents of file at path, or exit with error. If text,
         read in “rt” mode with UTF-8 encoding; otherwise, read in mode “rb”.

           >>> Path("/dev/null").file_read_all()
           ''
           >>> Path("/dev/null").file_read_all(False)
           b''"""
      if (text):
         mode = "rt"
         encoding = "UTF-8"
      else:
         mode = "rb"
         encoding = None
      fp = self.open(mode, encoding=encoding)
      data = ch.ossafe(fp.read, "can’t read: %s" % self)
      ch.close_(fp)
      return data

   def file_size(self, follow_symlinks=False):
      """Return the size of file at path in bytes.

           >>> Path("/dev/null").file_size()
           0"""
      return self.stat(follow_symlinks).st_size

   def file_write(self, content):
      """e.g.:

           >>> Path("/dev/null").file_write("Weird Al Yankovic")
      """
      if (isinstance(content, str)):
         content = content.encode("UTF-8")
      fp = self.open("wb")
      ch.ossafe(fp.write, "can’t write: %s" % self, content)
      ch.close_(fp)

   def grep_p(self, rx):
      """Return True if file at path contains a line matching regular
         expression rx, False if it does not.

           >>> Path("/dev/null").grep_p(r"foo")
           False"""
      try:
         with open(self, "rt") as fp:
            for line in fp:
               if (re.search(rx, line) is not None):
                  return True
         return False
      except OSError as x:
         ch.FATAL("can’t read %s: %s" % (self, x.strerror))

   def json_from_file(self, msg):
      ch.DEBUG("loading JSON: %s: %s" % (msg, self))
      text = self.file_read_all()
      ch.TRACE("text:\n%s" % text)
      try:
         data = json.loads(text)
         ch.DEBUG("result:\n%s" % pprint.pformat(data, indent=2))
      except json.JSONDecodeError as x:
         ch.FATAL("can’t parse JSON: %s:%d: %s" % (self, x.lineno, x.msg))
      return data

   def listdir(self):
      """Return set of entries in directory path, as strings, without self (.)
         and parent (..). We considered changing this to use os.scandir() for
         #992, but decided that the advantages it offered didn’t warrant the
         effort required to make the change.

           >>> sorted(Path("/dev/fd").listdir())
           ['0', '1', '2', '3']"""
      return set(ch.ossafe(os.listdir, "can’t list: %s" % self, self))

   def mkdirs(self, exist_ok=True):
      "Like “mkdir -p”."
      ch.TRACE("ensuring directory and parents: %s" % self)
      try:
         os.makedirs(self, exist_ok=exist_ok)
      except OSError as x:
         # x.filename might be an intermediate directory
         ch.FATAL("can’t mkdir: %s: %s: %s" % (self, x.filename, x.strerror))

   def mountpoint(self):
      """Return the mount point of the filesystem containing, or, if symlink,
         the file pointed to. E.g.:

            >>> Path("/proc").mountpoint()
            Path('/proc')
            >>> Path("/proc/self").mountpoint()
            Path('/proc')
            >>> Path("/").mountpoint()
            Path('/')"""
      # https://stackoverflow.com/a/4453715
      try:
         pc = self.resolve()
      except RuntimeError:
         ch.FATAL("not found, can’t resolve: %s" % self)
      dev_child = pc.stat(False).st_dev
      while (not pc.root_p):
         dev_parent = pc.parent.stat(False).st_dev
         if (dev_child != dev_parent):
            return pc
         pc = pc.parent
      # Got all the way up to root without finding a transition, so we’re on
      # the root filesystem.
      return self.__class__("/")

   def rmtree(self):
      ch.TRACE("deleting directory: %s" % self)
      try:
         shutil.rmtree(self)
      except OSError as x:
         ch.FATAL("can’t recursively delete directory %s: %s: %s"
                  % (self, x.filename, x.strerror))

   def setxattr(self, name, value, follow_symlinks=True):
      if (ch.save_xattrs):
         try:
            os.setxattr(self, name, value, follow_symlinks)
         except OSError as x:
            if (x.errno == errno.ENOTSUP):  # no OSError subclass
               ch.WARNING("xattrs not supported on %s, setting --no-xattr"
                          % self.mountpoint())
               ch.save_xattrs = False
            else:
               ch.FATAL("can’t set xattr: %s: %s: %s"
                        % (self, name, x.strerror))
      if (not ch.save_xattrs):  # not “else” because maybe changed in “if”
         ch.DEBUG("xattrs disabled, ignoring: %s: %s" % (self, name))
         return

   def stat_bytes(self, links):
      "Return self.stat() encoded as an opaque bytearray."
      st = self.stat(links)
      return (  self.path.encode("UTF-8")
              + struct.pack("=HQQ", st.st_mode, st.st_size, st.st_mtime_ns))

   def stat_bytes_recursive(self):
      """Return concatenation of self.stat() and all my children as an opaque
         bytearray, in unspecified but consistent order. Follow symlinks in
         self but not its descendants."""
      # FIXME: Locale issues related to sorting?
      md = self.stat_bytes(True)
      if (self.is_dir()):
         for (dir_, dirs, files) in ch.walk(self):
            md += dir_.stat_bytes(False)
            for f in sorted(files):
               md += (dir_ // f).stat_bytes(False)
            dirs.sort()
      return md

   def strip(self, left=0, right=0):
      """Return a copy of self with n leading components removed. E.g.:

           >>> a = Path("/a/b/c")
           >>> a.strip(left=1)
           Path('a/b/c')
           >>> a.strip(right=1)
           Path('/a/b')
           >>> a.strip(left=1, right=1)
           Path('a/b')
           >>> Path("/a/b/").strip(right=1)
           Path('/a/')

         It is an error if self doesn’t have at least left + right components,
         i.e., you can strip a path down to nothing but not further.

           >>> Path("/").strip(left=1, right=1)
           Traceback (most recent call last):
             ...
           ValueError: can't strip 2 components from a path with only 1"""
      parts = self.parts
      if (len(parts) < left + right):
         raise ValueError("can't strip %d components from a path with only %d"
                          % (left + right, len(parts)))
      ret = self.__class__(*self.parts[left:len(self.parts)-right])
      if (self.trailed_p):
         ret.path += "/"
      return ret

   def suffix_add(self, suffix):
      """Append the given suffix and return the result. Dot (“.”) is not
         special and must be specified explicitly if needed. E.g.:

           >>> Path("a").suffix_add(".txt")
           Path('a.txt')
           >>> Path("a").suffix_add("_txt")
           Path('a_txt')
           >>> Path("a/").suffix_add(".txt")
           Path('a.txt/')"""
      return self.__class__(  self.untrailed.path
                            + suffix
                            + ("/" if self.trailed_p else ""))


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
   def bucache_needs_ignore_upgrade(self):
      return self.build_cache // "ch_upgrade-ignore"

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
         across, even if it can’t be upgraded. See also #1147."""
      return (os.path.isdir(self.unpack_base) and
              os.path.isdir(self.download_cache))

   @property
   def version_file(self):
      return self.root // "version"

   @staticmethod
   def root_default():
      # FIXME: Perhaps we should use getpass.getch.user() instead of the $USER
      # environment variable? It seems a lot more robust. But, (1) we’d have
      # to match it in some scripts and (2) it makes the documentation less
      # clear becase we have to explain the fallback behavior.
      return Path("/var/tmp/%s.ch" % ch.user())

   @staticmethod
   def root_env():
      if (not "CH_IMAGE_STORAGE" in os.environ):
         return None
      path = Path(os.environ["CH_IMAGE_STORAGE"])
      if (not path.is_absolute()):
         ch.FATAL("$CH_IMAGE_STORAGE: not absolute path: %s" % path)
      return path

   def build_large_path(self, name):
      return self.build_large // name

   def cleanup(self):
      "Called during initialization after we know the storage dir is valid."
      # Delete partial downloads.
      part_ct = 0
      for path in self.download_cache.glob("part_*"):
         path = Path(path)
         ch.VERBOSE("deleting: %s" % path)
         path.unlink()
         part_ct += 1
      if (part_ct > 0):
         ch.WARNING("deleted %d partially downloaded files" % part_ct)

   def fatman_for_download(self, image_ref):
      return self.download_cache // ("%s.fat.json" % image_ref.for_path)

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
            ch.FATAL("storage directory seems invalid: %s" % self.root, hint)
         v_found = self.version_read()
      if (v_found == STORAGE_VERSION):
         ch.VERBOSE("found storage dir v%d: %s" % (STORAGE_VERSION, self.root))
         self.lock()
      elif (v_found in {None, 3, 4, 5, 6}):  # initialize/upgrade
         ch.INFO("%s storage directory: v%d %s"
                 % (op, STORAGE_VERSION, self.root))
         self.root.mkdir()
         self.lock()
         # These directories appeared in various storage versions, but since
         # the thing to do on upgrade is the same as initialize, we don’t
         # track the details.
         self.download_cache.mkdir()
         self.build_cache.mkdir()
         self.build_large.mkdir()
         self.unpack_base.mkdir()
         self.upload_cache.mkdir()
         if (v_found is not None):  # upgrade
            if (v_found < 6):
               # Git metadata moved from /.git to /ch/.git, and /.gitignore
               # went out-of-band (to info/exclude in the repository).
               for img in self.unpack_base.iterdir():
                  old = img // ".git"
                  new = img // "ch/git"
                  if (old.exists()):
                     new.parent.mkdir()
                     old.rename(new)
                     gi = img // ".gitignore"
                     if (gi.exists()):
                        gi.unlink()
               # Must also remove .gitignore from all commits. This requires
               # Git operations, which we can’t do here because the build
               # cache may be disabled. Do it in Enabled_Cache.configure().
               if (len(self.build_cache.listdir()) > 0):
                  self.bucache_needs_ignore_upgrade.file_ensure_exists()
            if (v_found == 6):
               # Charliecloud 0.32 had a bug where symlinks to fat manifests
               # that were really skinny were erroneously absolute, making the
               # storage directory immovable (PR #1657). Remove all symlinks
               # in dlcache; they’ll be re-created later.
               for entry in self.download_cache.iterdir():
                  if (entry.is_symlink()):
                     ch.DEBUG("deleting bad v6 symlink: %s" % entry)
                     entry.unlink()
         self.version_file.file_write("%d\n" % STORAGE_VERSION)
      else:                         # can’t upgrade
         ch.FATAL("incompatible storage directory v%d: %s"
                  % (v_found, self.root),
                  'you can delete and re-initialize with “ch-image reset”')
      self.validate_strict()
      self.cleanup()

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
      self.lockfile_fp = self.lockfile.open("w")
      try:
         fcntl.lockf(self.lockfile_fp, fcntl.LOCK_EX | fcntl.LOCK_NB)
      except OSError as x:
         if (x.errno in { errno.EACCES, errno.EAGAIN }):
            ch.FATAL("storage directory is already in use",
                     "concurrent instances of ch-image cannot share the same storage directory")
         else:
            ch.FATAL("can’t lock storage directory: %s" % x.strerror)

   def manifest_for_download(self, image_ref, digest):
      if (digest is None):
         digest = "skinny"
      return (   self.download_cache
              // ("%s%%%s.manifest.json" % (image_ref.for_path, digest)))

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
      # Check that all expected files exist, and no others. Note that we don’t
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
      # Ignore some files that may or may not exist.
      entries -= { i.name for i in (self.lockfile, self.mount_point) }
      # Delete some files that exist only if we crashed.
      for i in (self.image_tmp, ):
         if (i.name in entries):
            ch.WARNING("deleting leftover temporary file/dir: %s" % i.name)
            i.rmtree()
            entries.remove(i.name)
      # If anything is left, yell about it.
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
   # It’s here because the standard library class has problems with symlinks
   # and replacing one file type with another; see issues #819 and #825 as
   # well as multiple unfixed Python bugs [e.g. 3,4,5]. We work around this
   # with manual deletions.
   #
   # [1]: https://docs.python.org/3/library/tarfile.html
   # [2]: https://github.com/python/cpython/blob/2bcd0fe7a5d1a3c3dd99e7e067239a514a780402/Lib/tarfile.py#L2159
   # [3]: https://bugs.python.org/issue35483
   # [4]: https://bugs.python.org/issue19974
   # [5]: https://bugs.python.org/issue23228

   # Need new method name because add() is called recursively and we don’t
   # want those internal calls to get our special sauce.
   def add_(self, name, **kwargs):
      def filter_(ti):
         assert (ti.name == "." or ti.name[:2] == "./")
         if (ti.name in ("./ch/git", "./ch/git.pickle")):
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
         ch.FATAL("can’t lstat: %s" % targetpath, targetpath)
      if (st is not None):
         if (stat.S_ISREG(st.st_mode)):
            if (regulars):
               Path(targetpath).unlink()
         elif (stat.S_ISLNK(st.st_mode)):
            if (symlinks):
               Path(targetpath).unlink()
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
      assert (ti.name[0] != "/")  # absolute paths unsafe but shouldn’t happen
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
