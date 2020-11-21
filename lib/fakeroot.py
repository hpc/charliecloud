import os.path

import charliecloud as ch


## Globals ##

DEFAULT_CONFIGS = {

   # General notes:
   #
   # 1. Semantics of these configurations. (Character limits are to support
   #    tidy code formatting.)
   #
   #    a. This is a dictionary of configurations, which themselves are
   #       dictionaries.
   #
   #    b. Key is an arbitrary tag; user-visible. There's no enforced
   #       character set but let's stick with [a-z0-9_] for now and limit to
   #       at most 12 characters.
   #
   #    c. A configuration has the following keys.
   #
   #       name ... Human-readable name for the configuration. Max 60 chars.
   #
   #       match .. Tuple; first item is the name of a file and the second is
   #                a regular expression. If the regex matches any line in the
   #                file, that configuration is used for the image.
   #
   #       first .. List of tuples containing POSIX shell commands to perform
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
   #                  it's a different one than we would have chosen, the
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
   #                ch-grow does roughly:
   #
   #                  if ( ! $CMD_1 ); then
   #                      $CMD_2
   #                  fi
   #
   #                For both commands, the output is visible to the user but
   #                is not analyzed.
   #
   #       cmds ... List of RUN commands that need fakeroot injection. Each
   #                item in the list is matched against each
   #                whitespace-separated word in the RUN instructions. For
   #                example, suppose that cmds_each contains "dnf", and
   #                consider the following RUN instructions:
   #
   #                  RUN ['dnf', 'install', 'foo']
   #                  RUN dnf install foo
   #
   #                These are fairly standard forms. "dnf" matches both, the
   #                first on the first element in the list and the second
   #                after breaking the shell command on whitespace.
   #
   #                  RUN true&&dnf install foo
   #
   #                This third example does *not* match (false negative)
   #                because breaking on whitespace yields "true&&dnf",
   #                "install", and "foo"; none of these words are "dnf".
   #
   #                  RUN echo dnf install foo
   #
   #                This final example *does* match (false positive) becaus
   #                the second word *is* "dnf"; the algorithm isn't smart
   #                enough to realize that it's an argument to "echo".
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
   #                (Note that "/bin/sh -c" is how shell-form RUN instructions
   #                are executed regardless of --force.)
   #
   # 2. The first match wins. However, because dictionary ordering can't be
   #    relied on yet, since it was introduced in Python 3.6 [1], matches
   #    should be disjoint.
   #
   #    [1]: https://docs.python.org/3/library/stdtypes.html#dict
   #
   # 3. A matching configuration is considered applicable if any of the
   #    fakeroot-able commands are present. We do nothing if the config isn't
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
   #    * Look at image name: Misses derived images, large number of tags
   #      seems a maintenance headache, :latest changes.
   #
   #    * grep the same file for each distro: No standardized file for this.
   #
   #    * Ask lsb_release(1): Not always installed, requires executing ch-run.

   # CentOS/RHEL notes:
   #
   # 1. CentOS seems to have only fakeroot, which is in EPEL, not the standard
   #    repos.

   { "rhel7":
     { "name": "CentOS/RHEL 7",
       "match": ("/etc/redhat-release", r"release 7\."),
       "first": [ ("command -v fakeroot > /dev/null",
                   "yum install -y epel-release && yum install -y fakeroot") ],
       "cmds", ["dnf", "rpm", "yum"],
       "each": ["fakeroot"] },

   { "rhel8":
     { "name": "CentOS/RHEL 8",
       "match":  ("/etc/redhat-release", r"release 8\."),
       "first": [ ("command -v fakeroot > /dev/null",
                   "dnf install -y epel-release && dnf install -y fakeroot") ],
       "cmds", ["dnf", "rpm", "yum"],
       "each": ["fakeroot"] },

   # Debian notes:
   #
   # 1. By default in recent Debians, apt(8) runs as an unprivileged user.
   #    This makes *all* apt operations fail in an unprivileged container
   #    because it can't drop privileges. There are multiple ways to turn the
   #    “sandbox” off. As far as I can tell, none are documented, but this one
   #    at least appears in google searches a lot.
   #
   #    apt also doesn't drop privileges if there is no user _apt; in my
   #    testing, sometimes this user is present and sometimes not, for reasons
   #    I don't understand. If not present, you get this warning:
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

   "debSB":
     { "name": "Debian 9 (Stretch) or 10 (Buster)",
       "match": ("/etc/debian_version", r"^(9|10)\."),
       "first": [ ("""apt-config dump | fgrep -q 'APT::Sandbox::User "root"' \
                      || ! fgrep -q _apt /etc/passwd""",
                   """echo 'APT::Sandbox::User "root";' \
                      > /etc/apt/apt.conf.d/no-sandbox"""),
                  ("""command -v fakeroot > /dev/null""",
                   # update b/c base image ships with no package indexes
                   """apt-get update && apt-get install -y pseudo""") ],
       "cmds": ["apt", "apt-get", "dpkg"],
       "each": ["fakeroot"] } },

}


## Functions ##

def config(img):
   ch.DEBUG("fakeroot: checking configs: %s" % img)
   for c in DEFAULT_CONFIGS:
      (path, rx) = c["match"]
      path_full = "%s/%s" % (img, path)
      ch.DEBUG("fakeroot: checking %s: grep '%s' %s"
               % (c["config"]["name"], rx, path))
      if (os.path.isfile(path_full) and ch.grep_p(path_full, rx)):
         ch.DEBUG("fakeroot: using config %s" % c["config"]["name"])
         return c["config"]
   ch.DEBUG("fakeroot: no config found")
   return None

def inject_each(img, args):
   c = config(img)
   if (c is None):
      return args
   # Match on words, not substrings.
   for each in c["cmds_each"]:
      for arg in args:
         if (each in arg.split()):
            return c["each"] + args
   return args

def inject_first(img, env):
   c = config(img)
   if (c is None):
      return
   if (os.path.exists("%s/ch/fakeroot-first-run")):
      ch.DEBUG("fakeroot: already initialized")
      return
   ch.INFO("fakeroot: initializing for %s" % c["name"])
   for cl in c["first"]:
      ch.INFO("fakeroot: $ %s" % cl)
      args = ["/bin/sh", "-c", cl]
      ch.ch_run_modify(img, args, env)
