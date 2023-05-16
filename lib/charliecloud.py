import argparse
import atexit
import collections
import collections.abc
import cProfile
import datetime
import enum
import hashlib
import io
import os
import platform
import pstats
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
import traceback


# List of dependency problems. This variable needs to be created before we
# import any other Charliecloud stuff to avoid #806.
depfails = []


import filesystem as fs
import registry as rg
import version


## Enums ##

# Build cache mode.
class Build_Mode(enum.Enum):
   ENABLED = "enabled"
   DISABLED = "disabled"
   REBUILD = "rebuild"

# Download cache mode.
class Download_Mode(enum.Enum):
   ENABLED = "enabled"
   WRITE_ONLY = "write-only"


## Constants ##

# Architectures. This maps the “machine” field returned by uname(2), also
# available as "uname -m" and platform.machine(), into architecture names that
# image registries use. It is incomplete (see e.g. [1], which is itself
# incomplete) but hopefully includes most architectures encountered in
# practice [e.g. 2]. Registry architecture and variant are separated by a
# slash. Note it is *not* 1-to-1: multiple uname(2) architectures map to the
# same registry architecture.
#
# [1]: https://stackoverflow.com/a/45125525
# [2]: https://github.com/docker-library/bashbrew/blob/v0.1.0/vendor/github.com/docker-library/go-dockerlibrary/architecture/oci-platform.go
ARCH_MAP = { "x86_64":    "amd64",
             "armv5l":    "arm/v5",
             "armv6l":    "arm/v6",
             "aarch32":   "arm/v7",
             "armv7l":    "arm/v7",
             "aarch64":   "arm64/v8",
             "armv8l":    "arm64/v8",
             "i386":      "386",
             "i686":      "386",
             "mips64le":  "mips64le",
             "ppc64le":   "ppc64le",
             "s390x":     "s390x" }  # a.k.a. IBM Z

# Some images have oddly specified architecture. For example, as of
# 2022-06-08, on Docker Hub, opensuse/leap:15.1 offers architectures amd64,
# arm/v7, arm64/v8, and ppc64le, while opensuse/leap:15.2 offers amd64, arm,
# arm64, and ppc64le, i.e., with no variants. This maps architectures to a
# sequence of fallback architectures that we hope are equivalent. See class
# Arch_Dict below.
ARCH_MAP_FALLBACK = { "arm/v7": ("arm",),
                      "arm64/v8": ("arm64",) }

# String to use as hint when we throw an error that suggests a bug.
BUG_REPORT_PLZ = "please report this bug: https://github.com/hpc/charliecloud/issues"

# Maximum filename (path component) length, in *characters*. All Linux
# filesystems of note that I could identify support at least 255 *bytes*. The
# problem is filenames with multi-byte characters: you cannot simply truncate
# byte-wise because you might do so in the middle of a character. So this is a
# somewhat random guess with hopefully enough headroom not to cause problems.
FILENAME_MAX_CHARS = 192

# Chunk size in bytes when streaming HTTP. Progress meter is updated once per
# chunk, which means the display is updated roughly every 20s at 100 Kbit/s
# and every 2s at 1Mbit/s; beyond that, the once-per-second display throttling
# takes over.
HTTP_CHUNK_SIZE = 256 * 1024

# Minimum Python version. NOTE: Keep in sync with configure.ac.
PYTHON_MIN = (3,6)


## Globals ##

# Compatibility link. Sometimes we load pickled data from when Path was
# defined in this file. This alias lets us still load such pickles.
Path = fs.Path

# Active architecture (both using registry vocabulary)
arch = None       # requested by user
arch_host = None  # of host

# FIXME: currently set in ch-image :P
CH_BIN = None
CH_RUN = None

# Logging; set using init() below.
verbose = 0          # Verbosity level.
log_festoon = False  # If true, prepend pid and timestamp to chatter.
log_fp = sys.stderr  # File object to print logs to.
trace_fatal = False  # Add abbreviated traceback to fatal error hint.

# True if the download cache is enabled.
dlcache_p = None

# Profiling.
profiling = False
profile = None


## Exceptions ##

class Fatal_Error(Exception):
   def __init__(self, *args, **kwargs):
      self.args = args
      self.kwargs = kwargs
class No_Fatman_Error(Exception): pass
class Image_Unavailable_Error(Exception): pass


## Classes ##

class Arch_Dict(collections.UserDict):
   """Dictionary that overloads subscript and “in” to consider
      ARCH_MAP_FALLBACK."""

   def __contains__(self, k):  # “in” operator
      if (k in self.data):
         return True
      try:
         return self._fallback_key(k) in self.data
      except KeyError:
         return False

   def __getitem__(self, k):
      try:
         return self.data.__getitem__(k)
      except KeyError:
         return self.data.__getitem__(self._fallback_key(k))

   def _fallback_key(self, k):
      """Return fallback key corresponding to key k, or raise KeyError if
         there is no fallback."""
      assert (k not in self.data)
      if (k not in ARCH_MAP_FALLBACK):
         raise KeyError("no fallbacks: %s" % k)
      for f in ARCH_MAP_FALLBACK[k]:
         if (f in self.data):
            return f
      raise KeyError("fallbacks also missing: %s" % k)

   def in_warn(self, k):
      """Return True if k in self, False otherwise, just like the “in“
         operator, but also log a warning if fallback is used."""
      result = k in self
      if (result and k not in self.data):
         WARNING("arch %s requested but falling back to %s" %
                 (k, self._fallback_key(k)))
      return result


class ArgumentParser(argparse.ArgumentParser):

   class HelpFormatter(argparse.HelpFormatter):

      # Suppress duplicate metavar printing when option has both short and
      # long flavors. E.g., instead of:
      #
      #   -s DIR, --storage DIR  set builder internal storage directory to DIR
      #
      # print:
      #
      #   -s, --storage DIR      set builder internal storage directory to DIR
      #
      # From https://stackoverflow.com/a/31124505.
      def _format_action_invocation(self, action):
         if (not action.option_strings or action.nargs == 0):
            return super()._format_action_invocation(action)
         default = self._get_default_metavar_for_optional(action)
         args_string = self._format_args(action, default)
         return ', '.join(action.option_strings) + ' ' + args_string

   def __init__(self, sub_title=None, sub_metavar=None, *args, **kwargs):
      super().__init__(formatter_class=self.HelpFormatter, *args, **kwargs)
      self._optionals.title = "options"  # https://stackoverflow.com/a/16981688
      if (sub_title is not None):
         self.subs = self.add_subparsers(title=sub_title, metavar=sub_metavar)

   def add_parser(self, title, desc, *args, **kwargs):
      return self.subs.add_parser(title, help=desc, description=desc,
                                  *args, **kwargs)

   def parse_args(self, *args, **kwargs):
      cli = super().parse_args(*args, **kwargs)
      # Bring in environment variables that set options.
      if (cli.bucache is None and "CH_IMAGE_CACHE" in os.environ):
         try:
            cli.bucache = Build_Mode(os.environ["CH_IMAGE_CACHE"])
         except ValueError:
            FATAL("$CH_IMAGE_CACHE: invalid build cache mode: %s"
                  % os.environ["CH_IMAGE_CACHE"])
      return cli


class OrderedSet(collections.abc.MutableSet):

   # Note: The superclass provides basic implementations of all the other
   # methods. I didn’t evaluate any of these.

   __slots__ = ("data",)

   def __init__(self, others=None):
      self.data = collections.OrderedDict()
      if (others is not None):
         self.data.update((i, None) for i in others)

   def __contains__(self, item):
      return (item in self.data)

   def __iter__(self):
      return iter(self.data.keys())

   def __len__(self):
      return len(self.data)

   def __repr__(self):
      return "%s(%s)" % (self.__class__.__name__, list(iter(self)))

   def add(self, x):
      self.data[x] = None

   def clear(self):
      # Superclass provides an implementation but warns it’s slow (and it is).
      self.data.clear()

   def discard(self, x):
      self.data.pop(x, None)


class Progress:
   """Simple progress meter for countable things that updates at most once per
      second. Writes first update upon creation. If length is None, then just
      count up (this is for registries like Red Hat that sometimes don’t
      provide a Content-Length header for blobs).

      The purpose of the divisor is to allow counting things that are much
      more numerous than what we want to display; for example, to count bytes
      but report MiB, use a divisor of 1048576.

      By default, moves to a new line at first update, then assumes exclusive
      control of this line in the terminal, rewriting the line as needed. If
      output is not a TTY or global log_festoon is set, each update is one log
      entry with no overwriting."""

   __slots__ = ("display_last",
                "divisor",
                "msg",
                "length",
                "unit",
                "overwrite_p",
                "precision",
                "progress")

   def __init__(self, msg, unit, divisor, length):
      self.msg = msg
      self.unit = unit
      self.divisor = divisor
      self.length = length
      if (not os.isatty(log_fp.fileno()) or log_festoon):
         self.overwrite_p = False  # updates all use same line
      else:
         self.overwrite_p = True   # each update on new line
      self.precision = 1 if self.divisor >= 1000 else 0
      self.progress = 0
      self.display_last = float("-inf")
      self.update(0)

   def update(self, increment, last=False):
      now = time.monotonic()
      self.progress += increment
      if (last or now - self.display_last > 1):
         if (self.length is None):
            line = ("%s: %.*f %s"
                    % (self.msg,
                       self.precision, self.progress / self.divisor,
                       self.unit))
         else:
            ct = "%.*f/%.*f" % (self.precision, self.progress / self.divisor,
                                self.precision, self.length / self.divisor)
            pct = "%d%%" % (100 * self.progress / self.length)
            if (ct == "0.0/0.0"):
               # too small, don’t print count
               line = "%s: %s" % (self.msg, pct)
            else:
               line = ("%s: %s %s (%s)" % (self.msg, ct, self.unit, pct))
         INFO(line, end=("\r" if self.overwrite_p else "\n"))
         self.display_last = now

   def done(self):
      self.update(0, True)
      if (self.overwrite_p):
         INFO("")  # newline to release display line


class Progress_Reader:
   """Wrapper around a binary file object to maintain a progress meter while
      reading."""

   __slots__ = ("fp",
                "msg",
                "progress")

   def __init__(self, fp, msg):
      self.fp = fp
      self.msg = msg
      self.progress = None

   def __iter__(self):
      return self

   def __next__(self):
      data = self.read(HTTP_CHUNK_SIZE)
      if (len(data) == 0):
         raise StopIteration
      return data

   def close(self):
      if (self.progress is not None):
         self.progress.done()
         close_(self.fp)

   def read(self, size=-1):
     data = ossafe(self.fp.read, "can’t read: %s" % self.fp.name, size)
     self.progress.update(len(data))
     return data

   def seek(self, *args):
      raise io.UnsupportedOperation

   def start(self):
      # Get file size. This seems awkward, but I wasn’t able to find anything
      # better. See: https://stackoverflow.com/questions/283707
      old_pos = self.fp.tell()
      assert (old_pos == 0)  # math will be wrong if this isn’t true
      length = self.fp.seek(0, os.SEEK_END)
      self.fp.seek(old_pos)
      self.progress = Progress(self.msg, "MiB", 2**20, length)


class Progress_Writer:
   """Wrapper around a binary file object to maintain a progress meter while
      data are written."""

   __slots__ = ("fp",
                "msg",
                "path",
                "progress")

   def __init__(self, path, msg):
      self.msg = msg
      self.path = path
      self.progress = None

   def close(self):
      if (self.progress is not None):
         self.progress.done()
         close_(self.fp)

   def start(self, length):
      self.progress = Progress(self.msg, "MiB", 2**20, length)
      self.fp = self.path.open_("wb")

   def write(self, data):
      self.progress.update(len(data))
      ossafe(self.fp.write, "can’t write: %s" % self.path, data)


class Timer:

   __slots__ = ("start")

   def __init__(self):
      self.start = time.time()

   def log(self, msg):
      VERBOSE("%s in %.3fs" % (msg, time.time() - self.start))


## Supporting functions ##

def DEBUG(msg, hint=None, **kwargs):
   #if (verbose >= 2):
   #   log(msg, hint, None, "38;5;6m", "", **kwargs)  # dark cyan (same as 36m)
   log(msg, hint, None, "38;5;6m", "", **kwargs)  # dark cyan (same as 36m)

def ERROR(msg, hint=None, trace=None, **kwargs):
   #if (log_quiet < 2):
   #   log(msg, hint, trace, "1;31m", "error: ", **kwargs)  # bold red
   log(msg, hint, trace, "1;31m", "error: ", **kwargs)  # bold red

def FATAL(msg, hint=None, **kwargs):
   if (trace_fatal):
      # One-line traceback, skipping top entry (which is always bootstrap code
      # calling ch-image.main()) and last entry (this function).
      tr = ", ".join("%s:%d:%s" % (os.path.basename(f.filename),
                                   f.lineno, f.name)
                     for f in reversed(traceback.extract_stack()[1:-1]))
   else:
      tr = None
   raise Fatal_Error(msg, hint, tr, **kwargs)

def INFO(msg, hint=None, **kwargs):
   "Note: Use print() for output; this function is for logging."
   #if (log_quiet == 0):
   #   log(msg, hint, None, "33m", "", **kwargs)  # yellow
   log(msg, hint, None, "33m", "", **kwargs)  # yellow

def TRACE(msg, hint=None, **kwargs):
   if (verbose >= 3):
      log(msg, hint, None, "38;5;6m", "", **kwargs)  # dark cyan (same as 36m)

def VERBOSE(msg, hint=None, **kwargs):
   #if ((verbose >= 1) and (log_quiet == 0)):
   if (verbose >= 1):
      log(msg, hint, None, "38;5;14m", "", **kwargs)  # light cyan (1;36m, not bold)

def WARNING(msg, hint=None, **kwargs):
   #if (log_quiet < 2):
   #   log(msg, hint, None, "31m", "warning: ", **kwargs)  # red
   log(msg, hint, None, "31m", "warning: ", **kwargs)  # red

def arch_host_get():
   "Return the registry architecture of the host."
   arch_uname = platform.machine()
   VERBOSE("host architecture from uname: %s" % arch_uname)
   try:
      arch_registry = ARCH_MAP[arch_uname]
   except KeyError:
      FATAL("unknown host architecture: %s" % arch_uname, BUG_REPORT_PLZ)
   VERBOSE("host architecture for registry: %s" % arch_registry)
   return arch_registry

def argv_to_string(argv):
   return " ".join(shlex.quote(i).replace("\n", "\\n") for i in argv)

def bytes_hash(data):
   "Return the hash of data, as a hex string with no leading algorithm tag."
   h = hashlib.sha256()
   h.update(data)
   return h.hexdigest()

def ch_run_modify(img, args, env, workdir="/", binds=[], ch_run_args=[],
                  fail_ok=False):
   # Note: If you update these arguments, update the ch-image(1) man page too.
   args = (  [CH_BIN + "/ch-run"]
           + ch_run_args
           + ["-w", "-u0", "-g0", "--no-passwd", "--cd", workdir, "--unsafe"]
           + sum([["-b", i] for i in binds], [])
           + [img, "--"] + args)
   return cmd(args, env=env, stderr=None, fail_ok=fail_ok)

def close_(fp):
   try:
      path = fp.name
   except AttributeError:
      path = "(no path)"
   ossafe(fp.close, "can’t close: %s" % path)

def cmd(argv, fail_ok=False, **kwargs):
   """Run command using cmd_base(). If fail_ok, return the exit code whether
      or not the process succeeded; otherwise, return (zero) only if the
      process succeeded and exit with fatal error if it failed."""
   cp = cmd_base(argv, fail_ok=fail_ok, **kwargs)
   return cp.returncode

def cmd_base(argv, fail_ok=False, **kwargs):
   """Run a command to completion. If not fail_ok, exit with a fatal error if
      the command fails (i.e., doesn’t exit with code zero). Return the
      CompletedProcess object.

      The command’s stderr is suppressed unless (1) logging is DEBUG or higher
      or (2) fail_ok is False and the command fails."""
   argv = [str(i) for i in argv]
   VERBOSE("executing: %s" % argv_to_string(argv))
   if ("env" in kwargs):
      VERBOSE("environment: %s" % kwargs["env"])
   if ("stderr" not in kwargs):
      if (verbose <= 1):  # VERBOSE or lower: capture for printing on fail only
         kwargs["stderr"] = subprocess.PIPE
   if ("input" not in kwargs):
      kwargs["stdin"] = subprocess.DEVNULL
   if (log_quiet > 0):
      kwargs["stdout"] = subprocess.DEVNULL
      kwargs["stderr"] = subprocess.DEVNULL
   try:
      profile_stop()
      cp = subprocess.run(argv, **kwargs)
      profile_start()
   except OSError as x:
      VERBOSE("can’t execute %s: %s" % (argv[0], x.strerror))
      # Most common reason we are here is that the command isn’t found, which
      # generates a FileNotFoundError. Use fake return value 127; this is
      # consistent with the shell [1]. This is a kludge, but we assume the
      # caller doesn’t care about the distinction between some problem within
      # the subprocess and inability to start the subprocess.
      #
      # [1]: https://devdocs.io/bash/exit-status#Exit-Status
      cp = subprocess.CompletedProcess(argv, 127)
   if (not fail_ok and cp.returncode != 0):
      if (cp.stderr is not None):
         if (isinstance(cp.stderr, bytes)):
            cp.stderr = cp.stderr.decode("UTF-8")
         sys.stderr.write(cp.stderr)
         sys.stderr.flush()
      FATAL("command failed with code %d: %s"
            % (cp.returncode, argv_to_string(argv)))
   return cp

def cmd_stdout(argv, encoding="UTF-8", **kwargs):
   """Run command using cmd_base(), capturing its standard output. Return the
      CompletedProcess object (its stdout is available in the “stdout”
      attribute). If logging is debug or higher, print stdout."""
   cp = cmd_base(argv, encoding=encoding, stdout=subprocess.PIPE, **kwargs)
   if (verbose >= 2):  # debug or higher
      # just dump to stdout rather than using DEBUG() to match cmd_quiet
      sys.stdout.write(cp.stdout)
      sys.stdout.flush()
   return cp

def cmd_quiet(argv, **kwargs):
   """Run command using cmd() and return the exit code. If logging is verbose
      or lower, discard stdout."""
   if (verbose >= 2):  # debug or higher
      stdout=None
   else:
      stdout=subprocess.DEVNULL
   return cmd(argv, stdout=stdout, **kwargs)

def color_reset(*fps):
   for fp in fps:
      color_set("0m", fp)

def color_set(color, fp):
   if (fp.isatty()):
      print("\033[" + color, end="", flush=True, file=fp)

def copy2(src, dst, **kwargs):
   "Wrapper for shutil.copy2() with error checking."
   ossafe(shutil.copy2, "can’t copy: %s -> %s" % (src, dst), src, dst, **kwargs)

def dependencies_check():
   """Check more dependencies. If any dependency problems found, here or above
      (e.g., lark module checked at import time), then complain and exit."""
   # enforce Python minimum version
   vsys_py = sys.version_info[:3]  # 4th element is a string
   if (vsys_py < PYTHON_MIN):
      vmin_py_str = ".".join(("%d" % i) for i in PYTHON_MIN)
      vsys_py_str = ".".join(("%d" % i) for i in vsys_py)
      depfails.append(("bad", ("need Python %s but running under %s: %s"
                               % (vmin_py_str, vsys_py_str, sys.executable))))
   # report problems & exit
   for (p, v) in depfails:
      ERROR("%s dependency: %s" % (p, v))
   if (len(depfails) > 0):
      exit(1)

def digest_trim(d):
   """Remove the algorithm tag from digest d and return the rest.

        >>> digest_trim("sha256:foobar")
        'foobar'

      Note: Does not validate the form of the rest."""
   try:
      return d.split(":", maxsplit=1)[1]
   except AttributeError:
      FATAL("not a string: %s" % repr(d))
   except IndexError:
      FATAL("no algorithm tag: %s" % d)

def done_notify():
   if (user() == "jogas"):
      INFO("!!! KOBE !!!")
   else:
      INFO("done")

def exit(code):
   profile_stop()
   profile_dump()
   sys.exit(code)

def init(cli):
   # logging
   global log_festoon, log_fp, log_quiet, trace_fatal, verbose
   log_quiet = cli.quiet
   assert (0 <= cli.verbose <= 3)
   verbose = cli.verbose
   trace_fatal = (cli.debug or bool(os.environ.get("CH_IMAGE_DEBUG", False)))
   if ((trace_fatal) and (log_quiet > 0)):
      log_quiet = 0
      trace_fatal = False
      FATAL("“debug” and “quiet” incompatible.")
   if ("CH_LOG_FESTOON" in os.environ):
      log_festoon = True
   file_ = os.getenv("CH_LOG_FILE")
   if (file_ is not None):
      verbose = max(verbose, 1)
      log_fp = file_.open_("at")
   atexit.register(color_reset, log_fp)
   VERBOSE("version: %s" % version.VERSION)
   VERBOSE("verbose level: %d" % verbose)
   # storage directory
   global storage
   storage = fs.Storage(cli.storage)
   fs.storage_lock = not cli.no_lock
   # architecture
   global arch, arch_host
   assert (cli.arch is not None)
   arch_host = arch_host_get()
   if (cli.arch == "host"):
      arch = arch_host
   else:
      arch = cli.arch
   # download cache
   if (cli.always_download):
      dlcache = Download_Mode.WRITE_ONLY
   else:
      dlcache = Download_Mode.ENABLED
   global dlcache_p
   dlcache_p = (dlcache == Download_Mode.ENABLED)
   # registry authentication
   if (cli.func.__module__ == "push"):
      rg.auth_p = True
   elif (cli.auth):
      rg.auth_p = True
   elif ("CH_IMAGE_AUTH" in os.environ):
      rg.auth_p = (os.environ["CH_IMAGE_AUTH"] == "yes")
   else:
      rg.auth_p = False
   VERBOSE("registry authentication: %s" % rg.auth_p)
   # misc
   global password_many, profiling
   password_many = cli.password_many
   profiling = cli.profile
   if (cli.tls_no_verify):
      rg.tls_verify = False
      rpu = rg.requests.packages.urllib3
      rpu.disable_warnings(rpu.exceptions.InsecureRequestWarning)

def kill_blocking(pid, timeout=10):
   """Kill process pid with SIGTERM (the friendly one) and wait for it to
      exit. If timeout (in seconds) is exceeded and it’s still running, exit
      with a fatal error. It is *not* an error if pid does not exist, to avoid
      race conditions where we decide to kill a process and it exits before we
      can send the signal."""
   sig = signal.SIGTERM
   try:
      os.kill(pid, sig)
   except ProcessLookupError:  # ESRCH, no such process
      return
   except OSError as x:
      FATAL("can’t signal PID %d with %d: %s" % (pid, sig, x.strerror))
   for i in range(timeout*2):
      try:
         os.kill(pid, 0)  # no effect on process
      except ProcessLookupError:  # done
         return
      except OSError as x:
         FATAL("can’t signal PID %s with 0: %s" % (pid, x.strerror))
      time.sleep(0.5)
   FATAL("timeout of %ds exceeded trying to kill PID %d" % (timeout, pid),
         BUG_REPORT_PLZ)

def walk(*args, **kwargs):
   """Wrapper for os.walk(). Return a generator of the files in a directory
      tree (root specified in *args). For each directory in said tree, yield a
      3-tuple (dirpath, dirnames, filenames), where dirpath is a Path object,
      and dirnames and filenames are lists of Path objects. For insight into
      these being lists rather than generators, see use of ch.walk() in
      I_copy.copy_src_dir()."""
   for (dirpath, dirnames, filenames) in os.walk(*args, **kwargs):
      yield (fs.Path(dirpath),
             [fs.Path(dirname) for dirname in dirnames],
             [fs.Path(filename) for filename in filenames])

def log(msg, hint, trace, color, prefix, end="\n"):
   if (color is not None):
      color_set(color, log_fp)
   if (log_festoon):
      ts = datetime.datetime.now().isoformat(timespec="milliseconds")
      festoon = ("%5d %s  " % (os.getpid(), ts))
   else:
      festoon = ""
   print(festoon, prefix, msg, sep="", file=log_fp, end=end, flush=True)
   if (hint is not None):
      print(festoon, "hint: ", hint, sep="", file=log_fp, flush=True)
   if (trace is not None):
      print(festoon, "trace: ", trace, sep="", file=log_fp, flush=True)
   if (color is not None):
      color_reset(log_fp)

def now_utc_iso8601():
   return datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z"

def ossafe(f, msg, *args, **kwargs):
   """Call f with args and kwargs. Catch OSError and other problems and fail
      with a nice error message."""
   try:
      return f(*args, **kwargs)
   except OSError as x:
      FATAL("%s: %s" % (msg, x.strerror))

def positive(x):
   """Convert x to float, then if ≤ 0, change to positive infinity. This is
      monstly a convenience function to let 0 express “unlimited”."""
   x = float(x)
   if (x <= 0):
      x = float("inf")
   return x

def prefix_path(prefix, path):
   """"Return True if prefix is a parent directory of path.
       Assume that prefix and path are strings."""
   return prefix == path or (prefix + '/' == path[:len(prefix) + 1])

def profile_dump():
   "If profiling, dump the profile data."
   if (profiling):
      INFO("writing profile files ...")
      fp = fs.Path("/tmp/chofile.txt").open("wt")
      ps = pstats.Stats(profile, stream=fp)
      ps.sort_stats(pstats.SortKey.CUMULATIVE)
      ps.dump_stats("/tmp/chofile.p")
      ps.print_stats()
      close_(fp)

def profile_start():
   "If profiling, start the profiler."
   global profile
   if (profiling):
      if (profile is None):
         INFO("initializing profiler")
         profile = cProfile.Profile()
      profile.enable()

def profile_stop():
   "If profiling, stop the profiler."
   if (profiling and profile is not None):
      profile.disable()

def si_binary_bytes(ct):
   # FIXME: varies between 1 and 3 significant figures
   ct = float(ct)
   for suffix in ("B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB"):
      if (ct < 1024):
         return (ct, suffix)
      ct /= 1024
   assert False, "unreachable"

def si_decimal(ct):
   ct = float(ct)
   for suffix in ("", "K", "M", "G", "T", "P", "E", "Z"):
      if (ct < 1000):
         return (ct, suffix)
      ct /= 1000
   assert False, "unreachable"

def user():
   "Return the current username; exit with error if it can’t be obtained."
   try:
      return os.environ["USER"]
   except KeyError:
      FATAL("can’t get username: $USER not set")

def variables_sub(s, variables):
   if (s is None):
      return s
   # FIXME: This should go in the grammar rather than being a regex kludge.
   #
   # Dockerfile spec does not say what to do if substituting a value that’s
   # not set. We ignore those subsitutions. This is probably wrong (the shell
   # substitutes the empty string).
   for (k, v) in variables.items():
      # FIXME: remove when issue #774 is fixed
      m = re.search(r"(?<!\\)\${.+?:[+-].+?}", s)
      if (m is not None):
         FATAL("modifiers ${foo:+bar} and ${foo:-bar} not yet supported (issue #774)")
      s = re.sub(r"(?<!\\)\${?%s}?" % k, v, s)
   return s

def version_check(argv, min_, required=True, regex=r"(\d+)\.(\d+)\.(\d+)"):
   """Return True if the version number of program exected as argv is at least
      min_. Otherwise, including if execution fails, exit with error if
      required, otherwise return False. Use regex to extract the version
      number from output."""
   if (required):
      too_old = FATAL
      bad_parse = FATAL
   else:
      too_old = VERBOSE
      bad_parse = WARNING
   prog = argv[0]
   cp = cmd_stdout(argv, fail_ok=True, stderr=subprocess.STDOUT)
   if (cp.returncode != 0):
      too_old("%s failed with exit code %d, assuming not present"
              % (prog, cp.returncode))
      return False
   m = re.search(regex, cp.stdout)
   if (m is None):
      bad_parse("can’t parse %s version, assuming not present: %s"
                % (prog, cp.stdout))
      return False
   try:
      v = tuple(int(i) for i in m.groups())
   except ValueError:
      bad_parse("can’t parse %s version part, assuming not present: %s"
                % (prog, cp.stdout))
      return False
   if (min_ > v):
      too_old("%s is too old: %d.%d.%d < %d.%d.%d" % ((prog,) + v + min_))
      return False
   VERBOSE("%s version OK: %d.%d.%d ≥ %d.%d.%d" % ((prog,) + v + min_))
   return True
