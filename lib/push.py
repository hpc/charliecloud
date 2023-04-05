import json
import os.path

import charliecloud as ch
import build_cache as bu
import image as im
import registry as rg
import version

## Globals ##

cache_upload = None

## Main ##

def main(cli):
   src_ref = im.Reference(cli.source_ref)
   ch.INFO("pushing image:   %s" % src_ref)
   image = im.Image(src_ref, cli.image)
   # FIXME: validate it’s an image using Megan’s new function (PR #908)
   if (not os.path.isdir(image.unpack_path)):
      if (cli.image is not None):
         ch.FATAL("can’t push: %s does not appear to be an image" % cli.image)
      else:
         ch.FATAL("can’t push: no image %s" % src_ref)
   if (cli.image is not None):
      ch.INFO("image path:      %s" % image.unpack_path)
   else:
      ch.VERBOSE("image path:      %s" % image.unpack_path)
   if (cli.dest_ref is not None):
      dst_ref = im.Reference(cli.dest_ref)
      ch.INFO("destination:     %s" % dst_ref)
   else:
      dst_ref = im.Reference(cli.source_ref)

   if (cli.ulcache and isinstance(bu.cache, bu.Disabled_Cache)):
      ch.FATAL("can't cache upload: cache disabled")
   elif (cli.ulcache):
      global cache_upload
      cache_upload = True
   up = Image_Pusher(image, dst_ref)
   up.push()
   ch.done_notify()


## Classes ##


class Image_Pusher:

   __slots__ = ("config",     # sequence of bytes
                "dst_ref",    # destination of upload
                "file_id",    # image file id (git hash or name)
                "image",      # Image object we are uploading
                "layers",     # list of (digest, .tar.gz path) to push, lowest first
                "manifest",   # sequence of bytes
                "registry")   # destination registry

   def __init__(self, image, dst_ref):
      self.config = None
      self.dst_ref = dst_ref
      self.image = image
      self.layers = None
      self.manifest = None
      self.registry = None
      # Use git hash to id image if possible; otherwise use name.
      (sid, git_hash) = bu.cache.find_image(self.image)
      if (git_hash is not None):
         self.file_id = str(git_hash)
      else:
         self.file_id = str(image.name)

   @property
   def path_config(self):
      return ch.storage.upload_cache // (str(self.file_id) + ".config.json")

   @property
   def path_manifest(self):
      return ch.storage.upload_cache // (str(self.file_id) + ".manifest.json")

   @classmethod
   def config_new(class_):
      "Return an empty config, ready to be filled in."
      # FIXME: URL of relevant docs?
      # FIXME: tidy blank/empty fields?
      return { "architecture": ch.arch_host_get(),
               "charliecloud_version": version.VERSION,
               "comment": "pushed with Charliecloud",
               "config": {},
               "container_config": {},
               "created": ch.now_utc_iso8601(),
               "history": [],
               "os": "linux",
               "rootfs": { "diff_ids": [], "type": "layers" },
               "weirdal": "yankovic" }

   @classmethod
   def manifest_new(class_):
      "Return an empty manifest, ready to be filled in."
      return { "schemaVersion": 2,
               "mediaType": rg.TYPES_MANIFEST["docker2"],
               "config": { "mediaType": rg.TYPE_CONFIG,
                           "size": None,
                           "digest": None },
               "layers": [],
               "weirdal": "yankovic" }

   def cleanup(self):
      if (cache_upload is None):
         ch.INFO("cleaning up")
         # Delete the tarballs since we can’t yet cache them.
         for (_, tar_c) in self.layers:
            ch.VERBOSE("deleting tarball: %s" % tar_c)
            tar_c.unlink_()

   def json_from_path(self, path, msg):
      "Attempt to return json from file; otherwise return None"
      if (not path.exists()):
         return None
      try:
         data = path.json_from_file(msg, raise_ok=True)
      except:
         return None
      return data

   def layers_from_json(self, manifest):
      if (manifest is None):
         return None
      try:
         version = manifest['schemaVersion']
         # load layer hashes
         if (version == 1):
            key1 = "fsLayers"
            key2 = "blobSum"
         else:  # version == 2
            key1 = "layers"
            key2 = "digest"
         if (key1 not in manifest):
            raise KeyError
         layers = list()
         for i in manifest[key1]:
            if (key2 not in i):
               raise KeyError
            tar_p = ch.storage.upload_cache // (str(ch.digest_trim(i[key2])) + '.tar.gz')
            if (tar_p.exists()):
               layers.append((tar_p.file_hash(), tar_p))
            else:
               raise KeyError
      except KeyError as msg:
         ch.DEBUG("key error; %s" % msg)
         return None
      return layers

   def prepare(self):
      """Prepare self.image for pushing to self.dst_ref. Return tuple: (list
         of gzipped layer tarball paths, config as a sequence of bytes,
         manifest as a sequence of bytes)."""

      # Initializing an HTTP instance for the registry and doing a 'GET'
      # request right out the gate ensures the user needs to authenticate
      # before we prepare the image for upload (#1426).
      self.registry = rg.HTTP(self.dst_ref)
      self.registry.request("GET", self.registry._url_base)

      # Check for previously prepared; if they exist, use them.
      config = self.json_from_path(self.path_config, 'config')
      manifest = self.json_from_path(self.path_manifest, 'manifest')
      layers = self.layers_from_json(manifest)
      if (config is None or manifest is None or layers is None):
         (config, manifest, layers) = self.prepare_new()

      # Store prepared files?
      self.store_json_maybe(self.path_manifest, manifest)
      self.store_json_maybe(self.path_config, config)

      # Pack it all up and store for upload().
      config_bytes = json.dumps(config, indent=2).encode("UTF-8")
      config_hash = ch.bytes_hash(config_bytes)
      manifest["config"]["size"] = len(config_bytes)
      manifest["config"]["digest"] = "sha256:" + config_hash
      ch.DEBUG("config: %s\n%s" % (config_hash, config_bytes.decode("UTF-8")))
      manifest_bytes = json.dumps(manifest, indent=2).encode("UTF-8")
      ch.DEBUG("manifest:\n%s" % manifest_bytes.decode("UTF-8"))
      self.layers = layers
      self.config = config_bytes
      self.manifest = manifest_bytes

   def prepare_new(self):
      tars_uc = self.image.tarballs_write(ch.storage.upload_cache)
      tars_c = list()
      config = self.config_new()
      manifest = self.manifest_new()
      # Prepare layers.
      for (i, tar_uc) in enumerate(tars_uc, start=1):
         ch.INFO("layer %d/%d: preparing" % (i, len(tars_uc)))
         path_uc = ch.storage.upload_cache // tar_uc
         hash_uc = path_uc.file_hash()
         config["rootfs"]["diff_ids"].append("sha256:" + hash_uc)
         size_uc = path_uc.file_size()
         path_c = path_uc.file_gzip(["-9", "--no-name"])
         tar_c = path_c.name
         hash_c = path_c.file_hash()
         size_c = path_c.file_size()
         if (cache_upload):
            path_c.rename_(str(ch.storage.upload_cache) + "/"  + hash_c + ".tar.gz")
            path_c = ch.storage.upload_cache // (hash_c + ".tar.gz")
         tars_c.append((hash_c, path_c))
         manifest["layers"].append({ "mediaType": rg.TYPE_LAYER,
                                     "size": size_c,
                                     "digest": "sha256:" + hash_c })
      # Prepare metadata.
      ch.INFO("preparing metadata")
      self.image.metadata_load()
      # Environment. Note that this is *not* a dictionary for some reason but
      # a list of name/value pairs separated by equals [1], with no quoting.
      #
      # [1]: https://github.com/opencontainers/image-spec/blob/main/config.md
      config['config']['Env'] = ["%s=%s" % (k, v)
                                 for k, v
                                 in self.image.metadata.get("env", {}).items()]
      # History. Some registries, e.g., Quay, use history metadata for simple
      # sanity checks. For example, when an image’s number of "empty_layer"
      # history entries doesn’t match the number of layers being uploaded,
      # Quay will reject the image upload.
      #
      # This type of error checking is odd as the empty_layer key is optional
      # (https://github.com/opencontainers/image-spec/blob/main/config.md).
      #
      # Thus, to push images built (or pulled) with Charliecloud we ensure the
      # the total number of non-empty layers always totals one (1). To do this
      # we iterate over the history entires backward searching for the first
      # non-empty entry and preserve it; all others are set to empty.
      hist = self.image.metadata["history"]
      non_empty_winner = None
      for i in range(len(hist) - 1, -1, -1):
         if (   "empty_layer" not in hist[i].keys()
             or (    "empty_layer" in hist[i].keys()
                 and not hist[i]["empty_layer"] == True)):
            non_empty_winner = i
            break
      assert(non_empty_winner is not None)
      for i in range(len(hist) - 1):
         if (i != non_empty_winner):
            hist[i]["empty_layer"] = True
      config["history"] = hist
      # Pack it up to go.
      config_bytes = json.dumps(config, indent=2).encode("UTF-8")
      config_hash = ch.bytes_hash(config_bytes)
      manifest["config"]["size"] = len(config_bytes)
      manifest["config"]["digest"] = "sha256:" + config_hash
      ch.DEBUG("config: %s\n%s" % (config_hash, config_bytes.decode("UTF-8")))
      manifest_bytes = json.dumps(manifest, indent=2).encode("UTF-8")
      ch.DEBUG("manifest:\n%s" % manifest_bytes.decode("UTF-8"))
      return (config, manifest, tars_c)

   def push(self):
      self.prepare()
      self.upload()
      self.cleanup()

   def store_json_maybe(self, path, data):
      if (cache_upload is not None):
         with open(path, "w") as fp:
            json.dump(data, fp)

   def upload(self):
      ch.INFO("starting upload")
      for (i, (digest, tarball)) in enumerate(self.layers, start=1):
         self.registry.layer_from_file(digest, tarball,
                                 "layer %d/%d: " % (i, len(self.layers)))
      self.registry.config_upload(self.config)
      self.registry.manifest_upload(self.manifest)
      self.registry.close()
