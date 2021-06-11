# Subcommands not exciting enough for their own module.

import argparse
import os
import sys

import charliecloud as ch
import pull
import version


## argparse "actions" ##

class Action_Exit(argparse.Action):

   def __init__(self, *args, **kwargs):
      super().__init__(nargs=0, *args, **kwargs)

class Dependencies(Action_Exit):

   def __call__(self, *args, **kwargs):
      ch.dependencies_check()
      sys.exit(0)

class Version(Action_Exit):

   def __call__(self, *args, **kwargs):
      print(version.VERSION)
      sys.exit(0)


## Plain functions ##

# Argument: command line arguments Namespace. Do not need to call sys.exit()
# because caller manages that.

def delete(cli):
   ch.dependencies_check()
   img_ref = ch.Image_Ref(cli.image_ref)
   img = ch.Image(img_ref)
   img.unpack_delete()

def list_(cli):
   ch.dependencies_check()
   imgdir = ch.storage.unpack_base
   if (cli.image_ref):
      # image
      img = ch.Image(ch.Image_Ref(cli.image_ref))
      print("details of image:    %s" % img.ref)
      # present locally?
      if (not img.unpack_exist_p):
         stored = "no"
      else:
         img.metadata_load()
         stored = "yes (%s)" % img.metadata["arch"]
      print("in local storage:    %s" % stored)
      # present remotely?
      print("full remote ref:     %s" % img.ref.canonical)
      pullet = pull.Image_Puller(img, not cli.no_cache)
      pullet.fatman_load()
      if (pullet.architectures is not None):
         remote = "yes"
         arch_aware = "yes"
         arch_avail = " ".join(sorted(pullet.architectures.keys()))
      else:
         pullet.manifest_load(True)
         if (pullet.layer_hashes is not None):
            remote = "yes"
            arch_aware = "no"
            arch_avail = "unknown"
         else:
            remote = "no"
            arch_aware = "n/a"
            arch_avail = "n/a"
      pullet.done()
      print("available remotely:  %s" % remote)
      print("remote arch-aware:   %s" % arch_aware)
      print("host architecture:   %s" % ch.arch_host)
      print("archs available:     %s" % arch_avail)
   else:
      if (not os.path.isdir(ch.storage.root)):
         ch.INFO("does not exist: %s" % ch.storage.root)
         return;
      if (not ch.storage.valid_p()):
          ch.INFO("not a storage directory: %s" % ch.storage.root)
          return;
      imgs = ch.ossafe(os.listdir, "can't list directory: %s" % ch.storage.root, imgdir)
      for img in sorted(imgs):
         print(ch.Image_Ref(img))

def import_(cli):
   ch.dependencies_check()
   if (not os.path.exists(cli.path)):
      ch.FATAL("can't copy: not found: %s" % cli.path)
   dst = ch.Image(ch.Image_Ref(cli.image_ref))
   ch.INFO("importing:    %s" % cli.path)
   ch.INFO("destination:  %s" % dst)
   if (os.path.isdir(cli.path)):
      dst.copy_unpacked(cli.path)
   else:  # tarball, hopefully
      dst.unpack([cli.path])
   # initialize metadata if needed
   dst.metadata_load()
   dst.metadata_save()
   ch.done_notify()

def python_path(cli):
   print(sys.executable)

def reset(cli):
   ch.dependencies_check()
   ch.storage.reset()

def storage_path(cli):
   print(ch.storage.root)
