import json
import os.path
import sys

import charliecloud as ch

## Constants ##

# Internal library of manifests, e.g. for "FROM scratch" (issue #1013).
manifests_internal = {
   "scratch": {  # magic empty image
      "schemaVersion": 2,
      "config": { "digest": None },
      "layers": []
   }
}


## Main ##

def main(cli):
   ch.dependencies_check()
   # Set things up.
   ref = ch.Image_Ref(cli.image_ref)
   if (cli.parse_only):
      print(ref.as_verbose_str)
      sys.exit(0)
   image = ch.Image(ref, cli.image_dir)
   ch.INFO("pulling image:    %s" % ref)
   ch.INFO("requesting arch:  %s" % ch.arch)
   if (cli.image_dir is not None):
      ch.INFO("destination:      %s" % image.unpack_path)
   else:
      ch.VERBOSE("destination:      %s" % image.unpack_path)
   pullet = Image_Puller(image, not cli.no_cache)
   pullet.pull_to_unpacked(cli.last_layer)
   pullet.done()
   ch.done_notify()


## Classes ##

class Image_Puller:

   __slots__ = ("architectures",  # key: architecture, value: manifest digest
                "config_hash",
                "image",
                "layer_hashes",
                "registry",
                "use_cache")

   def __init__(self, image, use_cache):
      self.architectures = None
      self.image = image
      self.registry = ch.Registry_HTTP(image.ref)
      self.config_hash = None
      self.layer_hashes = None
      self.use_cache = use_cache

   @property
   def config_path(self):
      if (self.config_hash is None):
         return None
      else:
         return ch.storage.download_cache // (self.config_hash + ".json")

   @property
   def fatman_path(self):
      return ch.storage.fatman_for_download(self.image.ref)

   @property
   def manifest_path(self):
      if (str(self.image.ref) in manifests_internal):
         return "[internal library]"
      else:
         if (ch.arch == "yolo"):
            digest = None
         else:
            try:
               digest = self.architectures[ch.arch]
            except TypeError:
               digest = None
         return ch.storage.manifest_for_download(self.image.ref, digest)

   def done(self):
      self.registry.close()

   def download(self):
      "Download image metadata and layers and put them in the download cache."
      # Spec: https://docs.docker.com/registry/spec/manifest-v2-2/
      ch.VERBOSE("downloading image: %s" % self.image)
      ch.mkdirs(ch.storage.download_cache)
      # fat manifest
      if (ch.arch != "yolo"):
         self.fatman_load()
         if (self.architectures is not None):
            if (ch.arch not in self.architectures):
               ch.FATAL("requested arch unavailable: %s not one of: %s"
                        % (ch.arch,
                           " ".join(sorted(self.architectures.keys()))))
         elif (ch.arch == "amd64"):
            # We're guessing that enough arch-unaware images are amd64 to
            # barge ahead if requested architecture is amd64.
            ch.arch = "yolo"
            ch.WARNING("image is architecture-unaware")
            ch.WARNING("requested arch is amd64; switching to --arch=yolo")
         else:
            ch.FATAL("image is architecture-unaware; try --arch=yolo?")
      # manifest
      self.manifest_load()
      # config
      ch.VERBOSE("config path: %s" % self.config_path)
      if (self.config_path is not None):
         if (os.path.exists(self.config_path) and self.use_cache):
            ch.INFO("config: using existing file")
         else:
            ch.INFO("config: downloading")
            self.registry.blob_to_file(self.config_hash, self.config_path)
      # layers
      for (i, lh) in enumerate(self.layer_hashes, start=1):
         path = self.layer_path(lh)
         ch.VERBOSE("layer path: %s" % path)
         ch.INFO("layer %d/%d: %s: "% (i, len(self.layer_hashes), lh[:7]),
                 end="")
         if (os.path.exists(path) and self.use_cache):
            ch.INFO("using existing file")
         else:
            ch.INFO("downloading")
            self.registry.blob_to_file(lh, path)

   def error_decode(self, data):
      """Decode first error message in registry error blob and return a tuple
         (code, message)."""
      try:
         code = data["errors"][0]["code"]
         msg = data["errors"][0]["message"]
      except (IndexError, KeyError):
         ch.FATAL("malformed error data (yes this is ironic)")
      return (code, msg)

   def fatman_load(self):
      """Load the fat manifest JSON file, downloading it first if needed. If
         the image has a fat manifest, populate self.architectures; this may
         be an empty dictionary if no valid architectures were found.

         It is not an error if the image has no fat manifest or the registry
         reports no such image. In this architecture-unaware condition, set
         self.architectures to None."""
      self.architectures = None
      if (str(self.image.ref) in manifests_internal):
         return  # no fat manifests for internal library
      if (os.path.exists(self.fatman_path) and self.use_cache):
         ch.INFO("manifest list: using existing file")
      else:
         ch.INFO("manifest list: downloading")
         self.registry.fatman_to_file(self.fatman_path, True)
      if (not os.path.exists(self.fatman_path)):
         # Response was 404.
         ch.INFO("manifest list: no list found")
         return
      fm = ch.json_from_file(self.fatman_path, "fat manifest")
      if ("layers" in fm or "fsLayers" in fm):
         # If there is no fat manifest but the image exists, we get a skinny
         # manifest instead. We can't use it, however, because it might be a
         # v1 manifest when a v2 is available. ¯\_(ツ)_/¯
         ch.INFO("manifest list: no valid list found")
         return
      if ("errors" in fm):
         # fm is an error blob.
         (code, msg) = self.error_decode(fm)
         if (code == "MANIFEST_UNKNOWN"):
            ch.INFO("manifest list: no such image")
            return
         else:
            ch.FATAL("manifest list: error: %s" % msg)
      self.architectures = dict()
      if ("manifests" not in fm):
         ch.FATAL("manifest list has no key 'manifests'")
      for m in fm["manifests"]:
         try:
            if (m["platform"]["os"] != "linux"):
               continue
            arch = m["platform"]["architecture"]
            if ("variant" in m["platform"]):
               arch = "%s/%s" % (arch, m["platform"]["variant"])
            digest = m["digest"]
         except KeyError:
            ch.FATAL("manifest lists missing a required key")
         if (arch in self.architectures):
            ch.FATAL("manifest list: duplicate architecture: %s" % arch)
         self.architectures[arch] = ch.digest_trim(digest)
      if (len(self.architectures) == 0):
         ch.WARNING("no valid architectures found")

   def layer_path(self, layer_hash):
      "Return the path to tarball for layer layer_hash."
      return ch.storage.download_cache // (layer_hash + ".tar.gz")

   def manifest_load(self, continue_404=False):
      """Download the manifest file if needed, parse it, and set
         self.config_hash and self.layer_hashes. By default, if the image does
         not exist, exit with error; if continue_404, then log the condition
         but do not exit. In this case, self.config_hash and self.layer_hashes
         will both be None."""
      def bad_key(key):
         ch.FATAL("manifest: %s: no key: %s" % (self.manifest_path, key))
      self.config_hash = None
      self.layer_hashes = None
      # obtain the manifest
      try:
         # internal manifest library, e.g. for "FROM scratch"
         manifest = manifests_internal[str(self.image.ref)]
         ch.INFO("manifest: using internal library")
      except KeyError:
         # download the file if needed, then parse it
         if (ch.arch == "yolo"):
            digest = None
         else:
            try:
               digest = self.architectures[ch.arch]
            except TypeError:
               digest = None
         ch.DEBUG("manifest digest: %s" % digest)
         if (os.path.exists(self.manifest_path) and self.use_cache):
            ch.INFO("manifest: using existing file")
         else:
            ch.INFO("manifest: downloading")
            self.registry.manifest_to_file(self.manifest_path, digest=digest,
                                           continue_404=continue_404)
         if (not os.path.exists(self.manifest_path)):
            # response was 404
            ch.INFO("manifest: none found")
            return
         manifest = ch.json_from_file(self.manifest_path, "manifest")
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
         ch.VERBOSE("no config; manifest schema version 1")
         self.config_hash = None
      else:  # version == 2
         try:
            self.config_hash = manifest["config"]["digest"]
            if (self.config_hash is not None):
               self.config_hash = ch.digest_trim(self.config_hash)
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

   def pull_to_unpacked(self, last_layer=None):
      "Pull and flatten image."
      self.download()
      layer_paths = [self.layer_path(h) for h in self.layer_hashes]
      self.image.unpack(layer_paths, last_layer)
      self.image.metadata_replace(self.config_path)
      # Check architecture we got. This is limited because image metadata does
      # not store the variant. Move fast and break things, I guess.
      arch_image = self.image.metadata["arch"] or "unknown"
      arch_short = ch.arch.split("/")[0]
      arch_host_short = ch.arch_host.split("/")[0]
      if (arch_image != "unknown" and arch_image != arch_host_short):
         host_mismatch = " (does not match host %s)" % ch.arch_host
      else:
         host_mismatch = ""
      ch.INFO("image arch:       %s%s" % (arch_image, host_mismatch))
      if (ch.arch != "yolo" and arch_short != arch_image):
         ch.WARNING("image architecture does not match requested: %s ≠ %s"
                    % (ch.arch, image_arch))
