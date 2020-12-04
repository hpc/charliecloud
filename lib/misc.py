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

def list_(cli):
   ch.dependencies_check()
   imgdir = ch.storage.unpack_base
   imgs = ch.ossafe(os.listdir, "can't list directory: %s" % imgdir, imgdir)
   for img in sorted(imgs):
      print(ch.Image_Ref(img))

def pull(cli):
   ch.dependencies_check()
   # Set things up.
   ref = ch.Image_Ref(cli.image_ref, cli.image_dir)
   if (cli.parse_only):
      print(ref.as_verbose_str)
      sys.exit(0)
   image = ch.Image(ref)
   ch.INFO("pulling image:   %s" % image.ref)
   if (cli.image_dir is not None):
      ch.INFO( "destination:     %s" % image.unpack_path)
   else:
      ch.DEBUG("destination:     %s" % image.unpack_path)
   ch.DEBUG("use cache:       %s" % (not cli.no_cache))
   ch.DEBUG("download cache:  %s" % storage.download_cache)
   ch.DEBUG("manifest:        %s" % image.manifest_path)
   # Pull!
   image.pull_to_unpacked(use_cache=(not cli.no_cache),
                          last_layer=cli.last_layer)
   # Done.
   ch.INFO("done")

def push(cli):
   ch.dependencies_check()
   ulcache = ch.storage.upload_cache
   if (cli.image_dir is not None):
      image_dir = cli.image_dir
   else:
      image_dir = ch.storage.unpack(image_ref)
   # Stage upload.
   image_ref = ch.Image_Ref(cli.local_image_ref)
   image_manifest = str(image_ref) + ".manifest.json"
   image_path = os.path.join(image_dir, image_ref.for_path)
   if (not os.path.isdir(image_path)):
      ch.FATAL("local image '%s' not found" % image_path)
   # Images we push will always be different from those we pull fro dockerhub
   # because we don't preserve gid/uid mapping (can't without
   # set[u|g]id helpers). Thus we store our artifacts in the STORAGE/ulcache
   # directory.
   #
   # FIXME: if we have an existing upload manifest, do we push it's exiting
   # referenced artifacts (i.e., layer tarballs, manifest, etc.)?
   if (os.path.isfile(os.path.join(ulcache, image_manifest))):
      ch.DEBUG("FIXME: local image upload manifest '%s/%s' found; use it?"
               % (ulcache, image_manifest))
   if (cli.dest_image_ref):
      dest_image_ref = ch.Image_Ref(cli.dest_image_ref)
      dest_image_ref.defaults_add()
   else:
      dest_image_ref = image_ref
   dest_image_ref.defaults_add()
   ch.INFO("pushing image:   %s" % image_ref)
   ch.INFO("destination:     https://%s" % dest_image_ref)
   upload = ch.Image_Upload(image_path, dest_image_ref)
   # Koby!
   upload.push_to_repo(image_path, ulcache)
   ch.INFO('done')
   # upload.push_to_repo(image_path, ulcache, cli.chunked_upload)

def storage_path(cli):
   print(ch.storage.root)

