import json
import os.path
import shutil
import sys

import charliecloud as ch


## Main ##

def main(cli):
   ch.dependencies_check()
   # Set things up.
   ref = ch.Image_Ref(cli.image_ref)
   cache = ch.Cache(cli.no_cache)
   if (cli.parse_only):
      ch.INFO(ref.as_verbose_str)
      sys.exit(0)
   image = ch.Image(ref, cli.image_dir)
   ch.INFO("pulling image:   %s" % ref)
   if (cli.image_dir is not None):
      ch.INFO( "destination:     %s" % image.unpack_path)
   else:
      ch.VERBOSE("destination:     %s" % image.unpack_path)
   cache_ops = cache.cache_ops
   ch.VERBOSE("read from download cache:      %s" % (cache_ops.dl_read))
   ch.VERBOSE("write to download cache:       %s" % (cache_ops.dl_write))
   ch.VERBOSE("read from layer cache:         %s" % (cache_ops.ly_read))
   ch.VERBOSE("write to layer cache:          %s" % (cache_ops.ly_write))
   ch.VERBOSE("download cache:  %s" % ch.storage.download_cache)
   pullet = Image_Puller(image)
   ch.VERBOSE("manifest:        %s" % pullet.manifest_path)
   pullet.pull(cache, last_layer=cli.last_layer)
   ch.done_notify()


## Classes ##

class Image_Puller:

   __slots__ = ("config_hash",
                "image",
                "layer_hashes")

   def __init__(self, image):
      self.config_hash = None
      self.image = image
      self.layer_hashes = None

   @property
   def config_path(self):
      if (self.config_hash is None):
         return None
      else:
         return ch.storage.download_cache // (self.config_hash + ".json")

   @property
   def manifest_path(self):
      "Path to the manifest file."
      return ch.storage.manifest_for_download(self.image.ref)

   def download_manifest(self, use_cache):
      """Download metadata and place in download cache. This has been 
         seperated from downloading layer to support image caching"""
      dl = ch.Registry_HTTP(self.image.ref)
      ch.mkdirs(ch.storage.download_cache)
      if (os.path.exists(self.manifest_path) and use_cache):
         ch.INFO("manifest: using existing file")
      else:
         ch.INFO("manifest: downloading")
         dl.manifest_to_file(self.manifest_path)
      self.manifest_load()
      dl.close()


   def download_layers(self, use_cache):
      """Download layers and put them in the download
         cache. If use_cache is True (the default), anything already in the
         cache is skipped, otherwise download it anyway, overwriting what's in
         the cache."""
      # Spec: https://docs.docker.com/registry/spec/manifest-v2-2/
      dl = ch.Registry_HTTP(self.image.ref)
      ch.VERBOSE("downloading image: %s" % dl.ref)
      # config
      ch.VERBOSE("config path: %s" % self.config_path)
      if (self.config_path is not None):
         if (os.path.exists(self.config_path) and use_cache):
            ch.INFO("config: using existing file")
         else:
            ch.INFO("config: downloading")
            dl.blob_to_file(self.config_hash, self.config_path)
      # layers
      for (i, lh) in enumerate(self.layer_hashes, start=1):
         path = self.layer_path(lh)
         ch.VERBOSE("layer path: %s" % path)
         ch.INFO("layer %d/%d: %s: "% (i, len(self.layer_hashes), lh[:7]),
                 end="")
         if (os.path.exists(path) and use_cache):
            ch.INFO("using existing file")
         else:
            ch.INFO("downloading")
            dl.blob_to_file(lh, path)
      dl.close()

   def layer_path(self, layer_hash):
      "Return the path to tarball for layer layer_hash."
      return ch.storage.download_cache // (layer_hash + ".tar.gz")

   def manifest_load(self):
      """Parse the manifest file and set self.config_hash and
         self.layer_hashes."""
      def bad_key(key):
         ch.FATAL("manifest: %s: no key: %s" % (self.manifest_path, key))
      # read and parse the JSON
      fp = ch.open_(self.manifest_path, "rt", encoding="UTF-8")
      text = ch.ossafe(fp.read, "can't read: %s" % self.manifest_path)
      ch.ossafe(fp.close, "can't close: %s" % self.manifest_path)
      ch.DEBUG("manifest:\n%s" % text)
      try:
         manifest = json.loads(text)
      except json.JSONDecodeError as x:
         ch.FATAL("can't parse manifest file: %s:%d: %s"
                  % (self.manifest_path, x.lineno, x.msg))
      # validate schema version
      try:
         version = manifest['schemaVersion']
      except KeyError:
         bad_key("schemaVersion")
      if (version not in {1,2}):
         ch.FATAL("unsupported manifest schema version: %s" % repr(version))
      # load config hash
      #
      # FIXME: Manifest version 1 does not list a config blob. It does have
      # things (plural) that look like a config at history/v1Compatibility as
      # an embedded JSON string :P but I haven't dug into it.
      if (version == 1):
         ch.WARNING("no config; manifest schema version 1")
         self.config_hash = None
      else:  # version == 2
         try:
            self.config_hash = ch.digest_trim(manifest["config"]["digest"])
         except KeyError:
            bad_key("config/digest")
      # load layer hashes
      if (version == 1):
         key1 = "fsLayers"
         key2 = "blobSum"
      else:  # version == 2
         key1 = "layers"
         key2 = "digest"
      if (key1 not in manifest):
         bad_key(key1)
      self.layer_hashes = list()
      for i in manifest[key1]:
         if (key2 not in i):
            bad_key("%s/%s" % (key1, key2))
         self.layer_hashes.append(ch.digest_trim(i[key2]))
      if (version == 1):
         self.layer_hashes.reverse()

   def pull_to_unpacked(self, use_cache=True, last_layer=None):
      "Pull and flatten image."
      self.download_layers(use_cache)
      layer_paths = [self.layer_path(h) for h in self.layer_hashes]
      self.image.unpack(self.config_path, layer_paths, last_layer)

   def pull(self, cache, last_layer=None):
      cache_ops = cache.cache_ops
      # First download manifest
      self.download_manifest(use_cache=(not cache_ops.dl_read))
      # Initialize the cache.
      cache.initialize()
      # Compute layer id
      lid = cache.compute_lid(open(self.manifest_path, "rb"))
      tag = str(self.image.ref)
      cache_lid = cache.lid_at_tag(tag)
      # Cache hit. We're good and pass.
      if (not cache_ops.ly_write and cache_lid == lid):
         ch.INFO("cache: %s in cache" % tag)
         # Check for inconsistent cache
         if (not os.path.isdir(self.image.unpack_path)):
            ch.FATAL("Unpack Directory %s doesn't exist. Inconsistent cache!" %
                    self.image.unpack_path)
         with ch.open_(self.image.unpack_path // "/ch/layer_id", "rt") as fp:
             file_lid= ch.ossafe(fp.read, "can't read: %s" % lid_file).strip()
         if (file_lid != lid):
            ch.FATAL("Lid at %s doesn't match computed lid. Inconsistent cache!" %
                    lid_file)
      else:
         # If git tag exists, remove it.
         if (cache_lid > 0):
            cache.rm_tag(str(ref))
         # If image exists, remove it.
         if (os.path.isdir(self.image.unpack_path)):
            image_lid_path = self.image.unpack_path // "/ch/layer_id"
            if (os.path.isdir(image_lid_path)):
               with ch.open_(image_lid_path) as fp:
                  file_lid = ch.ossafe(fp.read, "can't read: %s" % lid_file).strip()
               if (file_lid != lid):
                  ch.FATAL("Lid at %s doesn't match computed lid. Inconsistent cache!" %
                           lid_file)
            ch.INFO("Removing old image")
            ch.rmtree(self.image.unpack_path)
         # If --no-cache=ly-write, create an empty directory.
         if (cache_ops.ly_write):
            ch.mkdirs(self.image.unpack_path // tag)
            self.pull_to_unpacked(use_cache=(not cache_ops.dl_read), last_layer=last_layer)
         else:
            # Add image to the cache and create worktree
            cache.add_image(tag)
            # Super kldugy
            # Need to satisfy shutil and git empty directory reqs.
            temp_path = ch.Path(str(self.image.unpack_path) + '_temp')
            image_path = self.image.unpack_path
            shutil.move(image_path, temp_path)
            # Unpack to directory
            self.pull_to_unpacked(use_cache=(not cache_ops.dl_read), last_layer=last_layer)
            shutil.move(temp_path // '.git', image_path // '.git')
            shutil.rmtree(temp_path)
            # Add layer_id file
            ch.mkdirs(self.image.unpack_path // "/ch/")
            with ch.open_(self.image.unpack_path // "/ch/layer_id",
                    "wt") as fp:
               print("%s" % lid, file=fp)
            cache.add_layer(lid)
            cache.tag_image(tag)
         ch.done_notify()
