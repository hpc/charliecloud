import json
import os.path
import sys

import charliecloud as ch


## Main ##

def main(cli):
   ch.dependencies_check()
   # Set things up.
   ref = ch.Image_Ref(cli.image_ref)
   if (cli.parse_only):
      print(ref.as_verbose_str)
      sys.exit(0)
   image = ch.Image(ref, cli.image_dir)
   pullet = Image_Puller(image)
   ch.INFO("pulling image:   %s" % image.ref)
   if (cli.image_dir is not None):
      ch.INFO( "destination:     %s" % image.unpack_path)
   else:
      ch.DEBUG("destination:     %s" % image.unpack_path)
   ch.DEBUG("use cache:       %s" % (not cli.no_cache))
   ch.DEBUG("download cache:  %s" % ch.storage.download_cache)
   ch.DEBUG("manifest:        %s" % pullet.manifest_path)
   # Pull!
   pullet.pull_to_unpacked(use_cache=(not cli.no_cache),
                           last_layer=cli.last_layer)
   # Done.
   ch.INFO("done")


## Classes ##

class Image_Puller:

   __slots__ = ("image",)

   def __init__(self, image):
      self.image = image

   @property
   def manifest_path(self):
      "Path to the manifest file."
      return ch.storage.manifest(self.image.ref)

   def download(self, use_cache):
      """Download image manifest and layers according to origin and put them
         in the download cache. By default, any components already in the
         cache are skipped; if use_cache is False, download them anyway,
         overwriting what's in the cache."""
      # Spec: https://docs.docker.com/registry/spec/manifest-v2-2/
      dl = ch.Repo_Data_Transfer(self.image.ref)
      ch.DEBUG("downloading image: %s" % dl.ref)
      ch.mkdirs(ch.storage.download_cache)
      # manifest
      if (os.path.exists(self.manifest_path) and use_cache):
         ch.INFO("manifest: using existing file")
      else:
         ch.INFO("manifest: downloading")
         dl.get_manifest(self.manifest_path)
      # layers
      layer_hashes = self.layer_hashes_load()
      for (i, lh) in enumerate(layer_hashes, start=1):
         path = self.layer_path(lh)
         ch.DEBUG("layer path: %s" % path)
         ch.INFO("layer %d/%d: %s: "% (i, len(layer_hashes), lh[:7]), end="")
         if (os.path.exists(path) and use_cache):
            ch.INFO("using existing file")
         else:
            ch.INFO("downloading")
            dl.get_layer(lh, path)
      dl.close()

   def layer_hashes_load(self):
      "Return sequence of layer hashes (as hex strings) from manifest."
      try:
         fp = ch.open_(self.manifest_path, "rt", encoding="UTF-8")
      except OSError as x:
         ch.FATAL("can't open manifest file: %s: %s"
                  % (self.manifest_path, x.strerror))
      try:
         doc = json.load(fp)
      except json.JSONDecodeError as x:
         ch.FATAL("can't parse manifest file: %s:%d: %s"
                  % (self.manifest_path, x.lineno, x.msg))
      try:
         schema_version = str(doc['schemaVersion'])
      except KeyError:
         ch.FATAL("manifest file %s missing expected key 'schemaVersion'"
                  % self.manifest_path)
      if (schema_version == '1'):
         ch.DEBUG('loading layer hashes from schema version 1 manifest')
         try:
            hashes = [i["blobSum"].split(":")[1] for i in doc["fsLayers"]]
         except (KeyError, AttributeError, IndexError) as x:
            ch.FATAL("can't parse manifest file: %s:%d :%s"
                     % self.manifest_path, x.lineno, x.msg)
         hashes.reverse()
      elif (schema_version == '2'):
         ch.DEBUG('loading layer hashes from schema version 2 manifest')
         try:
            hashes = [i["digest"].split(":")[1] for i in doc["layers"]]
         except (KeyError, AttributeError, IndexError):
            ch.FATAL("can't parse manifest file: %s:%d :%s"
                     % self.manifest_path, x.lineno, x.msg)
      else:
         ch.FATAL("unsupported manifest schema version: %s" % schema_version)
      return hashes

   def layer_path(self, layer_hash):
      "Return the path to tarball for layer layer_hash."
      return "%s/%s.tar.gz" % (ch.storage.download_cache, layer_hash)

   def layers_enumerate(self):
      """Read the manifest and return a sequence of layer tarball paths,
         lowest layer first."""
      return [self.layer_path(h) for h in self.layer_hashes_load()]

   def pull_to_unpacked(self, use_cache=True, fixup=False, last_layer=None):
      """Pull and flatten image. If fixup, then also add the Charliecloud
         workarounds to the image directory."""
      self.download(use_cache)
      layer_paths = self.layers_enumerate()
      self.image.flatten(layer_paths, last_layer)
      if (fixup):
         self.image.fixup()
