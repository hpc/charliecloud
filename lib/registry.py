import getpass
import io
import os
import re
import sys
import urllib
import types

import charliecloud as ch


## Hairy imports ##

# Requests is not bundled, so this noise makes the file parse and
# --version/--help work even if it's not installed.
try:
   import requests
   import requests.auth
   import requests.exceptions
except ImportError:
   ch.depfails.append(("missing", 'Python module "requests"'))
   # Mock up a requests.auth module so the rest of the file parses.
   requests = types.ModuleType("requests")
   requests.auth = types.ModuleType("requests.auth")
   requests.auth.AuthBase = object


## Constants ##

# Content types for some stuff we care about.
# See: https://github.com/opencontainers/image-spec/blob/main/media-types.md
TYPES_MANIFEST = \
   {"docker2": "application/vnd.docker.distribution.manifest.v2+json",
    "oci1":    "application/vnd.oci.image.manifest.v1+json"}
TYPES_INDEX = \
   {"docker2": "application/vnd.docker.distribution.manifest.list.v2+json",
    "oci1":    "application/vnd.oci.image.index.v1+json"}
TYPE_CONFIG = "application/vnd.docker.container.image.v1+json"
TYPE_LAYER = "application/vnd.docker.image.rootfs.diff.tar.gzip"

## Globals ##

# Verify TLS certificates? Passed to requests.
tls_verify = True

# True if we talk to registries authenticated; false if anonymously.
auth_p = False


## Classes ##

class Credentials:

   __slots__ = ("password",
                "username")

   def __init__(self):
      self.username = None
      self.password = None

   def get(self):
      # If stored, return those.
      if (self.username is not None):
         username = self.username
         password = self.password
      else:
         try:
            # Otherwise, use environment variables.
            username = os.environ["CH_IMAGE_USERNAME"]
            password = os.environ["CH_IMAGE_PASSWORD"]
         except KeyError:
            # Finally, prompt the user.
            # FIXME: This hangs in Bats despite sys.stdin.isatty() == True.
            try:
               username = input("\nUsername: ")
            except KeyboardInterrupt:
               ch.FATAL("authentication cancelled")
            password = getpass.getpass("Password: ")
         if (not ch.password_many):
            # Remember the credentials.
            self.username = username
            self.password = password
      return (username, password)


class Auth(requests.auth.AuthBase):

   # Every registry request has an “authorization object”. This starts as no
   # authentication at all. If we get HTTP 401 Unauthorized, we try to
   # “escalate” to a higher level of authorization; some classes have multiple
   # escalators that we try in order. Escalation can fail either if
   # authentication fails or there is nothing to escalate to.
   #
   # Class attributes:
   #
   #   anon_p ...... True if the authorization object is anonymous; False if
   #                 it needed authentication.
   #
   #   escalators .. Sequence of classes we can escalate to. Empty if no
   #                 escalation possible. This is actually a property rather
   #                 than a class attribute because it needs to refer to
   #                 classes that may not have been defined when the module is
   #                 created, e.g. classes later in the file, or some can
   #                 escalate to themselves.
   #
   #   auth_p ...... True if appropriate for authenticated mode, False if
   #                 anonymous (i.e., --auth or not, respectively). Everything
   #                 must be one or the other.
   #
   #   scheme ...... Auth scheme string (from WWW-Authenticate header) that
   #                 this class matches.

   __slots__ = ("auth_h_next",)  # WWW-Authenticate header for next escalator

   def __eq__(self, other):
      return (type(self) == type(other))

   @property
   def escalators(self):
      ...

   @classmethod
   def authenticate(class_, creds, auth_d):
      """Authenticate using the given credentials and parsed WWW-Authenticate
         dictionary. Return a new Auth object if successful, None if
         not. The caller is responsible for dealing with the failure."""
      ...

   def escalate(self, reg, res):
      """Escalate to a higher level of authorization. Use the WWW-Authenticate
         header in failed response res if there is one."""
      ch.VERBOSE("escalating from %s" % self)
      assert (res.status_code == 401)
      # Get authentication instructions.
      if ("WWW-Authenticate" in res.headers):
         auth_h = res.headers["WWW-Authenticate"]
      elif (self.auth_h_next is not None):
         auth_h = self.auth_h_next
      else:
         ch.FATAL("don’t know how to authenticate: WWW-Authenticate not found")
      # We use two “undocumented (although very stable and frequently cited)”
      # methods to parse the authentication response header (thanks Andy,
      # i.e., @adrecord on GitHub).
      (auth_scheme, auth_d) = auth_h.split(maxsplit=1)
      auth_d = urllib.request.parse_keqv_list(
                  urllib.request.parse_http_list(auth_d))
      ch.VERBOSE("WWW-Authenticate parsed: %s %s" % (auth_scheme, auth_d))
      # Is escalation possible in principle?
      if (len(self.escalators) == 0):
         ch.FATAL("no further authentication possible, giving up")
      # Try to escalate.
      for class_ in self.escalators:
         if (class_.scheme == auth_scheme):
            if (class_.auth_p != auth_p):
               ch.VERBOSE("skipping %s: auth mode mismatch" % class_.__name__)
            else:
               ch.VERBOSE("authenticating using %s" % class_.__name__)
               auth = class_.authenticate(reg, auth_d)
               if (auth is None):
                  ch.VERBOSE("authentication failed; trying next")
               elif (auth == self):
                  ch.VERBOSE("authentication did not escalate; trying next")
               else:
                  return auth  # success!
      ch.VERBOSE("no authentication left to try")
      return None


class Auth_Basic(Auth):
   anon_p = False
   scheme = "Basic"
   auth_p = True

   __slots__ = ("basic")

   def __call__(self, *args, **kwargs):
      return self.basic(*args, **kwargs)

   def __eq__(self, other):
      return super().__eq__(other) and (self.basic == other.basic)

   def __str__(self):
      return self.basic.__str__()

   @property
   def escalators(self):
      return ()

   @classmethod
   def authenticate(class_, reg, auth_d):
      # Note: Basic does not validate the credentials until we try to use it.
      if ("realm" not in auth_d):
         ch.FATAL("WWW-Authenticate missing realm")
      (username, password) = reg.creds.get()
      i = class_()
      i.basic = requests.auth.HTTPBasicAuth(username, password)
      return i


class Auth_Bearer_IDed(Auth):
   # https://stackoverflow.com/a/58055668
   anon_p = False
   scheme = "Bearer"
   auth_p = True
   variant = "IDed"

   __slots__ = ("auth_d",
                "token")

   def __init__(self, token, auth_d):
      self.token = token
      self.auth_d = auth_d

   def __call__(self, req):
      req.headers["Authorization"] = "Bearer %s" % self.token
      return req

   def __eq__(self, other):
      return super().__eq__(other) and (self.auth_d == other.auth_d)

   def __str__(self):
      return ("Bearer (%s) %s" % (self.__class__.__name__.split("_")[-1],
                                  self.token_short))

   @property
   def escalators(self):
      # One can escalate to an authenticated Bearer with a greater scope. I’m
      # pretty sure this doesn’t create an infinite loop because eventually
      # the token request will fail.
      return (Auth_Bearer_IDed,)

   @property
   def token_short(self):
      return ("%s..%s" % (self.token[:8], self.token[-8:]))

   @classmethod
   def authenticate(class_, reg, auth_d):
      # Registries and endpoints vary in what they put in WWW-Authenticate. We
      # need realm because it's the URL to use for a token. Otherwise, just
      # give back all the keys we got.
      for k in ("realm",):
         if (k not in auth_d):
            ch.FATAL("WWW-Authenticate missing key: %s" % k)
      params = { (k,v) for (k,v) in auth_d.items() if k != "realm" }
      # Request a Bearer token.
      res = reg.request_raw("GET", auth_d["realm"], {200,401,403},
                            auth=class_.token_auth(reg.creds), params=params)
      if (res.status_code != 200):
         ch.VERBOSE("bearer token request rejected")
         return None
      # Create new instance.
      i = class_(res.json()["token"], auth_d)
      ch.VERBOSE("received bearer token: %s" % (i.token_short))
      return i

   @classmethod
   def token_auth(class_, creds):
      """Return a requests.auth.AuthBase object used to authenticate the token
         request."""
      (username, password) = creds.get()
      return requests.auth.HTTPBasicAuth(username, password)


class Auth_Bearer_Anon(Auth_Bearer_IDed):
   anon_p = True
   scheme = "Bearer"
   auth_p = False

   __slots__ = ()

   @property
   def escalators(self):
      return (Auth_Bearer_IDed,)

   @classmethod
   def token_auth(class_, creds):
      # The way to get an anonymous Bearer token is to give no Basic auth
      # header in the token request.
      return None


class Auth_None(Auth):
   anon_p = True
   scheme = None
   #auth_p =   # not meaningful b/c we start here in both modes

   def __call__(self, req):
      return req

   def __str__(self):
      return "no authorization"

   @property
   def escalators(self):
      return (Auth_Basic,
              Auth_Bearer_Anon,
              Auth_Bearer_IDed)


class HTTP:
   """Transfers image data to and from a remote image repository via HTTPS.

      Note that ref refers to the *remote* image. Objects of this class have
      no information about the local image."""

   __slots__ = ("auth",
                "creds",
                "ref",
                "session")

   def __init__(self, ref):
      # Need an image ref with all the defaults filled in.
      self.ref = ref.canonical
      self.auth = Auth_None()
      self.creds = Credentials()
      self.session = None
      # This is commented out because it prints full request and response
      # bodies to standard output (not stderr), which overwhelms the terminal.
      # Normally, a better debugging approach if you need this is to sniff the
      # connection using e.g. mitmproxy.
      #if (verbose >= 2):
      #   http.client.HTTPConnection.debuglevel = 1

   @staticmethod
   def headers_log(hs):
      """Log the headers."""
      # All headers first.
      for h in hs:
         h = h.lower()
         if (h == "www-authenticate"):
            f = ch.VERBOSE
         else:
            f = ch.DEBUG
         f("%s: %s" % (h, hs[h]))
      # Friendly message for Docker Hub rate limit.
      pull_ct = period = left_ct = reason = "???"  # keep as strings
      if ("ratelimit-limit" in hs):
         h = hs["ratelimit-limit"]
         m = re.search(r"^(\d+);w=(\d+)$", h)
         if (m is None):
            WARNING("can’t parse RateLimit-Limit: %s" % h)
         else:
            pull_ct = m[1]
            period = str(int(m[2]) / 3600)  # seconds to hours
      if ("ratelimit-remaining" in hs):
         h = hs["ratelimit-remaining"]
         m = re.search(r"^(\d+);", h)
         if (m is None):
            ch.WARNING("can’t parse RateLimit-Remaining: %s" % h)
         else:
            left_ct = m[1]
      if ("docker-ratelimit-source" in hs):
         h = hs["docker-ratelimit-source"]
         m = re.search(r"^[0-9.a-f:]+$", h)     # IPv4 or IPv6
         if (m is not None):
            reason = m[0]
         else:
            m = re.search(r"^[0-9A-Fa-f-]+$", h)  # user UUID
            if (m is not None):
               reason = "auth"
            else:
               # Overall limits yield HTTP 429 so warning seems legitimate?
               ch.WARNING("can’t parse Docker-RateLimit-Source: %s" % h)
      if (any(i != "???" for i in (pull_ct, period, left_ct))):
         ch.INFO("Docker Hub rate limit: %s pulls left of %s per %s hours (%s)"
                 % (left_ct, pull_ct, period, reason))

   @property
   def _url_base(self):
      return "https://%s:%d/v2/" % (self.ref.host, self.ref.port)

   def _url_of(self, type_, address):
      "Return an appropriate repository URL."
      return self._url_base + "/".join((self.ref.path_full, type_, address))

   def blob_exists_p(self, digest):
      """Return true if a blob with digest (hex string) exists in the
         remote repository, false otherwise."""
      # Gotchas:
      #
      # 1. HTTP 401 means both unauthorized *or* not found, I assume to avoid
      #    information leakage about the presence of stuff one isn't allowed
      #    to see. By the time it gets here, we should be authenticated, so
      #    interpret it as not found.
      #
      # 2. Sometimes we get 301 Moved Permanently. It doesn't bubble up to
      #    here because requests.request() follows redirects. However,
      #    requests.head() does not follow redirects, and it seems like a
      #    weird status, so I worry there is a gotcha I haven't figured out.
      url = self._url_of("blobs", "sha256:%s" % digest)
      res = self.request("HEAD", url, {200,401,404})
      return (res.status_code == 200)

   def blob_to_file(self, digest, path, msg):
      "GET the blob with hash digest and save it at path."
      # /v2/library/hello-world/blobs/<layer-hash>
      url = self._url_of("blobs", "sha256:" + digest)
      sw = ch.Progress_Writer(path, msg)
      self.request("GET", url, out=sw)
      sw.close()

   def blob_upload(self, digest, data, note=""):
      """Upload blob with hash digest to url. data is the data to upload, and
         can be anything requests can handle; if it's an open file, then it's
         wrapped in a Progress_Reader object. note is a string to prepend to
         the log messages; default empty string."""
      ch.INFO("%s%s: checking if already in repository" % (note, digest[:7]))
      # 1. Check if blob already exists. If so, stop.
      if (self.blob_exists_p(digest)):
         ch.INFO("%s%s: already present" % (note, digest[:7]))
         return
      msg = "%s%s: not present, uploading" % (note, digest[:7])
      if (isinstance(data, io.IOBase)):
         data = ch.Progress_Reader(data, msg)
         data.start()
      else:
         ch.INFO(msg)
      # 2. Get upload URL for blob.
      url = self._url_of("blobs", "uploads/")
      res = self.request("POST", url, {202})
      # 3. Upload blob. We do a "monolithic" upload (i.e., send all the
      # content in a single PUT request) as opposed to a "chunked" upload
      # (i.e., send data in multiple PATCH requests followed by a PUT request
      # with no body).
      url = res.headers["Location"]
      res = self.request("PUT", url, {201}, data=data,
                         params={ "digest": "sha256:%s" % digest })
      if (isinstance(data, ch.Progress_Reader)):
         data.close()
      # 4. Verify blob now exists.
      if (not self.blob_exists_p(digest)):
         ch.FATAL("blob just uploaded does not exist: %s" % digest[:7])

   def close(self):
      if (self.session is not None):
         self.session.close()

   def config_upload(self, config):
      "Upload config (sequence of bytes)."
      self.blob_upload(ch.bytes_hash(config), config, "config: ")

   def escalate(self, res):
      "Try to escalate authorization; return True if successful, else False."
      auth = self.auth.escalate(self, res)
      if (auth is None):
         return False
      else:
         self.auth = auth
         return True

   def fatman_to_file(self, path, msg):
      """GET the manifest for self.image and save it at path. This seems to
         have four possible results:

            1. HTTP 200, and body is a fat manifest: image exists and is
               architecture-aware.

            2. HTTP 200, but body is a skinny manifest: image exists but is
               not architecture-aware.

            3. HTTP 401/404: image does not exist or is unauthorized.

            4. HTTP 429: rate limite exceeded.

         This method raises Image_Unavailable_Error in case 3. The caller is
         responsible for distinguishing cases 1 and 2."""
      url = self._url_of("manifests", self.ref.version)
      pw = ch.Progress_Writer(path, msg)
      # Including TYPES_MANIFEST avoids the server trying to convert its v2
      # manifest to a v1 manifest, which currently fails for images
      # Charliecloud pushes. The error in the test registry is “empty history
      # when trying to create schema1 manifest”.
      accept = "%s;q=0.5" % ",".join(  list(TYPES_INDEX.values())
                                     + list(TYPES_MANIFEST.values()))
      res = self.request("GET", url, out=pw, statuses={200, 401, 404, 429},
                         headers={ "Accept" : accept })
      pw.close()
      if (res.status_code == 429):
         if (self.auth.anon_p):
            hint = "consider --auth"
         else:
            hint = None
         ch.FATAL("registry rate limit exceeded (HTTP 429)", hint)
      elif (res.status_code != 200):
         ch.DEBUG(res.content)
         raise ch.Image_Unavailable_Error()

   def layer_from_file(self, digest, path, note=""):
      "Upload gzipped tarball layer at path, which must have hash digest."
      # NOTE: We don't verify the digest b/c that means reading the whole file.
      ch.VERBOSE("layer tarball: %s" % path)
      fp = path.open_("rb") # open file avoids reading it all into memory
      self.blob_upload(digest, fp, note)
      ch.close_(fp)

   def manifest_to_file(self, path, msg, digest=None):
      """GET manifest for the image and save it at path. If digest is given,
         use that to fetch the appropriate architecture; otherwise, fetch the
         default manifest using the exising image reference."""
      if (digest is None):
         digest = self.ref.version
      else:
         digest = "sha256:" + digest
      url = self._url_of("manifests", digest)
      pw = ch.Progress_Writer(path, msg)
      accept = "%s;q=0.5" % ",".join(TYPES_MANIFEST.values())
      res = self.request("GET", url, out=pw, statuses={200, 401, 404},
                         headers={ "Accept" : accept })
      pw.close()
      if (res.status_code != 200):
         ch.DEBUG(res.content)
         raise ch.Image_Unavailable_Error()

   def manifest_upload(self, manifest):
      "Upload manifest (sequence of bytes)."
      # Note: The manifest is *not* uploaded as a blob. We just do one PUT.
      ch.INFO("manifest: uploading")
      url = self._url_of("manifests", self.ref.tag)
      self.request("PUT", url, {201}, data=manifest,
                   headers={ "Content-Type": TYPES_MANIFEST["docker2"] })

   def request(self, method, url, statuses={200}, out=None, **kwargs):
      """Request url using method and return the response object. If statuses
         is given, it is set of acceptable response status codes, defaulting
         to {200}; any other response is a fatal error. If out is given,
         response content will be streamed to this Progress_Writer object and
         must be non-zero length.

         Use current session if there is one, or start a new one if not. If
         authentication fails (or isn't initialized), then authenticate harder
         and re-try the request."""
      # Set up.
      self.session_init_maybe()
      ch.VERBOSE("auth: %s" % self.auth)
      if (out is not None):
         kwargs["stream"] = True
      # Make the request.
      while True:
         res = self.request_raw(method, url, statuses | {401}, **kwargs)
         if (res.status_code != 401):
            break
         else:
            ch.VERBOSE("HTTP 401 unauthorized")
            if (self.escalate(res)):   # success
               ch.VERBOSE("retrying with auth: %s" % self.auth)
            elif (401 in statuses):    # caller can deal with it
               break
            else:
               ch.FATAL("unhandled authentication failure")
      # Stream response if needed.
      if (out is not None and res.status_code == 200):
         try:
            length = int(res.headers["Content-Length"])
         except KeyError:
            length = None
         except ValueError:
            ch.FATAL("invalid Content-Length in response")
         out.start(length)
         for chunk in res.iter_content(ch.HTTP_CHUNK_SIZE):
            out.write(chunk)
      # Done.
      return res

   def request_raw(self, method, url, statuses, auth=None, **kwargs):
      """Request url using method. statuses is an iterable of acceptable
         response status codes; any other response is a fatal error. Return
         the requests.Response object.

         Session must already exist. If auth arg given, use it; otherwise, use
         object's stored authentication if initialized; otherwise, use no
         authentication."""
      ch.VERBOSE("%s: %s" % (method, url))
      if (auth is None):
         auth = self.auth
      try:
         res = self.session.request(method, url, auth=auth, **kwargs)
         ch.VERBOSE("response status: %d" % res.status_code)
         self.headers_log(res.headers)
         if (res.status_code not in statuses):
            ch.FATAL("%s failed; expected status %s but got %d: %s"
                  % (method, statuses, res.status_code, res.reason))
      except requests.exceptions.RequestException as x:
         ch.FATAL("%s failed: %s" % (method, x))
      return res

   def session_init_maybe(self):
      "Initialize session if it's not initialized; otherwise do nothing."
      if (self.session is None):
         ch.VERBOSE("initializing session")
         self.session = requests.Session()
         self.session.verify = tls_verify
