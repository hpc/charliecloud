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
   ref = ch.Image_Ref(cli.image_ref)
   if (cli.parse_only):
      print(ref.as_verbose_str)
      sys.exit(0)
   image = ch.Image(ref, cli.image_dir)
   ch.INFO("pulling image:   %s" % image.ref)
   if (cli.image_dir is not None):
      ch.INFO( "destination:     %s" % image.unpack_path)
   else:
      ch.DEBUG("destination:     %s" % image.unpack_path)
   ch.DEBUG("use cache:       %s" % (not cli.no_cache))
   ch.DEBUG("download cache:  %s" % ch.storage.download_cache)
   ch.DEBUG("manifest:        %s" % image.manifest_path)
   # Pull!
   image.pull_to_unpacked(use_cache=(not cli.no_cache),
                          last_layer=cli.last_layer)
   # Done.
   ch.INFO("done")

def push(cli):
   ch.dependencies_check()
   # FIXME: validate it's an image using Megan's new function
   src_ref = ch.Image_Ref(cli.source_ref)
   ch.INFO("pushing image:   %s" % src_ref)
   if (cli.image_dir is not None):
      image_dir = cli.image_dir
      if (not os.path.isdir(image_dir)):
          ch.FATAL("can't push: %s does not appear to be an image" % image_dir)
   else:
      image_dir = ch.storage.unpack(src_ref)
      if (not os.path.isdir(image_dir)):
          ch.FATAL("can't push: no image %s" % src_ref)
   if (clid.dest_ref is not None):
      dst_ref = ch.Image_Ref(cli.dest_ref)
      ch.INFO("destination:     %s" % dst_ref)
   else:
      dst_ref = ch.Image_Ref(cli.source_ref)
   dst_ref.defaults_add()
   # FIXME -- YOU ARE HERE
   # Should we split out the downloading stuff from Image?
   # main Image has from_layers() and to_layers()?
   up = ch.Image_Upload(image_dir, dst_ref)
   up.push()
   ch.INFO("done")

   
   # FIXME -- old stuff follows
   # Stage upload.
   image_manifest = str(image_ref) + ".manifest.json"
   image_path = os.path.join(image_dir, image_ref.for_path)
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
   # Koby!
   upload.push_to_repo(image_path, ulcache)
   ch.INFO('done')
   # upload.push_to_repo(image_path, ulcache, cli.chunked_upload)

def storage_path(cli):
   print(ch.storage.root)

