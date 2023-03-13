import os.path
import re

import charliecloud as ch
import filesystem as fs


## Globals ##

FAKEROOT_DEFAULT_CONFIGS = {

   # General notes:
   #
   # 1. Semantics of these configurations. (Character limits are to support
   #    tidy code and message formatting.)
   #
   #    a. This is a dictionary of configurations, which themselves are
   #       dictionaries.
   #
   #    b. Key is an arbitrary tag; user-visible. There’s no enforced
   #       character set but let’s stick with [a-z0-9_] for now and limit to
   #       at most 10 characters.
   #
   #    c. A configuration has the following keys.
   #
   #       name ... Human-readable name for the configuration. Max 46 chars.
   #
   #       match .. Tuple; first item is the name of a file and the second is
   #                a regular expression. If the regex matches any line in the
   #                file, that configuration is used for the image.
   #
   #       init ... List of tuples containing POSIX shell commands to perform
   #                fakeroot installation and any other initialization steps.
   #
   #                Item 1: Command to detect if the step is necessary. If the
   #                  command exits successfully, the step is already
   #                  complete; if unsuccessful, it is still needed. The sense
   #                  of the test is so something like "is command FOO
   #                  available?", which seems the most common command, does
   #                  not require negation.
   #
   #                  The test should be fairly permissive; e.g., if the image
   #                  already has a fakeroot implementation installed, but
   #                  it’s a different one than we would have chosen, the
   #                  command should succeed.
   #
   #                  IMPORTANT: This command must have no side effects,
   #                  because it is normally run in all matching images, even
   #                  if --force is not specified. Note that talking to the
   #                  internet is a side effect!
   #
   #                Item 2: Command to do the init step.
   #
   #                I.e., to perform each fakeroot initialization step,
   #                ch-image does roughly:
   #
   #                  if ( ! $CMD_1 ); then
   #                      $CMD_2
   #                  fi
   #
   #                For both commands, the output is visible to the user but
   #                is not analyzed.
   #
   #       cmds ... List of RUN command words that need fakeroot injection.
   #                Each item in the list is matched against each
   #                whitespace-separated word in the RUN instructions. For
   #                example, suppose that each is the list “dnf”, “rpm”, and
   #                “yum”; consider the following RUN instructions:
   #
   #                  RUN ['dnf', 'install', 'foo']
   #                  RUN dnf install foo
   #
   #                These are fairly standard forms. “dnf” matches both, the
   #                first on the first element in the list and the second
   #                after breaking the shell command on whitespace.
   #
   #                  RUN true&&dnf install foo
   #
   #                This third example does *not* match (false negative)
   #                because breaking on whitespace yields “true&&dnf”,
   #                “install”, and “foo”; none of these words are “dnf”.
   #
   #                  RUN echo dnf install foo
   #
   #                This final example *does* match (false positive) becaus
   #                the second word *is* “dnf”; the algorithm isn’t smart
   #                enough to realize that it’s an argument to “echo”.
   #
   #                The last two illustrate that the algorithm uses simple
   #                whitespace delimiters, not even a partial shell parser.
   #
   #       each ... List of words to prepend to RUN instructions that match
   #                cmd_each. For example, if each is ["fr", "-z"], then these
   #                instructions:
   #
   #                  RUN ['dnf', 'install', 'foo']
   #                  RUN dnf install foo
   #
   #                become:
   #
   #                   RUN ['fr', '-z', 'dnf', 'install', 'foo']
   #                   RUN ['fr', '-z', '/bin/sh', '-c', 'dnf install foo']
   #
   #                (Note that “/bin/sh -c” is how shell-form RUN instructions
   #                are executed regardless of --force.)
   #
   # 2. The first match wins. However, because dictionary ordering can’t be
   #    relied on yet, since it was introduced in Python 3.6 [1], matches
   #    should be disjoint.
   #
   #    [1]: https://docs.python.org/3/library/stdtypes.html#dict
   #
   # 3. A matching configuration is considered applicable if any of the
   #    fakeroot-able commands are present. We do nothing if the config isn’t
   #    applicable. We do not look for other matches.
   #
   # 4. There are three implementations of fakeroot that I could find:
   #    fakeroot, fakeroot-ng, and pseudo. As of 2020-09-02:
   #
   #    * fakeroot-ng and pseudo use a daemon process, while fakeroot does
   #      not. pseudo also uses a persistent database.
   #
   #    * fakeroot-ng does not support ARM; pseudo supports many architectures
   #      including ARM.
   #
   #    * “Old” fakeroot seems to have had version 1.24 on 2019-09-07 with
   #      the most recent commit 2020-08-12.
   #
   #    * fakeroot-ng is quite old: last upstream release was 0.18 in 2013,
   #      and its source code is on Sourceforge.
   #
   #    * pseudo is aslo a bit old: last upstream version was 1.9.0 on
   #      2018-01-20, and the last Git commit was 2019-08-02.
   #
   #    Generally, we select the first one that seems to work in the order
   #    fakeroot, pseudo, fakeroot-ng.
   #
   # 5. Why grep a specified file vs. simpler alternatives?
   #
   #    * Look at image name: Misses derived images, large number of names
   #      seems a maintenance headache, :latest changes.
   #
   #    * grep the same file for each distro: No standardized file for this.
   #      [FIXME: This may be wrong; see issue #1292.]
   #
   #    * Ask lsb_release(1): Not always installed, requires executing ch-run.

   # Fedora notes:
   #
   # 1. The minimum supported version was chosen somewhat arbitrarily based on
   #    versions available for testing, i.e., what was on Docker Hub.
   #
   # 2. The fakeroot package is in the base repository set so enabling EPEL is
   #    not required.
   #
   # 3. Must be before “rhel8” because that matches Fedora too.

   "fedora":
   { "name": "Fedora 24+",
     "match":  ("/etc/fedora-release", r"release (?!1?[0-9] |2[0-3] )"),
     "init": [ ("command -v fakeroot > /dev/null",
                "dnf install -y fakeroot") ],
     "cmds": ["dnf", "rpm", "yum"],
     "each": ["fakeroot"] },

   # RHEL (and rebuilds like CentOS, Alma, Springdale, Rocky) notes:
   #
   # 1. These seem to have only fakeroot, which is in EPEL, not the standard
   #    repos.
   #
   # 2. Unlike some derivatives, RHEL itself doesn’t have the epel-release rpm
   #    in the standard repos; install via rpm for both to be consistent.
   #
   # 3. Enabling EPEL can have undesirable side effects, e.g. different
   #    version of things in the base repo that breaks other things. Thus,
   #    when we are done with EPEL, we uninstall it. Existing EPEL
   #    installations are left alone. (Such breakage is an EPEL bug, but we do
   #    commonly encounter it.)
   #
   # 4. “yum repolist” has a lot of side effects, e.g. locking the RPM
   #    database and asking configured repos for something or other.

   "rhel7":
   { "name": "RHEL 7 and derivatives",
     "match": ("/etc/redhat-release", r"release 7\."),
     "init": [ ("command -v fakeroot > /dev/null",
                "set -ex; "
                "if ! grep -Eq '\[epel\]' /etc/yum.conf /etc/yum.repos.d/*; then "
                "yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm; "
                "yum install -y fakeroot; "
                "yum remove -y epel-release; "
                "else "
                "yum install -y fakeroot; "
                "fi; ") ],
     "cmds": ["dnf", "rpm", "yum"],
     "each": ["fakeroot"] },

   "rhel8":
   { "name": "RHEL 8+ and derivatives",
     "match":  ("/etc/redhat-release", r"release (?![0-7]\.)"),
     "init": [ ("command -v fakeroot > /dev/null",
                "set -ex; "
                "if ! grep -Eq '\[epel\]' /etc/yum.conf /etc/yum.repos.d/*; then "
                # Macro %rhel from *-release* RPM, e.g. redhat-release-server
                # or centos-linux-release; thus reliable.
                "dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm; "
                "dnf install -y fakeroot; "
                "dnf remove -y epel-release; "
                "else "
                "dnf install -y fakeroot; "
                "fi; ") ],
     "cmds": ["dnf", "rpm", "yum"],
     "each": ["fakeroot"] },

   # Debian/Ubuntu notes:
   #
   # 1. In recent Debian-based distributions apt(8) runs as an unprivileged
   #    user by default. This makes *all* apt operations fail in an
   #    unprivileged container because it can’t drop privileges. There are
   #    multiple ways to turn the “sandbox” off. AFAICT, none are documented,
   #    but this one at least appears in Google searches a lot.
   #
   #    apt also doesn’t drop privileges if there is no user _apt; in my
   #    testing, sometimes this user is present and sometimes not, for reasons
   #    I don’t understand. If not present, you get this warning:
   #
   #      W: No sandbox user '_apt' on the system, can not drop privileges
   #
   #    Configuring apt not to use the sandbox seemed cleaner than deleting
   #    this user and eliminates the warning.
   #
   # 2. If we wanted to test if a fakeroot package was installed, we could say:
   #
   #      dpkg-query -Wf '${Package}\n' \
   #      | egrep '^(fakeroot|fakeroot-ng|pseudo)$'

   "debderiv":
   { "name": "Debian 9+, Ubuntu 14+, or other derivative",
     "match": ("/etc/os-release", r"Debian GNU/Linux (?![0-8] )|Ubuntu (?![0-9]\.|1[0-3]\.)|ID_LIKE=debian"),
     "init": [ ("apt-config dump | fgrep -q 'APT::Sandbox::User \"root\"'"
                " || ! fgrep -q _apt /etc/passwd",
                "echo 'APT::Sandbox::User \"root\";'"
                " > /etc/apt/apt.conf.d/no-sandbox"),
                ("command -v fakeroot > /dev/null",
                 # update b/c base image ships with no package indexes
                 "apt-get update && apt-get install -y fakeroot") ],
     "cmds": ["apt", "apt-get", "dpkg"],
     "each": ["fakeroot"] },

   "suse":
   { "name": "(Open)SUSE 42.2+",  # no fakeroot before this
     # I don’t know if there are OpenSUSE derivatives
     "match": ("/etc/os-release", r"ID_LIKE=.*suse"),
     "init": [ ("command -v fakeroot > /dev/null",
                # fakeroot seems to have a missing dependency, otherwise
                # failing with missing getopt in the fakeroot script.
                "zypper refresh; zypper install -y fakeroot /usr/bin/getopt") ],
     "cmds": ["zypper", "rpm"],
     "each": ["fakeroot"] },

   # pacman doesn’t seem to have proper dependencies like dpkg and rpm. It
   # happens that fakeroot can fail because the downloaded version is linked
   # against a newer glibc (at least) than is in the base image. We could also
   # update glibc (and its dependency util-linux), but that causes the tests
   # to fail with fchownat() errors. Another possiblity is to add “-u” to
   # update all installed packages, but that may not be what a user wants.
   "arch":
   { "name": "Arch Linux",
   "match": ("/etc/os-release", r"ID=arch"),  # /etc/arch-release empty
   "init": [ ("command -v fakeroot > /dev/null",
              "pacman -Syq --noconfirm fakeroot") ],
   "cmds": ["pacman"],
   "each": ["fakeroot"] },

   "alpine":
   { "name": "Alpine, any version",
    "match": ("/etc/alpine-release", r"[0-9]\.[0-9]+\.[0-9]+"),
    "init": [ ("command -v fakeroot > /dev/null",
               "apk update; apk add fakeroot") ],
    "cmds": ["apk"],
    "each": ["fakeroot"] },
}

# Default value of --force-cmd.
#
# NOTE: apt(8) tells people not to use it in scripts, but they do it anyway.
FORCE_CMD_DEFAULT = { "apt":     ["-o", "APT::Sandbox::User=root"],
                      "apt-get": ["-o", "APT::Sandbox::User=root"] }


## Functions ###

def new(image_path, force_mode, force_cmds):
   """Return a new forcer object appropriate for image at image_path in mode
      force_mode. If no such object can be found, exit with error."""
   if (force_mode is None):
      return Nope()
   elif (force_mode == "fakeroot"):
      return Fakeroot(image_path)
   elif (force_mode == "seccomp"):
      return Seccomp(force_cmds)
   else:
      assert False, "unreachable code reached"

def force_cmd_parse(text):
   # 1. Split on “,” preceded by even number of backslashes.
   #
   # FIXME: Said backslashes are removed in the split, so you can’t have a
   # component with trailing backslashes. That seems rare so I’m not fixing
   # for now.
   args = re.split(r"(?<!\\)(?:\\\\)*,", text)
   # 2. Reject list of length < 2.
   if (len(args) < 2):
      ch.FATAL("--force-cmd: need at least one ARG")
   # 3. Reject list with empty first item.
   if (args[0] == ""):
      ch.FATAL("--force-cmd: CMD can’t be empty")
   # 4. Replace “\x” for any char x ⇒ literal “x”.
   args = [re.sub(r"\\(.)", r"\1", a) for a in args]
   return (args[0], args[1:])


## Classes ##

class Base:

   __slots__ = ("run_modified_ct",)  # number of RUN instructions modified

   def __init__(self):
      self.run_modified_ct = 0

   @property
   def ch_run_args(self):
      "Extra arguments for ch-run."
      return []

   def run_modified(self, args, env):
      """Modify the RUN arguments args as needed, and return the result, which
         is a new list even if unmodified. env is the environment for the RUN
         instruction. May have significant side effects, including running
         other commands in the container."""
      args_new = self.run_modified_(args, env)
      if (args_new != args):
         self.run_modified_ct += 1
         ch.INFO("--force: RUN: new command: %s" % args_new)
      return args_new

   def run_modified_(self, args, env):
      return args.copy()


class Nope(Base):
   pass


class Fakeroot(Base):

   __slots__ = ("tag",
                "name",
                "init",
                "cmds",
                "each",
                "install_done",
                "image_path")

   def __init__(self, image_path):
      super().__init__()
      match = False
      for (tag, cfg) in FAKEROOT_DEFAULT_CONFIGS.items():
         ch.VERBOSE("workarounds: testing config: %s" % tag)
         file_path = fs.Path("%s/%s" % (image_path, cfg["match"][0]))
         if (file_path.is_file() and file_path.grep_p(cfg["match"][1])):
            match = True
            break
      if (not match):
         ch.FATAL("--force=fakeroot not available (no suitable config found)")
      self.image_path = image_path
      self.tag = tag
      for i in ("name", "init", "cmds", "each"):
         setattr(self, i, cfg[i])
      self.install_done = False
      ch.INFO("--force=fakeroot: will use: %s: %s" % (self.tag, self.name))

   def install(self, img_path, env):
      for (i, (test_cmd, init_cmd)) in enumerate(self.init, 1):
         ch.INFO("--force=fakeroot: init step %s: checking: $ %s"
                 % (i, test_cmd))
         args = ["/bin/sh", "-c", test_cmd]
         exit_code = ch.ch_run_modify(img_path, args, env, fail_ok=True)
         if (exit_code == 0):
            ch.INFO("--force=fakeroot: init step %d: exit %d, step not needed"
                    % (i, exit_code))
         else:
            ch.INFO("--force=fakeroot: init step %d: $ %s" % (i, init_cmd))
            args = ["/bin/sh", "-c", init_cmd]
            ch.ch_run_modify(img_path, args, env)

   def needs_inject(self, args):
      """Return True if the command in args seems to need fakeroot injection,
         False otherwise."""
      for word in self.cmds:
         for arg in args:
            if (word in arg.split()):  # arg words separate by whitespace
               return True
      return False

   def run_modified_(self, args, env):
      if (not self.needs_inject(args)):
         ch.VERBOSE("--force=fakeroot: RUN: doesn’t need injection")
         return args.copy()
      if (self.install_done):
         ch.VERBOSE("--force=fakeroot: already installed")
      else:
         self.install(self.image_path, env)
         self.install_done = True
      return self.each + args


class Seccomp(Base):

   __slots__ = ("force_cmds",)

   def __init__(self, force_cmds):
      super().__init__()
      self.force_cmds = force_cmds

   @property
   def ch_run_args(self):
      return super().ch_run_args + ["--seccomp"]

   def run_modified_(self, args, env):
      args = args.copy()
      for (cmd, args_inject) in self.force_cmds.items():
         args_new = list()
         for word in args:
            if (word == cmd):
               # It’s a list-style RUN, e.g.:
               #
               #   RUN ["apt", "install", "-y", "foo"]
               args_new += [word] + args_inject
            else:
               # It’s a shell-style RUN, e.g.:
               #
               #   RUN apt install -y foo
               #   RUN echo foo&&apt install -y foo
               #   RUN ["/bin/sh", "-c", "apt install -y foo"]
               #
               # Note this is a no-op if the command doesn’t contain cmd.
               str_inject = ch.argv_to_string(args_inject)
               args_new.append(re.sub(r"\b(%s)(\s)" % cmd,
                                      r"\1 %s\2" % str_inject, word))
         args = args_new
      return args
