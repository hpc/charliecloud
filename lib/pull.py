import json
import os.path
import sys

import charliecloud as ch
import build_cache as bu
import filesystem as fs
import image as im
import registry as rg


## Constants ##

# Internal library of manifests, e.g. for “FROM scratch” (issue #1013).
manifests_internal = {
   "scratch": {  # magic empty image
      "schemaVersion": 2,
      "config": { "digest": None },
      "layers": []
   }
}


## Main ##

def main(cli):
   # Set things up.
   src_ref = im.Reference(cli.source_ref)
   dst_ref = src_ref if cli.dest_ref is None else im.Reference(cli.dest_ref)
   if (cli.parse_only):
      print(src_ref.as_verbose_str)
      ch.exit(0)
   dst_img = im.Image(dst_ref)
   ch.INFO("pulling image:    %s" % src_ref)
   if (src_ref != dst_ref):
      ch.INFO("destination:      %s" % dst_ref)
   ch.INFO("requesting arch:  %s" % ch.arch)
   bu.cache.pull_eager(dst_img, src_ref, cli.last_layer)
   ch.done_notify()


## Classes ##

class Image_Puller:

   __slots__ = ("architectures",  # key: architecture, value: manifest digest
                "config_hash",
                "digests",
                "image",
                "layer_hashes",
                "registry",
                "sid_input",
                "src_ref")

   def __init__(self, image, src_ref):
      self.architectures = None
      self.config_hash = None
      self.digests = dict()
      self.image = image
      self.layer_hashes = None
      self.registry = rg.HTTP(src_ref)
      self.sid_input = None
      self.src_ref = src_ref

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
         if (ch.arch == "yolo" or self.architectures is None):
            digest = None
         else:
            digest = self.architectures[ch.arch]
         return ch.storage.manifest_for_download(self.image.ref, digest)

   def done(self):
      self.registry.close()

   def download(self):
      "Download image metadata and layers and put them in the download cache."
      # Spec: https://docs.docker.com/registry/spec/manifest-v2-2/
      ch.VERBOSE("downloading image: %s" % self.image)
      have_skinny = False
      try:
         # fat manifest
         if (ch.arch != "yolo"):
            try:
               self.fatman_load()
               if (not self.architectures.in_warn(ch.arch)):
                  ch.FATAL("requested arch unavailable: %s" % ch.arch,
                           ("available: %s"
                            % " ".join(sorted(self.architectures.keys()))))
            except ch.No_Fatman_Error:
               # currently, this error is only raised if we’ve downloaded the
               # skinny manifest.
               have_skinny = True
               if (ch.arch == "amd64"):
                  # We’re guessing that enough arch-unaware images are amd64 to
                  # barge ahead if requested architecture is amd64.
                  ch.arch = "yolo"
                  ch.WARNING("image is architecture-unaware")
                  ch.WARNING("requested arch is amd64; using --arch=yolo")
               else:
                  ch.FATAL("image is architecture-unaware",
                           "consider --arch=yolo")
         # manifest
         self.manifest_load(have_skinny)
      except ch.Image_Unavailable_Error:
         if (ch.user() == "qwofford"):
            h = "Quincy, use --auth!!"
         else:
            h = "if your registry needs authentication, use --auth"
         ch.FATAL("unauthorized or not in registry: %s" % self.registry.ref, h)
      # config
      ch.VERBOSE("config path: %s" % self.config_path)
      if (self.config_path is not None):
         if (os.path.exists(self.config_path) and ch.dlcache_p):
            ch.INFO("config: using existing file")
         else:
            self.registry.blob_to_file(self.config_hash, self.config_path,
                                       "config: downloading")
      # layers
      for (i, lh) in enumerate(self.layer_hashes, start=1):
         path = self.layer_path(lh)
         ch.VERBOSE("layer path: %s" % path)
         msg = "layer %d/%d: %s" % (i, len(self.layer_hashes), lh[:7])
         if (os.path.exists(path) and ch.dlcache_p):
            ch.INFO("%s: using existing file" % msg)
         else:
            self.registry.blob_to_file(lh, path, "%s: downloading" % msg)
      # done
      self.registry.close()

   def error_decode(self, data):
      """Decode first error message in registry error blob and return a tuple
         (code, message)."""
      try:
         code = data["errors"][0]["code"]
         msg = data["errors"][0]["message"]
      except (IndexError, KeyError):
         ch.FATAL("malformed error data", "yes, this is ironic")
      return (code, msg)

   def fatman_load(self):
      """Download the fat manifest and load it. If the image has a fat manifest
         populate self.architectures; this may be an empty dictionary if no
         valid architectures were found.

         Raises:

           * Image_Unavailable_Error if the image does not exist or we are not
             authorized to have it.

           * No_Fatman_Error if the image exists but has no fat manifest,
             i.e., is architecture-unaware. In this case self.architectures is
             set to None."""
      self.architectures = None
      if (str(self.src_ref) in manifests_internal):
         # cheat; internal manifest library matches every architecture
         self.architectures = ch.Arch_Dict({ ch.arch_host: None })
         # Assume that image has no digest. This is a kludge, but it makes my
         # solution to issue #1365 work so ¯\_(ツ)_/¯
         self.digests[ch.arch_host] = "no digest"
         return
      # raises Image_Unavailable_Error if needed
      self.registry.fatman_to_file(self.fatman_path,
                                   "manifest list: downloading")
      fm = self.fatman_path.json_from_file("fat manifest")
      if ("layers" in fm or "fsLayers" in fm):
         # Check for skinny manifest. If not present, create a symlink to the
         # “fat manifest” with the conventional name for a skinny manifest.
         # This works because the file we just saved as the “fat manifest” is
         # actually a misleadingly named skinny manifest. Link is relative to
         # avoid embedding the storage directory path within the storage
         # directory (see PR #1657).
         if (not self.manifest_path.exists_()):
            self.manifest_path.symlink_to(self.fatman_path.name)
         raise ch.No_Fatman_Error()
      if ("errors" in fm):
         # fm is an error blob.
         (code, msg) = self.error_decode(fm)
         if (code == "MANIFEST_UNKNOWN"):
            ch.INFO("manifest list: no such image")
            return
         else:
            ch.FATAL("manifest list: error: %s" % msg)
      self.architectures = ch.Arch_Dict()
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
         self.digests[arch] = digest.split(":")[1]
      if (len(self.architectures) == 0):
         ch.WARNING("no valid architectures found")

   def layer_path(self, layer_hash):
      "Return the path to tarball for layer layer_hash."
      return ch.storage.download_cache // (layer_hash + ".tar.gz")

   def manifest_load(self, have_skinny=False):
      """Download the manifest file, parse it, and set self.config_hash and
         self.layer_hashes. If the image does not exist,
         exit with error."""
      def bad_key(key):
         ch.FATAL("manifest: %s: no key: %s" % (self.manifest_path, key))
      self.config_hash = None
      self.layer_hashes = None
      # obtain the manifest
      try:
         # internal manifest library, e.g. for “FROM scratch”
         manifest = manifests_internal[str(self.src_ref)]
         ch.INFO("manifest: using internal library")
      except KeyError:
         # download the file and parse it
         if (ch.arch == "yolo" or self.architectures is None):
            digest = None
         else:
            digest = self.architectures[ch.arch]
         ch.DEBUG("manifest digest: %s" % digest)
         if (not have_skinny):
            self.registry.manifest_to_file(self.manifest_path,
                                          "manifest: downloading",
                                          digest=digest)
         manifest = self.manifest_path.json_from_file("manifest")
      # validate schema version
      version = self.image.schemaversion_from_manifest(manifest)
      # load config hash
      #
      # FIXME: Manifest version 1 does not list a config blob. It does have
      # things (plural) that look like a config at history/v1Compatibility as
      # an embedded JSON string :P but I haven’t dug into it.
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
      self.layer_hashes = self.image.layer_hash_from_manifest(manifest, version)
      # Remember State_ID input. We can’t rely on the manifest existing in
      # serialized form (e.g. for internal manifests), so re-serialize.
      self.sid_input = json.dumps(manifest, sort_keys=True)

   def manifest_digest_by_arch(self):
      "Return skinny manifest digest for target architecture."
      fatman  = self.fat_manifest_path.json_from_file()
      arch    = None
      digest  = None
      variant = None
      try:
         arch, variant = ch.arch.split("/", maxsplit=1)
      except ValueError:
         arch = ch.arch
      if ("manifests" not in fatman):
         ch.FATAL("manifest list has no manifests")
      for k in fatman["manifests"]:
         if (k.get('platform').get('os') != 'linux'):
            continue
         elif (    k.get('platform').get('architecture') == arch
               and (   variant is None
                    or k.get('platform').get('variant') == variant)):
            digest = k.get('digest')
      if (digest is None):
         ch.FATAL("arch not found for image: %s" % arch,
                  'try "ch-image list IMAGE_REF"')
      return digest

   def unpack(self, last_layer=None):
      layer_paths = [self.layer_path(h) for h in self.layer_hashes]
      self.image.unpack(layer_paths, last_layer)
      self.image.metadata_replace(self.config_path)
      # Check architecture we got. This is limited because image metadata does
      # not store the variant. Move fast and break things, I guess.
      arch_image = self.image.metadata["arch"] or "unknown"
      arch_short = ch.arch.split("/")[0]
      arch_host_short = ch.arch_host.split("/")[0]
      if (arch_image != "unknown" and arch_image != arch_host_short):
         host_mismatch = " (may not match host %s)" % ch.arch_host
      else:
         host_mismatch = ""
      ch.INFO("image arch: %s%s" % (arch_image, host_mismatch))
      if (ch.arch != "yolo" and arch_short != arch_image):
         ch.WARNING("image architecture does not match requested: %s ≠ %s"
                    % (ch.arch, arch_image))
