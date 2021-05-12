# Subcommands not exciting enough for their own module.

import argparse
import os
import sys

import charliecloud as ch
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
   img = ch.Image(img_ref, cli.storage)
   img.unpack_delete()

def list_(cli):
   ch.dependencies_check()
   imgdir = ch.storage.unpack_base
   imgs = ch.ossafe(os.listdir, "not a storage directory: %s" 
        % ch.storage.root, imgdir)
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
