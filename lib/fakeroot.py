import os.path

import charliecloud as ch


## Globals ##

# FIXME: document this config
# FIXME: sequence of command vs. one long command?

DEFAULT_CONFIGS = [

   # General notes:
   #
   # 1. The first match here wins.
   #
   # 2. There are three implementations of fakeroot that I could find:
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
   # 3. Why grep specified files vs. simpler alternatives?
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

   { "match":  ("/etc/redhat-release", r"release 7\."),
     "config": { "name": "CentOS/RHEL 7",
                 "first": ["yum install -y epel-release",
                           "yum install -y fakeroot"],
                 "cmds_each": ["dnf", "rpm", "yum"],
                 "each": ["fakeroot"] } },
   { "match":  ("/etc/redhat-release", r"release 8\."),
     "config": { "name": "CentOS/RHEL 8",
                 "first": ["dnf install -y epel-release",
                           "dnf install -y fakeroot"],
                 "cmds_each": ["dnf", "rpm", "yum"],
                 "each": ["fakeroot"] } },

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

   { "match":  ("/etc/debian_version", r"^(9|10)\."),
     "config": { "name": "Debian 9 (Stretch) or 10 (Buster)",
                 "first":
["echo 'APT::Sandbox::User \"root\";' > /etc/apt/apt.conf.d/no-sandbox",
 "apt-get update",  # base image ships with no package indexes
 "apt-get install -y pseudo"],
                 "cmds_each": ["apt", "apt-get", "dpkg"],
                 "each": ["fakeroot"] } }
]


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
