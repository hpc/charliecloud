import json
import os.path

import charliecloud as ch
import version


## Main ##

def main(cli):
   src_ref = ch.Image_Ref(cli.source_ref)
   ch.INFO("pushing image:   %s" % src_ref)
   image = ch.Image(src_ref, cli.image)
   # FIXME: validate it's an image using Megan's new function (PR #908)
   if (not os.path.isdir(image.unpack_path)):
      if (cli.image is not None):
         ch.FATAL("can't push: %s does not appear to be an image" % cli.image)
      else:
         ch.FATAL("can't push: no image %s" % src_ref)
   if (cli.image is not None):
      ch.INFO("image path:      %s" % image.unpack_path)
   else:
      ch.VERBOSE("image path:      %s" % image.unpack_path)
   if (cli.dest_ref is not None):
      dst_ref = ch.Image_Ref(cli.dest_ref)
      ch.INFO("destination:     %s" % dst_ref)
   else:
      dst_ref = ch.Image_Ref(cli.source_ref)
   up = Image_Pusher(image, dst_ref)
   up.push()
   ch.done_notify()


## Classes ##

class Image_Pusher:

   # Note; We use functions to create the blank config and manifest to to
   # avoid copy/deepcopy complexity from just copying a default dict.

   __slots__ = ("config",    # sequence of bytes
                "dst_ref",   # destination of upload
                "image",     # Image object we are uploading
                "layers",    # list of (digest, .tar.gz path), lowest first
                "manifest")  # sequence of bytes

   def __init__(self, image, dst_ref):
      self.config = None
      self.dst_ref = dst_ref
      self.image = image
      self.layers = None
      self.manifest = None

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
               "mediaType": ch.TYPES_MANIFEST["docker2"],
               "config": { "mediaType": ch.TYPE_CONFIG,
                           "size": None,
                           "digest": None },
               "layers": [],
               "weirdal": "yankovic" }

   def cleanup(self):
      ch.INFO("cleaning up")
      # Delete the tarballs since we can't yet cache them.
      for (_, tar_c) in self.layers:
         ch.VERBOSE("deleting tarball: %s" % tar_c)
         ch.unlink(tar_c)

   def prepare(self):
      """Prepare self.image for pushing to self.dst_ref. Return tuple: (list
         of gzipped layer tarball paths, config as a sequence of bytes,
         manifest as a sequence of bytes).

         There is not currently any support for re-using any previously
         prepared files already in the upload cache, because we don't yet have
         a way to know if these have changed until they are already build."""
      tars_uc = self.image.tarballs_write(ch.storage.upload_cache)
      tars_c = list()
      config = self.config_new()
      manifest = self.manifest_new()
      # Prepare layers.
      for (i, tar_uc) in enumerate(tars_uc, start=1):
         ch.INFO("layer %d/%d: preparing" % (i, len(tars_uc)))
         path_uc = ch.storage.upload_cache // tar_uc
         hash_uc = ch.file_hash(path_uc)
         config["rootfs"]["diff_ids"].append("sha256:" + hash_uc)
         #size_uc = ch.file_size(path_uc)
         path_c = ch.file_gzip(path_uc, ["-9", "--no-name"])
         tar_c = path_c.name
         hash_c = ch.file_hash(path_c)
         size_c = ch.file_size(path_c)
         tars_c.append((hash_c, path_c))
         manifest["layers"].append({ "mediaType": ch.TYPE_LAYER,
                                     "size": size_c,
                                     "digest": "sha256:" + hash_c })
      # Prepare metadata.
      ch.INFO("preparing metadata")
      self.image.metadata_load()
      hist = self.image.metadata["history"]
      # Some registries, e.g., Quay, use history metadata for simple sanity
      # checks. For example, when an image's number of "empty_layer" history
      # entries doesn't match the number of layers being uploaded, Quay will
      # reject the image upload.
      #
      # This type of error checking is odd as the empty_layer key is optional
      # (https://github.com/opencontainers/image-spec/blob/main/config.md).
      #
      # Thus, to push images built (or pulled) with Charliecloud we ensure the
      # the total number of non-empty layers always totals one (1). To do this
      # we iterate over the history entires backward searching for the first
      # non-empty entry and preserve it; all others are set to empty.
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
      config_bytes = json.dumps(config, indent=2).encode("UTF-8")
      config_hash = ch.bytes_hash(config_bytes)
      manifest["config"]["size"] = len(config_bytes)
      manifest["config"]["digest"] = "sha256:" + config_hash
      ch.DEBUG("config: %s\n%s" % (config_hash, config_bytes.decode("UTF-8")))
      manifest_bytes = json.dumps(manifest, indent=2).encode("UTF-8")
      ch.DEBUG("manifest:\n%s" % manifest_bytes.decode("UTF-8"))
      # Store for the next steps.
      self.layers = tars_c
      self.config = config_bytes
      self.manifest = manifest_bytes

   def push(self):
      self.prepare()
      self.upload()
      self.cleanup()

   def upload(self):
      ch.INFO("starting upload")
      ul = ch.Registry_HTTP(self.dst_ref)
      for (i, (digest, tarball)) in enumerate(self.layers, start=1):
         ul.layer_from_file(digest, tarball,
                            "layer %d/%d: " % (i, len(self.layers)))
      ul.config_upload(self.config)
      ul.manifest_upload(self.manifest)
      ul.close()
