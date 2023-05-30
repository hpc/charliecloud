# Subcommands not exciting enough for their own module.

import argparse
import inspect
import os
import os.path
import sys

import build_cache as bu
import charliecloud as ch
import image as im
import filesystem as fs
import pull
import version


## argparse “actions” ##

class Action_Exit(argparse.Action):

   def __init__(self, *args, **kwargs):
      super().__init__(nargs=0, *args, **kwargs)

class Dependencies(Action_Exit):

   def __call__(self, ap, cli, *args, **kwargs):
      # ch.init() not yet called, so must get verbosity from arguments.
      ch.dependencies_check()
      if (cli.verbose >= 1):
         print("lark path: %s" % os.path.normpath(inspect.getfile(im.lark)))
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
   delete_ct = 0
   for img in im.Image.glob(cli.image_ref):
      img.unpack_delete()
      delete_ct += 1
   for img in im.Image.glob(cli.image_ref + "_stage[0-9]*"):
      img.unpack_delete()
      delete_ct += 1
   if (delete_ct == 0):
      ch.FATAL("no image matching glob, can’t delete: %s" % cli.image_ref)
   bu.cache.worktrees_fix()

def gestalt_bucache(cli):
   bu.have_deps()

def gestalt_bucache_dot(cli):
   bu.have_deps()
   bu.have_dot()

def gestalt_python_path(cli):
   print(sys.executable)

def gestalt_storage_path(cli):
   print(ch.storage.root)

def gestalt_logging(cli):
   ch.INFO("info")
   ch.VERBOSE("verbose")
   ch.DEBUG("debug")
   ch.TRACE("trace")
   ch.WARNING("warning")
   ch.ERROR("error")

"""
def gestalt_info(cli):
   ch.INFO("info message!")

def gestalt_verbose(cli):
   ch.VERBOSE("verbose message!")

def gestalt_warning(cli):
   ch.WARNING("warning message!")

def gestalt_error(cli):
   ch.ERROR("error message!")

def gestalt_debug(cli):
   ch.DEBUG("debug message!")

def gestalt_trace(cli):
   ch.TRACE("trace message...?")
"""

def import_(cli):
   if (not os.path.exists(cli.path)):
      ch.FATAL("can’t copy: not found: %s" % cli.path)
   dst = im.Image(im.Reference(cli.image_ref))
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
      images = sorted(imgdir.listdir())
      if (len(images) >= 1):
         img_width = max(len(ref) for ref in images)
         for ref in images:
            img = im.Image(im.Reference(fs.Path(ref).parts[-1]))
            if cli.long:
               print("%-*s | %s" % (img_width, img, img.last_modified.ctime()))
            else:
               print(img)
   else:
      # list specified image
      img = im.Image(im.Reference(cli.image_ref))
      print("details of image:    %s" % img.ref)
      # present locally?
      if (not img.unpack_exist_p):
         stored = "no"
      else:
         img.metadata_load()
         stored = "yes (%s), modified: %s" % (img.metadata["arch"],
                                              img.last_modified.ctime())
      print("in local storage:    %s" % stored)
      # in cache?
      (sid, commit) = bu.cache.find_image(img)
      if (sid is None):
         cached = "no"
      else:
         cached = "yes (state ID %s, commit %s)" % (sid.short, commit[:7])
         if (os.path.exists(img.unpack_path)):
            wdc = bu.cache.worktree_head(img)
            if (wdc is None):
               ch.WARNING("stored image not connected to build cache")
            elif (wdc != commit):
               ch.WARNING("stored image doesn’t match build cache: %s" % wdc)
      print("in build cache:      %s" % cached)
      # present remotely?
      print("full remote ref:     %s" % img.ref.canonical)
      pullet = pull.Image_Puller(img, img.ref)
      try:
         pullet.fatman_load()
         remote = "yes"
         arch_aware = "yes"
         arch_keys = sorted(pullet.architectures.keys())
         try:
            fmt_space = len(max(arch_keys,key=len))
            arch_avail = []
            for key in arch_keys:
               arch_avail.append("%-*s  %s" % (fmt_space, key,
                                               pullet.digests[key][:11]))
         except ValueError:
            # handles case where arch_keys is empty, e.g.
            # mcr.microsoft.com/windows:20H2.
            arch_avail = [None]
      except ch.Image_Unavailable_Error:
         remote = "no (or you are not authorized)"
         arch_aware = "n/a"
         arch_avail = ["n/a"]
      except ch.No_Fatman_Error:
         remote = "yes"
         arch_aware = "no"
         arch_avail = ["unknown"]
      pullet.done()
      print("available remotely:  %s" % remote)
      print("remote arch-aware:   %s" % arch_aware)
      print("host architecture:   %s" % ch.arch_host)
      print("archs available:     %s" % arch_avail[0])
      for arch in arch_avail[1:]:
         print((" " * 21) + arch)

def reset(cli):
   ch.storage.reset()

def undelete(cli):
   if (cli.bucache != ch.Build_Mode.ENABLED):
      ch.FATAL("only available when cache is enabled")
   img = im.Image(im.Reference(cli.image_ref))
   if (img.unpack_exist_p):
      ch.FATAL("image exists; will not overwrite")
   (_, git_hash) = bu.cache.find_image(img)
   if (git_hash is None):
      ch.FATAL("image not in cache")
   bu.cache.checkout(img, git_hash, None)
