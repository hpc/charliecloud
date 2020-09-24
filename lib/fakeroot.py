   #Buster notes (merge with #498 for tech docs):
   #
   # 1. By default, apt(8) runs in a sandbox as an unprivileged user. This
   #    makes *all* apt operations fail in an unprivileged container because
   #    it can't drop privileges. There are multiple ways to turn the sandbox
   #    off. As far as I can tell, none are documented, but this one at least
   #    appears in google searches a lot. The other alternative I found was to
   #    delete the _apt user.
   #
   #    FIXME: Now that I try it again, the _apt user isn't present and
   #    "apt-get update" works. I just get the warning:
   #
   #      W: No sandbox user '_apt' on the system, can not drop privileges
   #
   # 2. There are three implementations of fakeroot, all in the standard
   #    repos: fakeroot, fakeroot-ng, and pseudo. Both fakeroot-ng and pseudo
   #    yield a successful install of openssh-client, but fakeroot does not.
   #    Both use a daemon process, while fakeroot does not. fakeroot-ng is
   #    quite old (last upstream release 0.18 in 2013, source code on
   #    Sourceforge) and does not support ARM. pseudo is heavier, e.g.
   #    persistent databases & daemons, and still a bit old (last upstream
   #    1.9.0 2018-01-20, last Git commit 2019-08-02), but does support many
   #    architectures including ARM. By contrast "old" fakeroot seems to have
   #    had version 1.24 2019-09-07 with the most recent commit 2020-08-12.
   #    (All this as of 2020-09-02.)
   #

import os.path

import charliecloud as ch


## Globals ##

# FIXME: document this config
# FIXME: sequence of command vs. one long command?

DEFAULT_CONFIGS = [
   # CentOS/RHEL 7

   # CentOS/RHEL 6

   # Debian 9 (Stretch)

   { "match":  ("/etc/debian_version", r"^10\."),
     "config": { "name": "Debian 10 (Buster)",
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
      ch.DEBUG("fakeroot: checking %s: grep '%s' %s"
               % (c["config"]["name"], rx, path))
      if ch.grep_p("%s/%s" % (img, path), rx):
         ch.DEBUG("fakeroot: using config %s" % c["config"]["name"])
         return c["config"]
   ch.DEBUG("fakeroot: no config found")
   return None

def inject_each(img, args):
   c = config(img)
   if (c is None):
      return args
   else:
      return c["each"] + args

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
