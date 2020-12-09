import argparse
import atexit
import collections
import collections.abc
import copy
import datetime
import gzip
import getpass
import hashlib
import http.client
import json
import os
import getpass
import pathlib
import random
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import time
import types


## Imports not in standard library ##

# These are messy because we need --version and --help even if a dependency is
# missing. Among other things, nothing can depend on non-standard modules at
# parse time.

# List of dependency problems.
depfails = []

try:
   # Lark is additionally messy because there are two packages on PyPI that
   # provide a "lark" module.
   import lark   # ImportError if no such module
   lark.Visitor  # AttributeError if wrong module
except (ImportError, AttributeError) as x:
   if (isinstance(x, ImportError)):
      depfails.append(("missing", 'Python module "lark-parser"'))
   elif (isinstance(x, AttributeError)):
      depfails.append(("bad", 'found Python module "lark"; need "lark-parser"'))
   else:
      assert False
   # Mock up a lark module so the rest of the file parses.
   lark = types.ModuleType("lark")
   lark.Visitor = object

try:
   import requests
   import requests.auth
   import requests.exceptions
except ImportError:
   depfails.append(("missing", 'Python module "requests"'))
   # Mock up a requests.auth module so the rest of the file parses.
   requests = types.ModuleType("requests")
   requests.auth = types.ModuleType("requests.auth")
   requests.auth.AuthBase = object


## Globals ##

# FIXME: currently set in ch-grow :P
CH_BIN = None
CH_RUN = None

# Logging; set using init() below.
verbose = 0          # Verbosity level. Can be 0, 1, or 2.
log_festoon = False  # If true, prepend pid and timestamp to chatter.
log_fp = sys.stderr  # File object to print logs to.

# Verify TLS certificates? Passed to requests.
tls_verify = True

# This is a general grammar for all the parsing we need to do. As such, you
# must prepend a start rule before use.
GRAMMAR = r"""

/// Image references ///

// Note: Hostnames with no dot and no port get parsed as a hostname, which
// is wrong; it should be the first path component. We patch this error later.
// FIXME: Supposedly this can be fixed with priorities, but I couldn't get it
// to work with brief trying.
image_ref: ir_hostport? ir_path? ir_name ( ir_tag | ir_digest )?
ir_hostport: IR_HOST ( ":" IR_PORT )? "/"
ir_path: ( IR_PATH_COMPONENT "/" )+
ir_name: IR_PATH_COMPONENT
ir_tag: ":" IR_TAG
ir_digest: "@sha256:" HEX_STRING
IR_HOST: /[A-Za-z0-9_.-]+/
IR_PORT: /[0-9]+/
IR_PATH_COMPONENT: /[a-z0-9_.-]+/
IR_TAG: /[A-Za-z0-9_.-]+/

/// Dockerfile ///

// First instruction must be ARG or FROM, but that is not a syntax error.
dockerfile: _NEWLINES? ( directive | comment )* ( instruction | comment )*

?instruction: _WS? ( arg | copy | env | from_ | run | workdir | uns_forever | uns_yet )

directive.2: _WS? "#" _WS? DIRECTIVE_NAME "=" LINE _NEWLINES
DIRECTIVE_NAME: ( "escape" | "syntax" )
comment: _WS? _COMMENT_BODY _NEWLINES
_COMMENT_BODY: /#[^\n]*/

copy: "COPY"i ( _WS option )* _WS ( copy_list | copy_shell ) _NEWLINES
copy_list.2: _string_list
copy_shell: WORD ( _WS WORD )+

arg: "ARG"i _WS ( arg_bare | arg_equals ) _NEWLINES
arg_bare: WORD
arg_equals: WORD "=" ( WORD | STRING_QUOTED )

env: "ENV"i _WS ( env_space | env_equalses ) _NEWLINES
env_space: WORD _WS LINE
env_equalses: env_equals ( _WS env_equals )*
env_equals: WORD "=" ( WORD | STRING_QUOTED )

from_: "FROM"i ( _WS option )* _WS image_ref [ _WS from_alias ] _NEWLINES
from_alias: "AS"i _WS IR_PATH_COMPONENT  // FIXME: undocumented; this is guess

run: "RUN"i _WS ( run_exec | run_shell ) _NEWLINES
run_exec.2: _string_list
run_shell: LINE

workdir: "WORKDIR"i _WS LINE _NEWLINES

uns_forever: UNS_FOREVER _WS LINE _NEWLINES
UNS_FOREVER: ( "EXPOSE"i | "HEALTHCHECK"i | "MAINTAINER"i | "STOPSIGNAL"i | "USER"i | "VOLUME"i )

uns_yet: UNS_YET _WS LINE _NEWLINES
UNS_YET: ( "ADD"i | "CMD"i | "ENTRYPOINT"i | "LABEL"i | "ONBUILD"i | "SHELL"i )

/// Common ///

option: "--" OPTION_KEY "=" OPTION_VALUE
OPTION_KEY: /[a-z]+/
OPTION_VALUE: /[^ \t\n]+/

HEX_STRING: /[0-9A-Fa-f]+/
LINE: ( _LINE_CONTINUE | /[^\n]/ )+
WORD: /[^ \t\n=]/+

_string_list: "[" _WS? STRING_QUOTED ( "," _WS? STRING_QUOTED )* _WS? "]"

_NEWLINES: _WS? "\n"+
_WS: /[ \t]|\\\n/+
_LINE_CONTINUE: "\\\n"

%import common.ESCAPED_STRING -> STRING_QUOTED
"""


## Classes ##

class HelpFormatter(argparse.HelpFormatter):

   def __init__(self, *args, **kwargs):
      # max_help_position is undocumented but I don't know how else to do this.
      #kwargs["max_help_position"] = 26
      super().__init__(max_help_position=26, *args, **kwargs)

   # Suppress duplicate metavar printing when option has both short and long
   # flavors. E.g., instead of:
   #
   #   -s DIR, --storage DIR  set builder internal storage directory to DIR
   #
   # print:
   #
   #   -s, --storage DIR      set builder internal storage directory to DIR
   #
   # From https://stackoverflow.com/a/31124505.
   def _format_action_invocation(self, action):
      if (not action.option_strings or action.nargs == 0):
         return super()._format_action_invocation(action)
      default = self._get_default_metavar_for_optional(action)
      args_string = self._format_args(action, default)
      return ', '.join(action.option_strings) + ' ' + args_string


class Image:
   """Container image object.

      Constructor arguments:

        ref........... Image_Ref object to identify the image.

        unpack_path .. Directory to unpack the image in; if None, infer path
                       in storage dir from ref."""

   __slots__ = ("ref",
                "unpack_path")

   def __init__(self, ref, unpack_path=None):
      assert isinstance(ref, Image_Ref)
      self.ref = ref
      if (unpack_path is not None):
         self.unpack_path = unpack_path
      else:
         self.unpack_path = storage.unpack(self.ref)

   def __str__(self):
      return str(self.ref)

   def commit(self):
      "Commit the current unpack directory into the layer cache."
      assert False, "unimplemented"

   def copy_unpacked(self, other):
      "Copy the unpack directory of Image other to my unpack directory."
      self.unpack_create_ok()
      DEBUG("copying image: %s -> %s" % (other.unpack_path, self.unpack_path))
      copytree(other.unpack_path, self.unpack_path, symlinks=True)

   def fixup(self):
      "Add the Charliecloud workarounds to my unpacked image."
      DEBUG("fixing up image: %s" % self.unpack_path)
      # Metadata directory.
      mkdirs("%s/ch" % self.unpack_path)
      file_ensure_exists("%s/ch/environment" % self.unpack_path)
      # Mount points.
      file_ensure_exists("%s/etc/hosts" % self.unpack_path)
      file_ensure_exists("%s/etc/resolv.conf" % self.unpack_path)
      for i in range(10):
         mkdirs("%s/mnt/%d" % (self.unpack_path, i))

   def flatten(self, layer_tars, last_layer=None):
      """Unpack layer_tars (sequence of paths to tarballs, with lowest layer
         first) into the unpack directory, validating layer contents and
         dealing with whiteouts. Empty layers are ignored."""
      if (last_layer is None):
         last_layer = sys.maxsize
      layers = self.layers_open(layer_tars)
      self.validate_members(layers)
      self.whiteouts_resolve(layers)
      INFO("flattening image")
      self.unpack_create()
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         lh_short = lh[:7]
         if (i > last_layer):
            INFO("layer %d/%d: %s: skipping per --last-layer"
                 % (i, len(layers), lh_short))
         else:
            INFO("layer %d/%d: %s: extracting" % (i, len(layers), lh_short))
            try:
               fp.extractall(path=self.unpack_path, members=members)
            except OSError as x:
               FATAL("can't extract layer %d: %s" % (i, x.strerror))

   def layers_open(self, layer_tars):
      """Open the layer tarballs and read some metadata (which unfortunately
         means reading the entirety of every file). Return an OrderedDict:

           keys:    layer hash (full)
           values:  namedtuple with two fields:
                      fp:       open TarFile object
                      members:  sequence of members (OrderedSet)

         Empty layers are skipped.

         Important note: TarFile.extractall() extracts the given members in
         the order they are specified, so we need to preserve their order from
         the file, as returned by getmembers(). We also need to quickly remove
         members we don't want from this sequence. Thus, we use the OrderedSet
         class defined in this module."""
      TT = collections.namedtuple("TT", ["fp", "members"])
      layers = collections.OrderedDict()
      # Schema version one (v1) allows one or more empty layers for Dockerfile
      # entries like CMD (https://github.com/containers/skopeo/issues/393).
      # Unpacking an empty layer doesn't accomplish anything so we ignore them.
      empty_cnt = 0
      for (i, path) in enumerate(layer_tars, start=1):
         lh = os.path.basename(path).split(".", 1)[0]
         lh_short = lh[:7]
         INFO("layer %d/%d: %s: listing" % (i, len(layer_tars), lh_short))
         try:
            fp = TarFile.open(path)
            members = OrderedSet(fp.getmembers())  # reads whole file :(
         except tarfile.TarError as x:
            FATAL("cannot open: %s: %s" % (path, x))
         if (lh in layers and len(members) > 0):
            FATAL("duplicate non-empty layer %s" % lh)
         if (len(members) > 0):
            layers[lh] = TT(fp, members)
         else:
            empty_cnt += 1
      DEBUG("skipped %d empty layers" % empty_cnt)
      return layers

   def validate_members(self, layers):
      INFO("validating tarball members")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         dev_ct = 0
         members2 = list(members)  # copy b/c we'll alter members
         for m in members2:
            self.validate_tar_path(fp.name, m.name)
            if (m.isdev()):
               # Device or FIFO: Ignore.
               dev_ct += 1
               members.remove(m)
            elif (m.issym()):
               # Symlink: Nothing to change, but accept it.
               pass
            elif (m.islnk()):
               # Hard link: Fail if pointing outside top level. (Note that we
               # let symlinks point wherever they want, because they aren't
               # interpreted until run time in a container.)
               self.validate_tar_link(fp.name, m.name, m.linkname)
            elif (m.isdir()):
               # Directory: Fix bad permissions (hello, Red Hat).
               m.mode |= 0o700
            elif (m.isfile()):
               # Regular file: Fix bad permissions (HELLO RED HAT!!).
               m.mode |= 0o600
            else:
               FATAL("unknown member type: %s" % m.name)
         if (dev_ct > 0):
            INFO("layer %d/%d: %s: ignored %d devices and/or FIFOs"
                 % (i, len(layers), lh[:7], dev_ct))

   def validate_tar_path(self, filename, path):
      "Reject paths outside the tar top level by aborting the program."
      if (len(path) > 0 and path[0] == "/"):
         FATAL("rejecting absolute path: %s: %s" % (filename, path))
      if (".." in path.split("/")):
         FATAL("rejecting path with up-level: %s: %s" % (filename, path))

   def validate_tar_link(self, filename, path, target):
      """Reject hard link targets outside the tar top level by aborting the
         program."""
      self.validate_tar_path(filename, path)
      if (len(target) > 0 and target[0] == "/"):
         FATAL("rejecting absolute hard link target: %s: %s -> %s"
               % (filename, path, target))
      if (".." in os.path.normpath(path + "/" + target).split("/")):
         FATAL("rejecting too many up-levels: %s: %s -> %s"
               % (filename, path, target))

   def whiteout_rm_prefix(self, layers, max_i, prefix):
      """Ignore members of all layers from 1 to max_i inclusive that have path
         prefix of prefix. For example, if prefix is foo/bar, then ignore
         foo/bar and foo/bar/baz but not foo/barbaz. Return count of members
         ignored."""
      DEBUG("finding members with prefix: %s" % prefix, v=2)
      prefix = os.path.normpath(prefix)  # "./foo" == "foo"
      ignore_ct = 0
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         if (i > max_i): break
         members2 = list(members)  # copy b/c we'll alter members
         for m in members2:
            if (os.path.commonpath([prefix, m.name]) == prefix):
               ignore_ct += 1
               members.remove(m)
               DEBUG("layer %d/%d: %s: ignoring %s"
                     % (i, len(layers), lh[:7], m.name), v=2)
      return ignore_ct

   def whiteouts_resolve(self, layers):
      """Resolve whiteouts. See:
         https://github.com/opencontainers/image-spec/blob/master/layer.md"""
      INFO("resolving whiteouts")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         wo_ct = 0
         ig_ct = 0
         members2 = list(members)  # copy b/c we'll alter members
         for m in members2:
            dir_ = os.path.dirname(m.name)
            filename = os.path.basename(m.name)
            if (filename.startswith(".wh.")):
               wo_ct += 1
               members.remove(m)
               if (filename == ".wh..wh..opq"):
                  # "Opaque whiteout": remove contents of dir_.
                  DEBUG("found opaque whiteout: %s" % m.name, v=2)
                  ig_ct += self.whiteout_rm_prefix(layers, i - 1, dir_)
               else:
                  # "Explicit whiteout": remove same-name file without ".wh.".
                  DEBUG("found explicit whiteout: %s" % m.name, v=2)
                  ig_ct += self.whiteout_rm_prefix(layers, i - 1,
                                                   dir_ + "/" + filename[4:])
         if (wo_ct > 0):
            DEBUG("layer %d/%d: %s: processed %d whiteouts; %d members ignored"
                  % (i, len(layers), lh[:7], wo_ct, ig_ct))

   def unpack_create_ok(self):
      """Ensure the unpack directory can be created. If the unpack directory
         is already an image, remove it."""
      if (not os.path.exists(self.unpack_path)):
         DEBUG("creating new image: %s" % self.unpack_path)
      else:
         if (not os.path.isdir(self.unpack_path)):
            FATAL("can't flatten: %s exists but is not a directory"
                  % self.unpack_path)
         if (   not os.path.isdir(self.unpack_path + "bin")
             or not os.path.isdir(self.unpack_path + "dev")
             or not os.path.isdir(self.unpack_path + "usr")):
            FATAL("can't flatten: %s exists but does not appear to be an image"
                  % self.unpack_path)
         DEBUG("replacing existing image: %s" % self.unpack_path)
         rmtree(self.unpack_path)

   def unpack_create(self):
      "Ensure the unpack directory exists, replacing or creating if needed."
      self.unpack_create_ok()
      mkdirs(self.unpack_path)


class Image_Upload():
   """Image Upload object.
      layers                dict where k = layer's compressed tarball path and
                            v = list consisting of: uncompressed and compressed
                            image data, e.g., size, and hash
      config                named tuple with config path, size, and digest
      manifest_path         path to generated image manifest
      path                  local image path
      ref                   remote repository reference
   """
   __slots__ = ("layers",
                "config",
                "manifest_path",
                "path",
                "ref",
                "upload_url")

   def __init__(self, path, dest):
      self.layers = None
      self.config = None
      self.manifest_path = None
      self.path = path
      self.ref = dest
      self.upload_url = None

   def archive_fixup(self, tarinfo):
      # FIXME: The uid and gid of "nobody" is not always  65534. The files
      # should be mapped to 0/0 with the following restrictions:
      #    1. no leading '/'
      #    2. no setuid or setguid files
      tarinfo.uid = tarinfo.gid = 65534
      tarinfo.uname = "nobody"
      tarinfo.gname = "nogroup"
      return tarinfo

   def compress_tarball(self, tar, dst):
      with open_(tar, 'rb') as archive:
         data=archive.read()
         with open_(dst, 'wb') as out:
            with  gzip.GzipFile(filename='', mode='wb', compresslevel=9,
                                fileobj=out, mtime=0.) as gz:
               gz.write(data)
         if (not os.path.isfile(dst)):
            FATAL('failed to create compressed archive %s' % dst)

   def compress_tarball_progress(self, tar, dst, total):
      import tqdm
      chunks, r = divmod(total, 32768)
      with open_(tar, 'rb') as archive:
         with open_(dst, 'wb') as out:
            # FIXME: this horror is a proof of concept; perhaps there are better
            # ways to implement the progress bar here.
            with tqdm.tqdm(total=total) as pb:
               with gzip.GzipFile(filename='', mode='a', compresslevel=9,
                                  fileobj=out, mtime=0.) as gz:
                  for i in range(chunks):
                     data = archive.read(32768)
                     gz.write(data)
                     pb.update(32768)
                  if ( r > 0 ):
                     data = archive.read(r)
                     gz.write(data)
                     pb.update(r)
      if (not os.path.isfile(dst)):
         FATAL('failed to create compressed archive %s' % dst)

   def create_tarball(self, image, ulcache):
      "Pack image to tarball, compress it, and store metadata"
      # FIXME: update when (if) we have multiple layers.
      mkdirs(ulcache)
      size  = {'compressed':   None,
               'uncompressed': None}
      hash_ = {'compressed':   None,
               'uncompressed': None}
      name = image.split('/')[-1]
      tar = os.path.join(ulcache, name) + '.tar'
      if os.path.isfile(tar):
         DEBUG("removing %s" % tar)
         os.remove(tar)
      INFO('creating tarball')
      DEBUG('uncompressed tar: %s' % tar)
      # Add image to uncompressed tar archive.
      # FIXME: add tqdm progress bar here.
      with tarfile.open(tar, "w") as archive:
         archive.add(self.path, arcname=None, recursive=True,
                     filter=self.archive_fixup)
      # Store uncompressed layer data.
      hash_['uncompressed'] = 'sha256:%s' % self.get_layer_hash(tar)
      size['uncompressed'] = Path(tar).stat().st_size
      DEBUG('uncompressed digest: %s' % hash_['uncompressed'])
      DEBUG('uncompressed size: %s' % size['uncompressed'])

      gzp = tar + '.gz'
      if (os.path.exists(gzp)):
         os.remove(gzp)
      INFO("compressing tarball")
      DEBUG("compressed tar: %s ..." % gzip)
      try:
         import tqdm
         DEBUG('using tqdm for compression progress')
         self.compress_tarball_progress(tar, gzp, size.get('uncompressed'))
      except (ModuleNotFoundError):
         self.compress_tarball(tar, gzp)

      # Store compressed layer data.
      hash_['compressed'] = 'sha256:%s' % self.get_layer_hash(gzp)
      size['compressed'] = Path(gzp).stat().st_size
      DEBUG('compressed digest: %s' % hash_['compressed'])
      DEBUG('compressed size: %s' % size['compressed'])
      gzp_path = os.path.join(ulcache, hash_['compressed'] + '.tar.gz')
      DEBUG("renaming compressed archive: %s " % gzp_path)
      os.rename(gzp, gzp_path)
      os.remove(tar)
      self.layers = { gzp_path: {'size': size, 'hash': hash_}}

   def get_digest(self, data):
      h = hashlib.sha256()
      h.update(data)
      return "sha256:%s" % h.hexdigest()

   def get_layer_hash(self, archive):
      with open_(archive,"rb") as f:
            encode = hashlib.sha256(f.read()).hexdigest()
      return encode

   def create_config(self, path, ulcache):
      "Create image config"
      mkdirs(ulcache)
      config =  {"architecture": "amd64", #FIXME
                 "comment": "pushed with ch-grow",
                 "config": {}, #FIXME
                 "container_config": {}, #FIXME
                 "created": "" , #FIXME
                 "charliecloud_version": "fixme", # FIXME
                 "history": [], #FIXME
                 "os": "linux",
                 "rootfs": {
                    "diff_ids":[],
                    "type": "layers"}}

      # add layers
      for k in self.layers:
         config['rootfs']['diff_ids'].append(self.layers[k]['hash']['uncompressed'])

      # FIXME: add correct time
      now = datetime.datetime.now()
      config['created'] = now.strftime("%Y-%m-%d %H:%M:%S")

      # Write file
      fp = os.path.join(ulcache, path.split('/')[-1])
      fp += ".config.json"
      with open_(fp, "wt", encoding='utf-8') as f:
         json.dump(config, f)
      json_dump = json.dumps(config)
      config_json = json.loads(json_dump)

      with open_(fp, "rb") as f:
         data = f.read()
         size = len(data)
         digest = self.get_digest(data)
         CT = collections.namedtuple('config', ['path', 'size', 'digest'])
         self.config = CT(fp, size, digest)
      DEBUG('config size: %s' % size)
      DEBUG('config digest: %s' % digest)
      DEBUG("generated config:\n%s" % json.dumps(config, indent=3))

   def create_manifest(self, path, ulcache):
      "Create image manifest json"
      # FIXME: implement ulcache, e.g., "use_cache"?
      mkdirs(ulcache)
      manifest = {"schemaVersion": 2,
                  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
                  "config": {
                     "mediaType":"application/vnd.docker.container.image.v1+json",
                     "size":"",
                     "digest":""},
                  "layers": []}

      # add layers
      archive_media = "application/vnd.docker.image.rootfs.diff.tar.gzip"
      for k,v in self.layers.items():
         manifest['layers'].append({'mediaType': archive_media,
                                 'size': v['size']['compressed'],
                                 'digest': v['hash']['compressed']})
      # add config
      c_path, c_size, c_digest = self.config
      manifest['config']['size'] = c_size
      manifest['config']['digest'] = c_digest

      # Write file
      fp = os.path.join(ulcache, path.split('/')[-1])
      fp += ".manifest.json"
      with open_(fp, "wt", encoding='utf-8') as f:
         json.dump(manifest, f)
         self.manifest_path = fp
      json_dump = json.dumps(manifest)
      manifest_json = json.loads(json_dump)
      DEBUG("generated manfiest:\n%s" % json.dumps(manifest, indent=3))

   def blob_exists(self, upload, digest):
      """Determine if a blob already exists."""
      res = upload.head_blob(digest=digest, auth=upload.auth)
      if (res.status_code == 200):
         return True
      return False

   def push_config(self, upload):
      INFO('pushing config')
      c_path, c_size, c_digest = self.config
      head_url = upload._url_of("blobs", c_digest)
      if (not self.blob_exists(upload, c_digest)):
         self.push_init(upload) # get new upload url
         with open_(c_path, "rb") as f:
            data = f.read()
            res = upload.patch(self.upload_url, data=data,
                               expected_statuses=(202,))
            upload.put(res.headers['Location'] + '&digest=%s' % c_digest,
                       expected_statuses=(201,))
      else:
         INFO('config exists; skipping')

   def push_init(self, upload):
      "Initiate upload process and store upload url."
      url = upload._url_of("blobs", "uploads/")
      res = upload.post(url=url, expected_statuses=(202,401))
      self.upload_url = res.headers.get('Location')

   def push_layer(self, path, digest, upload):
      "Push layer to repository via HTTPS PUT request and confirm with HEAD."
      blob_url = upload._url_of("blobs", digest)
      with open_(path, "rb") as f:
         data = f.read()
         upload.put_layer(self.upload_url + "&digest=%s" % digest, data)
      upload.head_blob(blob_url, auth=upload.auth, expected_statuses=(200,301))

   def push_layers(self, upload):
      """Push image layers to repository."""
      for i, path in enumerate(self.layers):
         digest = self.layers[path]['hash']['compressed']
         if (not self.blob_exists(upload, digest)):
            INFO("uploading layer %d/%d: %s" % (i + 1, len(self.layers),
                                                digest.split(':')[-1][:7]))
            self.push_layer(path, digest, upload)
         else:
            INFO("uploading layer %d/%d: %s (exists; skipping)"
                 % (i + 1, len(self.layers), digest.split(':')[-1][:7]))

   def push_manifest(self, upload):
      INFO('pushing manifest')
      with open_(self.manifest_path, 'r', encoding='utf-8') as f:
         data = f.read()
         upload.put_manifest(data=data)

   def push_to_repo(self, path, ulcache):
      """Stage image upload process."""
      self.create_tarball(path, ulcache)
      self.create_config(path, ulcache)
      self.create_manifest(path, ulcache)

      # FIXME: we manage a single upload object to pass around the auth
      # credentials. Probably a better way to handle this.
      ul = Repo_Data_Transfer(self.ref)
      self.push_init(ul)
      self.push_layers(ul)
      self.push_config(ul)
      self.push_manifest(ul)
      ul.close()


class Image_Ref:
   """Reference to an image in a remote repository.

      The constructor takes one argument, which is interpreted differently
      depending on type:

        None or omitted... Build an empty Image_Ref (all fields None).

        string ........... Parse it; see FAQ for syntax. Can be either the
                           standard form (e.g., as in a FROM instruction) or
                           our filename form with percents replacing slashes.

        Lark parse tree .. Must be same result as parsing a string. This
                           allows the parse step to be embedded in a larger
                           parse (e.g., a Dockerfile).

     Warning: References containing a hostname without a dot and no port
     cannot be round-tripped through a string, because the hostname will be
     assumed to be a path component."""

   __slots__ = ("host",
                "port",
                "path",
                "name",
                "tag",
                "digest")

   # Reference parser object. Instantiating a parser took 100ms when we tested
   # it, which means we can't really put it in a loop. But, at parse time,
   # "lark" may refer to a dummy module (see above), so we can't populate the
   # parser here either. We use a class varible and populate it at the time of
   # first use.
   parser = None

   def __init__(self, src=None):
      self.host = None
      self.port = None
      self.path = []
      self.name = None
      self.tag = None
      self.digest = None
      if (isinstance(src, str)):
         src = self.parse(src)
      if (isinstance(src, lark.tree.Tree)):
         self.from_tree(src)
      elif (src is not None):
         assert False, "unsupported initialization type"

   def __str__(self):
      out = ""
      if (self.host is not None):
         out += self.host
      if (self.port is not None):
         out += ":" + str(self.port)
      if (self.host is not None):
         out += "/"
      out += self.path_full
      if (self.tag is not None):
         out += ":" + self.tag
      if (self.digest is not None):
         out += "@sha256:" + self.digest
      return out

   @classmethod
   def parse(class_, s):
      if (class_.parser is None):
         class_.parser = lark.Lark("?start: image_ref\n" + GRAMMAR,
                                   parser="earley", propagate_positions=True)
      if ("%" in s):
         s = s.replace("%", "/")
      try:
         tree = class_.parser.parse(s)
      except lark.exceptions.UnexpectedInput as x:
         FATAL("image ref syntax, char %d: %s" % (x.column, s))
      except lark.exceptions.UnexpectedEOF as x:
         # We get UnexpectedEOF because of Lark issue #237. This exception
         # doesn't have a column location.
         FATAL("image ref syntax, at end: %s" % s)
      DEBUG(tree.pretty(), v=2)
      return tree

   @property
   def as_verbose_str(self):
      def fmt(x):
         if (x is None):
            return None
         else:
            return repr(x)
      return """\
as string:    %s
for filename: %s
fields:
  host    %s
  port    %s
  path    %s
  name    %s
  tag     %s
  digest  %s\
""" % tuple(  [str(self), self.for_path]
            + [fmt(i) for i in (self.host, self.port, self.path,
                                self.name, self.tag, self.digest)])

   @property
   def for_path(self):
      return str(self).replace("/", "%")

   @property
   def path_full(self):
      out = ""
      if (len(self.path) > 0):
         out += "/".join(self.path) + "/"
      out += self.name
      return out

   @property
   def version(self):
      if (self.tag is not None):
         return self.tag
      if (self.digest is not None):
         return "sha256:" + self.digest
      assert False, "version invalid with no tag or digest"

   @property
   def url(self):
      out = ""
      return out

   def copy(self):
      "Return an independent copy of myself."
      return copy.deepcopy(self)

   def defaults_add(self):
      "Set defaults for all empty fields."
      if (self.host is None): self.host = "registry-1.docker.io"
      if (self.port is None): self.port = 443
      if (self.host == "registry-1.docker.io" and len(self.path) == 0):
         # FIXME: For Docker Hub only, images with no path need a path of
         # "library" substituted. Need to understand/document the rules here.
         self.path = ["library"]
      if (self.tag is None and self.digest is None): self.tag = "latest"

   def from_tree(self, t):
      self.host = tree_child_terminal(t, "ir_hostport", "IR_HOST")
      self.port = tree_child_terminal(t, "ir_hostport", "IR_PORT")
      if (self.port is not None):
         self.port = int(self.port)
      self.path = list(tree_child_terminals(t, "ir_path", "IR_PATH_COMPONENT"))
      self.name = tree_child_terminal(t, "ir_name", "IR_PATH_COMPONENT")
      self.tag = tree_child_terminal(t, "ir_tag", "IR_TAG")
      self.digest = tree_child_terminal(t, "ir_digest", "HEX_STRING")
      # Resolve grammar ambiguity for hostnames w/o dot or port.
      if (    self.host is not None
          and "." not in self.host
          and self.port is None):
         self.path.insert(0, self.host)
         self.host = None


class OrderedSet(collections.abc.MutableSet):

   # Note: The superclass provides basic implementations of all the other
   # methods. I didn't evaluate any of these.

   __slots__ = ("data",)

   def __init__(self, others=None):
      self.data = collections.OrderedDict()
      if (others is not None):
         self.data.update((i, None) for i in others)

   def __contains__(self, item):
      return (item in self.data)

   def __iter__(self):
      return iter(self.data.keys())

   def __len__(self):
      return len(self.data)

   def __repr__(self):
      return "%s(%s)" % (self.__class__.__name__, list(iter(self)))

   def add(self, x):
      self.data[x] = None

   def clear(self):
      # Superclass provides an implementation but warns it's slow (and it is).
      self.data.clear()

   def discard(self, x):
      self.data.pop(x, None)


class Path(pathlib.PosixPath):
   """Stock Path objects have the very weird property that appending an
      *absolute* path to an existing path ignores the left operand, leaving
      only the absolute right operand:

        >>> import pathlib
        >>> a = pathlib.Path("/foo/bar")
        >>> a.joinpath("baz")
        PosixPath('/foo/bar/baz')
        >>> a.joinpath("/baz")
        PosixPath('/baz')

      This is contrary to long-standing UNIX/POSIX, where extra slashes in a
      path are ignored, e.g. the path "foo//bar" is equivalent to "foo/bar".
      It seems to be inherited from os.path.join().

      Even with the relatively limited use of Path objects so far, this has
      caused quite a few bugs. IMO it's too difficult and error-prone to
      manually manage whether paths are absolute or relative. Thus, this
      subclass introduces a new operator "+" which does the right thing, i.e.,
      if the right operand is absolute, that fact is ignored. E.g.:

        >>> a = Path("/foo/bar")
        >>> a.joinpath_posix("baz")
        Path('/foo/bar/baz')
        >>> a.joinpath_posix("/baz")
        Path('/foo/bar/baz')
        >>> a + "/baz"
        Path('/foo/bar/baz')
        >>> "/baz" + a
        Path('/baz/foo/bar')

      We introduce a new operator because it seemed like too subtle a change
      to an existing operator, and we disable the old operator (slash) to
      avoid getting burned here in Charliecloud."""

   def __add__(self, right):
      return self.joinpath_posix(right)

   def __radd__(self, left):
      left = Path(left)
      return left.joinpath_posix(self)

   def __truediv__(self, right):
      return NotImplemented

   def __rtruediv__(self, left):
      return NotImplemented

   def joinpath_posix(self, *others):
      others2 = list()
      for other in others:
         other = Path(other)
         if (other.is_absolute()):
            other = other.relative_to("/")
            assert (not other.is_absolute())
         others2.append(other)
      return self.joinpath(*others2)

class Repo_Data_Transfer:
   """Transfers image data to and from a remote image repository via HTTPS.

      Note that with some registries, authentication is required even for
      anonymous downloads of public images. In this case, we just fetch an
      authentication token anonymously."""

   # The repository protocol follows "ask forgiveness" rather than the
   # standard "ask permission". That is, you request the URL you want, and if
   # it comes back 401 (because either it doesn't exist or you're not
   # authenticated), the response contains a WWW-Authenticate header with the
   # information you need to authenticate. AFAICT, this information is not
   # available any other way. This seems awkward to me, because it requires
   # that all requesting code paths have a contingency for authentication.
   # Therefore, we emulate the standard approach instead.

   __slots__ = ("auth",
                "ref",
                "session")

   # https://stackoverflow.com/a/58055668
   class Bearer_Auth(requests.auth.AuthBase):

      __slots__ = ("token",)

      def __init__(self, token):
         self.token = token

      def __call__(self, req):
         req.headers["Authorization"] = "Bearer %s" % self.token
         return req

      def __str__(self):
         return ("Bearer %s" % self.token[:32])

   class Null_Auth(requests.auth.AuthBase):

      def __call__(self, req):
         return req

      def __str__(self):
         return "no authorization"

   def __init__(self, ref):
      # Need an image ref with all the defaults filled in.
      self.ref = ref.copy()
      self.ref.defaults_add()
      self.auth = self.Null_Auth()
      self.session = None
      if (verbose >= 2):
         http.client.HTTPConnection.debuglevel = 1

   def _url_of(self, type_, address):
      "Return an appropriate repository URL."
      url_base = "https://%s:%d/v2" % (self.ref.host, self.ref.port)
      return "/".join((url_base, self.ref.path_full, type_, address))

   def authenticate_basic(self, res, auth_d):
      DEBUG("authenticating using Basic")
      if ("realm" not in auth_d):
         FATAL("WWW-Authenticate missing realm")
      (username, password) = self.credentials_read()
      self.auth = requests.auth.HTTPBasicAuth(username, password)

   def authenticate_bearer(self, res, auth_d):
      DEBUG("authenticating using Bearer")
      for k in ("realm", "service", "scope"):
         if (k not in auth_d):
            FATAL("WWW-Authenticate missing key: %s" % k)
      # First, try for an anonymous auth token. If that fails, try for an
      # authenticated token.
      DEBUG("requesting anonymous auth token")
      res = self.get_raw(auth_d["realm"], [200,403],
                         params={"service": auth_d["service"],
                                 "scope": auth_d["scope"]})
      if (res.status_code == 403):
         INFO("anonymous access rejected")
         (username, password) = self.credentials_read()
         auth = requests.auth.HTTPBasicAuth(username, password)
         res = self.get_raw(auth_d["realm"], [200], auth=auth,
                            params={"service": auth_d["service"],
                                    "scope": auth_d["scope"]})
      token = res.json()["token"]
      DEBUG("received auth token: %s" % (token[:32]))
      self.auth = self.Bearer_Auth(token)

   def authorize(self, res):
      "Authorize using the WWW-Authenticate header in failed response res."
      DEBUG("authorizing")
      assert (res.status_code == 401)
      # Get authentication instructions.
      if ("WWW-Authenticate" not in res.headers):
         FATAL("WWW-Authenticate header not found")
      auth_h = res.headers["WWW-Authenticate"]
      DEBUG("WWW-Authenticate raw: %s" % auth_h)
      # Parse the WWW-Authenticate header. Apparently doing this correctly is
      # pretty hard. We use a non-compliant regex kludge [1,2]. Alternatives
      # include putting the grammar into Lark (this can be gotten by reading
      # the RFCs enough) or using the www-authenticate library [3].
      #
      # [1]: https://stackoverflow.com/a/1349528
      # [2]: https://stackoverflow.com/a/1547940
      # [3]: https://pypi.org/project/www-authenticate
      auth_type = auth_h.split()[0]
      auth_d = dict(re.findall(r'(?:(\w+)[:=] ?"?([\w.~:/?#@!$&()*+,;=\'\[\]-]+)"?)+', auth_h))
      DEBUG("WWW-Authenticate parsed: %s %s" % (auth_type, auth_d))
      # Dispatch to proper method.
      if   (auth_type == "Bearer"):
         self.authenticate_bearer(res, auth_d)
      elif (auth_type == "Basic"):
         self.authenticate_basic(res, auth_d)
      else:
         FATAL("unknown auth type: %s" % auth_h)

   def close(self):
      if (self.session is not None):
         self.session.close()

   def credentials_read(self):
      username = input("Username: ")
      password = getpass.getpass("Password: ")
      return (username, password)

   def get(self, url, path, headers=dict(), statuses=[200]):
      """GET url, passing headers, and write the body of the response to path.
         Use current session if there is one, or start a new one if not.
         Authenticate if needed."""
      DEBUG("GETting: %s" % url)
      self.session_init_maybe()
      DEBUG("auth: %s" % self.auth)
      res = self.get_raw(url, statuses+[401], headers)
      if (res.status_code == 401):
         DEBUG("HTTP 401 unauthorized")
         self.authorize(res)
         DEBUG("retrying with auth: %s" % self.auth)
         res = self.get_raw(url, statuses, headers)
      try:
         fp = open_(path, "wb")
         ossafe(fp.write, "can't write: %s" % path, res.content)
         ossafe(fp.close, "can't close: %s" % path)
      except OSError as x:
         FATAL("can't write: %s: %s" % (path, x))

   def get_layer(self, hash_, path):
      "GET the layer with hash hash_ and save it at path."
      # /v1/library/hello-world/blobs/<layer-hash>
      url = self._url_of("blobs", "sha256:" + hash_)
      accept = "application/vnd.docker.image.rootfs.diff.tar.gzip"
      self.get(url, path, { "Accept": accept })

   def get_manifest(self, path):
      "GET the manifest for the image and save it at path."
      url = self._url_of("manifests", self.ref.version)
      accept = "application/vnd.docker.distribution.manifest.v2+json"
      self.get(url, path, { "Accept": accept })

   def get_raw(self, url, statuses, headers=dict(), auth=None, **kwargs):
      """GET url, expecting a status code in statuses, passing headers.
         self.session must be valid. If auth is None, use self.auth (which
         might also be None). If status is not in statuses, barf with a fatal
         error. Pass kwargs unchanged to requests.session.get()."""
      if (auth is None):
         auth = self.auth
      try:
         res = self.session.get(url, headers=headers, auth=auth, **kwargs)
         if (res.status_code not in statuses):
            FATAL("HTTP GET failed; expected status %s but got %d: %s"
                  % (" or ".join(str(i) for i in statuses),
                     res.status_code, res.reason))
      except requests.exceptions.RequestException as x:
         FATAL("HTTP GET failed: %s" % x)
      # Log the rate limit headers if present.
      for h in ("RateLimit-Limit", "RateLimit-Remaining"):
         if (h in res.headers):
            DEBUG("%s: %s" % (h, res.headers[h]))
      return res

   def head_blob(self, digest, auth=None, expected_statuses=(200,404)):
      """Check if a blob already exists in the repository."""
      url = self._url_of("blobs", digest)
      DEBUG("HEADing %s" % url)
      return self.head_raw(url, auth=auth, expected_statuses=expected_statuses)

   def head_raw(self, url, headers=dict(), auth=None,
                expected_statuses=(200,404), **kwargs):
      """HEAD url, passing headers, with no magic. If auth is None, use
         self.auth (which might also be None). If status is not in
         expected_statuses, barf with a fatal error. Pass kwargs unchanged to
         requests.session.get()."""
      # FIXME: This function is identical to get_raw with the exception of the
      #        expected status 202, the session.post method, and error message.
      if (auth is None):
         auth = self.auth
      try:
         res = self.session.head(url, headers=headers, auth=auth, **kwargs)
         if (res.status_code not in expected_statuses):
            FATAL("HTTP HEAD failed; expected status %s but got %d: %s"
                  % (" or ".join(str(i) for i in expected_statuses),
                     res.status_code, res.reason))
      except requests.exceptions.RequestException as x:
         FATAL("HTTP HEAD failed: %s" % x)
      return res

   def patch(self, url, headers=dict(), data=None, expected_statuses=(202,)):
      DEBUG("PATCHing: %s" % url)
      self.session_init_maybe()
      self.authenticate_maybe(url, 'post') #FIXME, should be 'patch'
      return self.patch_raw(url, data=data, expected_statuses=expected_statuses,
                            headers=headers)

   def patch_raw(self, url, headers=dict(), auth=None,
                expected_statuses=(202,416,), data=None, **kwargs):
      """PATCH url, passing headers, with no magic. If auth is None, use
         self.auth (which might also be None). If status is not in
         expected_statuses, barf with a fatal error. Pass kwargs unchanged to
         requests.session.get()."""
      # FIXME: This function is identical to get_raw with the exception of the
      #        expected status 202, the session.post method, and error message.
      if (auth is None):
         auth = self.auth
      try:
         res = self.session.patch(url, headers=headers, auth=auth, data=data,
                                  **kwargs)
         if (res.status_code not in expected_statuses):
            FATAL("HTTP PATCH failed; expected status %s but got %d: %s"
                  % (" or ".join(str(i) for i in expected_statuses),
                     res.status_code, res.reason))
      except requests.exceptions.RequestException as x:
         FATAL("HTTP PATCH failed: %s" % x)
      return res

   def post(self, url, headers=dict(), data=None, expected_statuses=(200,0)):
      """POST url, passing headers, including athentication and session magic."""
      DEBUG("POSTing: %s" % url)
      self.session_init_maybe()
      self.authenticate_maybe(url, 'post')
      res = self.post_raw(url, headers=headers,
                          expected_statuses=expected_statuses)
      return res

   def post_raw(self, url, headers=dict(), auth=None,
                expected_statuses=(200,), **kwargs):
      """POST url, passing headers, with no magic. If auth is None, use
         self.auth (which might also be None). If status is not in
         expected_statuses, barf with a fatal error. Pass kwargs unchanged to
         requests.session.get()."""
      # FIXME: This function is identical to get_raw with the exception of the
      #        expected status 202, the session.post method, and error message.
      if (auth is None):
         auth = self.auth
      try:
         res = self.session.post(url, headers=headers, auth=auth, **kwargs)
         if (res.status_code not in expected_statuses):
            FATAL("HTTP POST failed; expected status %s but got %d: %s"
                  % (" or ".join(str(i) for i in expected_statuses),
                     res.status_code, res.reason))
      except requests.exceptions.RequestException as x:
         FATAL("HTTP POST failed: %s" % x)
      return res

   def put(self, url, data=None, expected_statuses=(201,), headers=dict()):
      """GET url, passing headers, including authentication and session magic,
         and write the body of the response to path."""
      DEBUG("PUTing: %s" % url)
      self.session_init_maybe()
      self.authenticate_maybe(url, 'post') #FIXME, should be 'put'
      return self.put_raw(url, data=data, expected_statuses=expected_statuses,
                   headers=headers)

   def put_layer(self, url, data):
      "Upload monolithic layer."
      headers = {'Content-Length': str(len(data)),
                 'Content-Type': 'application/octet-stream'}
      self.put(url, headers=headers, data=data)

   def put_manifest(self, data):
      url = self._url_of("manifests", self.ref.tag)
      headers = {'Content-Type': 'application/vnd.docker.distribution.manifest.v2+json',
                 'Content-Length': str(len(data)),
                 'Connection': 'close'}
      res = self.put(url, data=data, headers=headers, expected_statuses=(201,))

   def put_raw(self, url, headers=dict(), auth=None,
                expected_statuses=(200,), **kwargs):
      """PUT url, passing headers, with no magic. If auth is None, use
         self.auth (which might also be None). If status is not in
         expected_statuses, barf with a fatal error. Pass kwargs unchanged to
         requests.session.get()."""
      # FIXME: This function is identical to get_raw and put_raw with the
      # exception of HTTP request and error message.
      if (auth is None):
         auth = self.auth
      try:
         res = self.session.put(url, headers=headers, auth=auth, **kwargs)
         if (res.status_code not in expected_statuses):
            FATAL("HTTP PUT failed; expected status %s but got %d: %s"
                  % (" or ".join(str(i) for i in expected_statuses),
                     res.status_code, res.reason))
      except requests.exceptions.RequestException as x:
         FATAL("HTTP PUT failed: %s" % x)
      return res

   def session_init_maybe(self):
      "Initialize session if it's not initialized; otherwise do nothing."
      if (self.session is None):
         DEBUG("initializing session")
         self.session = requests.Session()
         self.session.verify = tls_verify


class Storage:

   """Source of truth for all paths within the storage directory. Do not
      compute any such paths elsewhere!"""

   __slots__ = ("root",)

   def __init__(self, storage_cli):
      self.root = storage_cli
      if (self.root is None):
         self.root = self.root_env()
      if (self.root is None):
         self.root = self.root_default()
      self.root = Path(self.root)

   @property
   def download_cache(self):
      return self.root + "dlcache"

   @property
   def unpack_base(self):
      return self.root + "img"

   @property
   def upload_cache(self):
      return self.root + "ulcache"

   @staticmethod
   def root_default():
      # FIXME: Perhaps we should use getpass.getuser() instead of the $USER
      # environment variable? It seems a lot more robust. But, (1) we'd have
      # to match it in some scripts and (2) it makes the documentation less
      # clear becase we have to explain the fallback behavior.
      try:
         username = os.environ["USER"]
      except KeyError:
         FATAL("can't get username: $USER not set")
      return "/var/tmp/%s/ch-grow" % username

   @staticmethod
   def root_env():
      try:
         return os.environ["CH_GROW_STORAGE"]
      except KeyError:
         return None

   def manifest(self, image_ref):
      return self.download_cache + ("%s.manifest.json" % image_ref.for_path)

   def unpack(self, image_ref):
      return self.unpack_base + image_ref.for_path


class TarFile(tarfile.TarFile):

   # This subclass augments tarfile.TarFile to add safety code. While the
   # tarfile module docs [1] say “do not use this class [TarFile] directly”,
   # they also say “[t]he tarfile.open() function is actually a shortcut” to
   # class method TarFile.open(), and the source code recommends subclassing
   # TarFile [2].
   #
   # It's here because the standard library class has problems with symlinks
   # and replacing one file type with another; see issues #819 and #825 as
   # well as multiple unfixed Python bugs [e.g. 3,4,5]. We work around this
   # with manual deletions.
   #
   # [1]: https://docs.python.org/3/library/tarfile.html
   # [2]: https://github.com/python/cpython/blob/2bcd0fe7a5d1a3c3dd99e7e067239a514a780402/Lib/tarfile.py#L2159
   # [3]: https://bugs.python.org/issue35483
   # [4]: https://bugs.python.org/issue19974
   # [5]: https://bugs.python.org/issue23228

   def clobber(self, targetpath, regulars=False, symlinks=False, dirs=False):
      assert (regulars or symlinks or dirs)
      try:
         st = os.lstat(targetpath)
      except FileNotFoundError:
         # We could move this except clause after all the stat.S_IS* calls,
         # but that risks catching FileNotFoundError that came from somewhere
         # other than lstat().
         st = None
      except OSError as x:
         FATAL("can't lstat: %s" % targetpath, targetpath)
      if (st is not None):
         if (stat.S_ISREG(st.st_mode)):
            if (regulars):
               unlink(targetpath)
         elif (stat.S_ISLNK(st.st_mode)):
            if (symlinks):
               unlink(targetpath)
         elif (stat.S_ISDIR(st.st_mode)):
            if (dirs):
               rmtree(targetpath)
         else:
            FATAL("invalid file type 0%o in previous layer; see inode(7): %s"
                  % (stat.S_IFMT(st.st_mode), targetpath))

   def makedir(self, tarinfo, targetpath):
      # Note: This gets called a lot, e.g. once for each component in the path
      # of the member being extracted.
      DEBUG("makedir: %s" % targetpath, v=2)
      self.clobber(targetpath, regulars=True, symlinks=True)
      super().makedir(tarinfo, targetpath)

   def makefile(self, tarinfo, targetpath):
      DEBUG("makefile: %s" % targetpath, v=2)
      self.clobber(targetpath, symlinks=True, dirs=True)
      super().makefile(tarinfo, targetpath)

   def makelink(self, tarinfo, targetpath):
      DEBUG("makelink: %s -> %s" % (targetpath, tarinfo.linkname), v=2)
      self.clobber(targetpath, regulars=True, symlinks=True, dirs=True)
      super().makelink(tarinfo, targetpath)


## Supporting functions ##

def DEBUG(*args, v=1, **kwargs):
   if (verbose >= v):
      log(color="36m", *args, **kwargs)

def ERROR(*args, **kwargs):
   log(color="31m", prefix="error: ", *args, **kwargs)

def FATAL(*args, **kwargs):
   ERROR(*args, **kwargs)
   sys.exit(1)

def INFO(*args, **kwargs):
   log(*args, **kwargs)

def WARNING(*args, **kwargs):
   log(color="31m", prefix="warning: ", *args, **kwargs)

def ch_run_modify(img, args, env, workdir="/", binds=[], fail_ok=False):
   args = (  [CH_BIN + "/ch-run"]
           + ["-w", "-u0", "-g0", "--no-home", "--no-passwd", "--cd", workdir]
           + sum([["-b", i] for i in binds], [])
           + [img, "--"] + args)
   return cmd(args, env, fail_ok)

def cmd(args, env=None, fail_ok=False):
   DEBUG("environment: %s" % env)
   DEBUG("executing: %s" % args)
   color_set("33m", sys.stdout)
   cp = subprocess.run(args, env=env, stdin=subprocess.DEVNULL)
   color_reset(sys.stdout)
   if (not fail_ok and cp.returncode):
      FATAL("command failed with code %d: %s" % (cp.returncode, args[0]))
   return cp.returncode

def color_reset(*fps):
   for fp in fps:
      color_set("0m", fp)

def color_set(color, fp):
   if (fp.isatty()):
      print("\033[" + color, end="", flush=True, file=fp)

def copy2(src, dst, **kwargs):
   "Wrapper for shutil.copy2() with error checking."
   ossafe(shutil.copy2, "can't copy: %s -> %s" % (src, dst), src, dst, **kwargs)

def copytree(*args, **kwargs):
   "Wrapper for shutil.copytree() that exits the program on the first error."
   shutil.copytree(copy_function=copy2, *args, **kwargs)

def dependencies_check():
   """Check more dependencies. If any dependency problems found, here or above
      (e.g., lark module checked at import time), then complain and exit."""
   for (p, v) in depfails:
      ERROR("%s dependency: %s" % (p, v))
   if (len(depfails) > 0):
      sys.exit(1)

def file_ensure_exists(path):
   fp = open_(path, "a")
   fp.close()

def file_write(path, content, mode=None):
   fp = open_(path, "wt")
   ossafe(fp.write, "can't write: %s" % path, content)
   if (mode is not None):
      ossafe(os.chmod, "can't chmod 0%o: %s" % (mode, path))
   fp.close()

def grep_p(path, rx):
   """Return True if file at path contains a line matching regular expression
      rx, False if it does not."""
   rx = re.compile(rx)
   try:
      with open(path, "rt") as fp:
         for line in fp:
            if (rx.search(line) is not None):
               return True
      return False
   except OSError as x:
      FATAL("error reading %s: %s" % (path, x.strerror))

def init(cli):
   global verbose, log_festoon, log_fp, storage
   # logging
   assert (0 <= cli.verbose <= 2)
   verbose = cli.verbose
   if ("CH_LOG_FESTOON" in os.environ):
      log_festoon = True
   file_ = os.getenv("CH_LOG_FILE")
   if (file_ is not None):
      verbose = max(verbose_, 1)
      log_fp = open_(file_, "at")
   atexit.register(color_reset, log_fp)
   DEBUG("verbose level: %d" % verbose)
   # storage object
   storage = Storage(cli.storage)

def log(*args, color=None, prefix="", **kwargs):
   if (color is not None):
      color_set(color, log_fp)
   if (log_festoon):
      prefix = ("%5d %s  %s"
                % (os.getpid(),
                   datetime.datetime.now().isoformat(timespec="milliseconds"),
                   prefix))
   print(prefix, file=log_fp, end="")
   print(flush=True, file=log_fp, *args, **kwargs)
   if (color is not None):
      color_reset(log_fp)

def mkdirs(path):
   DEBUG("ensuring directory: %s" % path)
   try:
      os.makedirs(path, exist_ok=True)
   except OSError as x:
      ch.FATAL("can't create directory: %s: %s: %s"
               % (path, x.filename, x.strerror))

def open_(path, mode, *args, **kwargs):
   "Error-checking wrapper for open()."
   return ossafe(open, "can't open for %s: %s" % (mode, path),
                 path, mode, *args, **kwargs)

def ossafe(f, msg, *args, **kwargs):
   """Call f with args and kwargs. Catch OSError and other problems and fail
      with a nice error message."""
   try:
      return f(*args, **kwargs)
   except OSError as x:
      FATAL("%s: %s" % (msg, x.strerror))

def rmtree(path):
   if (os.path.isdir(path)):
      DEBUG("deleting directory: %s" % path)
      try:
         shutil.rmtree(path)
      except OSError as x:
         ch.FATAL("can't recursively delete directory %s: %s: %s"
                  % (path, x.filename, x.strerror))
   else:
      assert False, "unimplemented"

def symlink(target, source, clobber=False):
   if (clobber and os.path.isfile(source)):
      unlink(source)
   try:
      os.symlink(target, source)
   except FileExistsError:
      if (not os.path.islink(source)):
         FATAL("can't symlink: source exists and isn't a symlink: %s" % source)
      if (os.readlink(source) != target):
         FATAL("can't symlink: %s exists; want target %s but existing is %s"
               % (source, target, os.readlink(source)))
   except OSError as x:
      ch.FATAL("can't symlink: %s -> %s: %s" % (source, target, x.strerror))

def tree_child(tree, cname):
   """Locate a descendant subtree named cname using breadth-first search and
      return it. If no such subtree exists, return None."""
   return next(tree_children(tree, cname), None)

def tree_child_terminal(tree, cname, tname, i=0):
   """Locate a descendant subtree named cname using breadth-first search and
      return its first child terminal named tname. If no such subtree exists,
      or it doesn't have such a terminal, return None."""
   st = tree_child(tree, cname)
   if (st is not None):
      return tree_terminal(st, tname, i)
   else:
      return None

def tree_child_terminals(tree, cname, tname):
   """Locate a descendant substree named cname using breadth-first search and
      yield the values of its child terminals named tname. If no such subtree
      exists, or it has no such terminals, yield an empty sequence."""
   for d in tree.iter_subtrees_topdown():
      if (d.data == cname):
         return tree_terminals(d, tname)
   return []

def tree_children(tree, cname):
   "Yield children of tree named cname using breadth-first search."
   for st in tree.iter_subtrees_topdown():
      if (st.data == cname):
         yield st

def tree_terminal(tree, tname, i=0):
   """Return the value of the ith child terminal named tname (zero-based), or
      None if not found."""
   for (j, t) in enumerate(tree_terminals(tree, tname)):
      if (j == i):
         return t
   return None

def tree_terminals(tree, tname):
   """Yield values of all child terminals of type type_, or empty list if none
      found."""
   for j in tree.children:
      if (isinstance(j, lark.lexer.Token) and j.type == tname):
         yield j.value

def unlink(path, *args, **kwargs):
   "Error-checking wrapper for os.unlink()."
   ossafe(os.unlink, "can't unlink: %s" % path, path)
