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
   img_ref = ch.Image_Ref(cli.image_ref)
   img = ch.Image(img_ref, cli.storage)
   img.unpack_delete()

def list_(cli):
   ch.dependencies_check()
   imgdir = ch.storage.unpack_base
   imgs = ch.ossafe(os.listdir, "can't list directory: %s" % imgdir, imgdir)
   for img in sorted(imgs):
      print(ch.Image_Ref(img))

def reset(cli):
   ch.rmtree(ch.storage.download_cache)
   ch.rmtree(ch.storage.unpack_base)

def storage_path(cli):
   print(ch.storage.root)
