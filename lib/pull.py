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
   if (ch.arch is not None and ch.arch != "yolo"):
      ch.INFO("architecture:    %s" % ch.arch)
   if (cli.image_dir is not None):
      ch.INFO( "destination:     %s" % image.unpack_path)
   else:
      ch.VERBOSE("destination:     %s" % image.unpack_path)
   ch.VERBOSE("use cache:       %s" % (not cli.no_cache))
   ch.VERBOSE("download cache:  %s" % ch.storage.download_cache)
   pullet = Image_Puller(image)
   ch.VERBOSE("manifest list:   %s" % pullet.fat_manifest_path)
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
   def fat_manifest_path(self):
      "Path to the fat manifest file."
      return ch.storage.fat_manifest_for_download(self.image.ref)

   def manifest_path(self, hash_=None):
      if (hash_ is None):
         return ch.storage.manifest_for_download(self.image.ref)
      else:
         return ch.storage.manifest_for_download(hash_)

   def download(self, use_cache):
      """Download image metadata and layers and put them in the download
         cache. If use_cache is True (the default), anything already in the
         cache is skipped, otherwise download it anyway, overwriting what's in
         the cache."""
      manifest_digest = None
      manifest_hash = None
      # Spec: https://docs.docker.com/registry/spec/manifest-v2-2/
      dl = ch.Registry_HTTP(self.image.ref)
      ch.VERBOSE("downloading image: %s" % dl.ref)
      ch.mkdirs(ch.storage.download_cache)
      # fat manifest
      if (ch.arch != "yolo"):
         if (os.path.exists(self.fat_manifest_path) and use_cache):
            ch.INFO("list of manifests: using existing file")
         else:
            ch.INFO("list of manifests: downloading")
            dl.fat_manifest_to_file(self.fat_manifest_path)
         # do we actually have a manifest list?
         fat_manifest_json = ch.json_from_file(self.fat_manifest_path)
         if ("manifests" in fat_manifest_json.keys()):
            manifest_digest = self.manifest_digest_by_arch()
            manifest_hash = ch.digest_trim(manifest_digest)
            ch.VERBOSE("architecture manifest hash: %s" % manifest_digest)
            ch.DEBUG("canonical manifest path: %s "
                     % self.manifest_path(manifest_hash))
         else:
            ch.VERBOSE("list of manifests: no other manifests")
      manifest_path = self.manifest_path(manifest_hash)
      # manifest
      if (os.path.exists(manifest_path) and use_cache):
         ch.INFO("manifest: using existing file")
      else:
         ch.INFO("manifest: downloading")
         dl.manifest_to_file(manifest_path, manifest_digest)
      self.manifest_load(manifest_path)
      # config
      ch.VERBOSE("config path: %s" % self.config_path)
      if (self.config_path is not None):
         if (os.path.exists(self.config_path) and use_cache):
            ch.INFO("config: using existing file")
         else:
            ch.INFO("config: downloading")
            dl.blob_to_file(self.config_hash, self.config_path)
      if (ch.arch != "yolo" and self.config_path is not None):
          config_json = ch.json_from_file(self.config_path)
          try:
             if (config_json["architecture"] == ch.arch):
                ch.VERBOSE("config: architecture match")
             else:
                FATAL("arch: %s: does not match architecture in config"
                      % ch.arch)
          except KeyError:
             ch.WARNING("config: missing 'arch' key; cannot confirm host match")

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
      if (os.path.exists(self.fat_manifest_path) and use_cache):
         ch.INFO("manifest list: using existing file")
      else:
         ch.INFO("manifest list: downloading")
         dl.fat_manifest_to_file(self.fat_manifest_path)
      manifest = ch.json_from_file(self.fat_manifest_path)
      variant = None
      list_ = []
      for k in manifest["manifests"]:
         if (k.get('platform').get('os') != 'linux'):
            continue
         try:
            variant = k.get('platform').get('variant')
         except KeyError:
            True
         if (variant is not None):
            variant = "/" + variant
            list_.append(k.get('platform').get('architecture') + variant)
         else:
            list_.append(k.get('platform').get('architecture'))
      return list_

   def manifest_load(self, manifest_path):
      """Parse the manifest file and set self.config_hash and
         self.layer_hashes."""
      def bad_key(key):
         ch.FATAL("manifest: %s: no key: %s" % (manifest_path, key))
      # read and parse the JSON
      manifest = ch.json_from_file(manifest_path)
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

   def manifest_digest_by_arch(self):
      """Return the manifest reference (digest) of target architecture in the
         fat manifest if the reference exists; otherwise error if specified
         arch is not 'host'."""
      manifest = ch.json_from_file(self.fat_manifest_path)
      arch     = None
      ref      = None
      variant  = None
      try:
         arch, variant = ch.arch.split("/", maxsplit=1)
      except ValueError:
         arch = ch.arch
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
               ARCH_FOUND = 'yas queen'
      except KeyError:
         ch.FATAL("arch: %s: bad argument; see list --help" % arch)
      if (ref is None and arch != "host"):
            ch.FATAL("arch: %s: not found in manifest list; see list --help"
                     % arch)
      return ref

   def pull_to_unpacked(self, use_cache=True, last_layer=None):
      "Pull and flatten image."
      self.download(use_cache)
      layer_paths = [self.layer_path(h) for h in self.layer_hashes]
      self.image.unpack(self.config_path, layer_paths, last_layer)
