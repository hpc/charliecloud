# Subcommands not exciting enough for their own module.

import argparse
import inspect
import os
import os.path
import sys

import build_cache as bu
import charliecloud as ch
import pull
import version


## argparse "actions" ##

class Action_Exit(argparse.Action):

   def __init__(self, *args, **kwargs):
      super().__init__(nargs=0, *args, **kwargs)

class Dependencies(Action_Exit):

   def __call__(self, ap, cli, *args, **kwargs):
      # ch.init() not yet called, so must get verbosity from arguments.
      ch.dependencies_check()
      if (cli.verbose >= 1):
         print("lark path: %s" % os.path.normpath(inspect.getfile(ch.lark)))
      sys.exit(0)

class Version(Action_Exit):

   def __call__(self, *args, **kwargs):
      print(version.VERSION)
      sys.exit(0)


## Plain functions ##

# Argument: command line arguments Namespace. Do not need to call sys.exit()
# because caller manages that.

def build_cache(cli):
   if (cli.bucache == ch.Build_Mode.DISABLED):
      ch.FATAL("build-cache subcommand invalid with build cache disabled")
   if (cli.reset):
      bu.cache.reset()
   if (cli.gc):
      bu.cache.garbageinate()
   if (cli.tree):
      bu.cache.tree_print()
   if (cli.dot):
      bu.cache.tree_dot()
   bu.cache.summary_print()

def delete(cli):
   img = ch.Image(ch.Image_Ref(cli.image_ref))
   img.unpack_delete()
   bu.cache.worktrees_prune()

def gestalt_bucache(cli):
   bu.have_deps()

def gestalt_bucache_dot(cli):
   bu.have_deps()
   bu.have_dot()

def gestalt_python_path(cli):
   print(sys.executable)

def gestalt_storage_path(cli):
   print(ch.storage.root)

def import_(cli):
   if (not os.path.exists(cli.path)):
      ch.FATAL("can't copy: not found: %s" % cli.path)
   dst = ch.Image(ch.Image_Ref(cli.image_ref))
   ch.INFO("importing:    %s" % cli.path)
   ch.INFO("destination:  %s" % dst)
   dst.unpack_clear()
   if (os.path.isdir(cli.path)):
      dst.copy_unpacked(cli.path)
   else:  # tarball, hopefully
      dst.unpack([cli.path])
   bu.cache.adopt(dst)
   ch.done_notify()

def list_(cli):
   imgdir = ch.storage.unpack_base
   if (cli.image_ref is None):
      # list all images
      if (not os.path.isdir(ch.storage.root)):
         ch.FATAL("does not exist: %s" % ch.storage.root)
      if (not ch.storage.valid_p):
         ch.FATAL("not a storage directory: %s" % ch.storage.root)
      for img in sorted(ch.listdir(imgdir)):
         print(ch.Image_Ref(img.parts[-1])) # ensure consistent str coversion
   else:
      # list specified image
      img = ch.Image(ch.Image_Ref(cli.image_ref))
      print("details of image:    %s" % img.ref)
      # present locally?
      if (not img.unpack_exist_p):
         stored = "no"
      else:
         img.metadata_load()
         stored = "yes (%s)" % img.metadata["arch"]
      print("in local storage:    %s" % stored)
      # in cache?
      (sid, commit) = bu.cache.find_image(img)
      if (sid is None):
         cached = "no"
      else:
         cached = "yes (state ID %s, commit %s)" % (sid.short, commit[:7])
         if (os.path.exists(img.unpack_path)):
            wdc = bu.cache.worktree_get_head(img)
            if (wdc is None):
               ch.WARNING("stored image not connected to build cache")
            elif (wdc != commit):
               ch.WARNING("stored image doesn't match build cache: %s" % wdc)
      print("in build cache:      %s" % cached)
      # present remotely?
      print("full remote ref:     %s" % img.ref.canonical)
      pullet = pull.Image_Puller(img, img.ref)
      try:
         pullet.fatman_load()
         remote = "yes"
         arch_aware = "yes"
         arch_avail = " ".join(sorted(pullet.architectures.keys()))
      except ch.Image_Unavailable_Error:
         remote = "no (or you are not authorized)"
         arch_aware = "n/a"
         arch_avail = "n/a"
      except ch.No_Fatman_Error:
         remote = "yes"
         arch_aware = "no"
         arch_avail = "unknown"
      pullet.done()
      print("available remotely:  %s" % remote)
      print("remote arch-aware:   %s" % arch_aware)
      print("host architecture:   %s" % ch.arch_host)
      print("archs available:     %s" % arch_avail)

def reset(cli):
   ch.storage.reset()

