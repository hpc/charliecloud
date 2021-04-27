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
      ch.INFO(ref.as_verbose_str)
      sys.exit(0)
   image = ch.Image(ref, cli.image_dir)
   ch.INFO("pulling image:   %s" % ref)
   ch.INFO("architecture:    %s" % ch.architecture.arch_canon)
   if (cli.image_dir is not None):
      ch.INFO( "destination:     %s" % image.unpack_path)
   else:
      ch.VERBOSE("destination:     %s" % image.unpack_path)
   ch.VERBOSE("use cache:       %s" % (not cli.no_cache))
   ch.VERBOSE("download cache:  %s" % ch.storage.download_cache)
   pullet = Image_Puller(image)
   ch.VERBOSE("manifest list:   %s" % pullet.manifest_list_path)
   ch.VERBOSE("manifest:        %s" % pullet.manifest_path)
   pullet.pull_to_unpacked(use_cache=(not cli.no_cache),
                           last_layer=cli.last_layer)
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

   @property
   def manifest_list_path(self):
      "Path to the fat manifest file."
      return ch.storage.manifest_list_for_download(self.image.ref)

   def download(self, use_cache):
      """Download image metadata and layers and put them in the download
         cache. If use_cache is True (the default), anything already in the
         cache is skipped, otherwise download it anyway, overwriting what's in
         the cache."""
      manifest_ref = None
      # Spec: https://docs.docker.com/registry/spec/manifest-v2-2/
      dl = ch.Registry_HTTP(self.image.ref)
      ch.VERBOSE("downloading image: %s" % dl.ref)
      ch.mkdirs(ch.storage.download_cache)

      # fat manifest
      if (ch.architecture.guess):
         if (os.path.exists(self.manifest_list_path) and use_cache):
            ch.INFO("manifest list: using existing file")
         else:
            ch.VERBOSE("manifest list: downloading")
            dl.manifest_list_to_file(self.manifest_list_path)
         # do we actually have a manifest list?
         manifest_list_json = ch.json_from_file(self.manifest_list_path)
         if ("manifests" in manifest_list_json.keys()):
            manifest_ref = self.manifest_ref_from_arch()
            ch.INFO("architecture manifest hash: %s" % manifest_ref)
            # invalidate the cache if the architecture manifest hash
            # doesn't match that in stroage
            if (os.path.exists(self.manifest_path)):
               storage_hash = ch.hash_from_file(self.manifest_path)
               if (    use_cache
                   and storage_hash != ch.hash_from_digest(manifest_ref)):
                  use_cache = False
         else:
            ch.VERBOSE("manifest list: no optional architectures")

      # manifest
      if (os.path.exists(self.manifest_path) and use_cache):
         ch.INFO("manifest: using existing file")
      else:
         ch.INFO("manifest: downloading")
         dl.manifest_to_file(self.manifest_path, manifest_ref)
      self.manifest_load()
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

   def list_architectures(self, use_cache):
      if (os.path.exists(self.manifest_list_path) and use_cache):
         ch.INFO("manifest list: using existing file")
      else:
         ch.INFO("manifest list: downloading")
         dl.manifest_list_to_file(self.manifest_list_path)
      manifest = ch.json_from_file(self.manifest_list_path)
      variant = None
      for k in manifest["manifests"]:
         if (k.get('platform').get('os') != 'linux'):
            continue
         try:
            variant = k.get('platform').get('variant')
         except KeyError:
            True
         if (variant is not None):
            variant = "/" + variant
            print(k.get('platform').get('architecture') + variant)
         else:
            print(k.get('platform').get('architecture'))

   def manifest_load(self):
      """Parse the manifest file and set self.config_hash and
         self.layer_hashes."""
      def bad_key(key):
         ch.FATAL("manifest: %s: no key: %s" % (self.manifest_path, key))
      # read and parse the JSON
      manifest = ch.json_from_file(self.manifest_path)
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

   def manifest_ref_from_arch(self):
      """Parse the fat manifest file for a digest that matches host
         architecture."""
      manifest = ch.json_from_file(self.manifest_list_path)
      arch = variant = ref = None
      try:
         arch, variant = ch.architecture.arch_canon.split("/")
      except ValueError:
         arch = ch.architecture.arch_canon
      try:
         for k in manifest["manifests"]:
            if (k.get('platform').get('os') != 'linux'):
               continue
            if (    k.get('platform').get('architecture') == arch
                and variant is not None
                and k.get('platform').get('variant') == variant):
               ref = k.get('digest')
            elif (    k.get('platform').get('architecture') == arch
                  and variant is None):
               ref = k.get('digest')
      except KeyError:
         ch.FATAL("bad arch; see list-arch")
      if ref is None:
            ch.FATAL("arch: not found in manifest list; see list-arch")
      return ref

   def pull_to_unpacked(self, use_cache=True, last_layer=None):
      "Pull and flatten image."
      self.download(use_cache)
      layer_paths = [self.layer_path(h) for h in self.layer_hashes]
      self.image.unpack(self.config_path, layer_paths, last_layer)
