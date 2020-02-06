#!/usr/bin/python3

# Library for common ch-grow and ch-pull functions.

import collections
import logging
import json
import os
import re
import requests
import shutil
import sys
import tarfile

from hashlib import sha256
from http.client import HTTPConnection

## Globals ##
session = requests.Session()

## Constants ##

# FIXME: move these to defaults; add argument handling
registryBase = 'https://registry-1.docker.io'
authBase     = 'https://auth.docker.io'
authService  = 'registry.docker.io'

# Accepted Docker V2 media types. See
# https://docs.docker.com/registry/spec/manifest-v2-2/
# FIXME: We only use MF_SCHEMA2 and LAYERS in this script, do we care about
# declaring the others for future work?
MF_SCHEMA1 = 'application/vnd.docker.distribution.manifest.v1+json'
MF_SCHEMA2 = 'application/vnd.docker.distribution.manifest.v2+json'
MF_LIST    = 'application/vnd.docker.distribution.manifest.list.v2+json'
C_CONFIG   = 'application/vnd.docker.container.image.v1+json'
LAYER      = 'application/vnd.docker.image.rootfs.diff.tar.gzip'
PLUGINS    = 'application/vnd.docker.plugin.v1+json'

PROXIES = { "HTTP_PROXY":  os.environ.get("HTTP_PROXY"),
            "HTTPS_PROXY": os.environ.get("HTTPS_PROXY"),
            "FTP_PROXY":   os.environ.get("FTP_PROXY"),
            "NO_PROXY":    os.environ.get("NO_PROXY"),
            "http_proxy":  os.environ.get("http_proxy"),
            "https_proxy": os.environ.get("https_proxy"),
            "ftp_proxy":   os.environ.get("ftp_proxy"),
            "no_proxy":    os.environ.get("no_proxy"),
}



## Classes ##

class Image:
    def __init__(self, string):
        # FIXME: Take some string and split into proper components.
        #
        # IMAGE[:TAG][@DIGEST], where IMAGE is the image name, TAG is the image
        # tag, and DIGEST is an algorithm and hash deliminated by a colon. Key
        # examples:
        #   1. hello-world
        #   2. hellow-world:latest
        #   3. hello-world@sha256:(some hash)
        #   4. hello-world:latest@sha256:(some hash)
        #   5. library/hello-world
        #   6. library/hello-world:latest
        #   7. library/hello-world@sha256:(some hash)
        #   8. library/hello-world:latest@sha256:(some hash)
        #
        # In key examples 1-4 we would need to append `library/` to the image
        # name to resolve the GET request.
        #
        # FIXME: what about ports?
        self.name = string.split(':')[0]
        self.tag  = string.split(':')[-1]
        self.reference = self.tag

    def download(self, dst):
        self.session  = MySession(self)
        self.manifest = self.data_fetch('manifests',
                                        MF_SCHEMA2,
                                        self.reference)

        print("downloading image '{}:{}' ...".format(self.name, self.tag))

        # Store manifest file as
        # CH_GROW_STORAGE/manifests/IMAGE:TAG/manifest.json. Note: IMAGE itself
        # can be a parent directory, for example the image
        # 'charliecloud/whiteout:2020-01-10` manifest would be written as:
        # /var/tmp/ch-grow/manifests/charliecloud/whiteout:2020-01-10/HASH
        mdir = os.path.join(dst, 'manifests/{}:{}'.format(self.name,
                                                          self.tag))
        if not os.path.isdir(mdir):
            os.makedirs(mdir)
        os.chdir(mdir)
        open(os.path.join(mdir,
                          'manifest.json'), 'wb').write(self.manifest.content)

        # Make layers directory.
        ldir = os.path.join(dst, 'layers')
        if not os.path.isdir(ldir):
            os.makedirs(ldir)
        os.chdir(ldir)

        # Pull layer from repository if absent from the layers dir.
        for layer in self.manifest.json().get('layers'):
            name = layer.get('digest').split('sha256:')[-1]
            if not os.path.exists(name):
                INFO("fetching layer '{}'".format(name))
                request = self.data_fetch('blobs', 'layer', layer.get('digest'))
                open(name, 'wb').write(request.content)
                if not tarfile.is_tarfile(name):
                    FATAL("'{}' does not appear to be a tarfile".format(layer))

    def data_fetch(self, branch, media, reference):
        self.session.headers.update({ 'Accept': media })
        URL = "{}/v2/{}/{}/{}".format(registryBase,
                                      self.name,
                                      branch,
                                      reference)
        #DEBUG("GET {}".format(URL))
        #DEBUG('{}'.format(self.session.headers))
        try:
            response = session.get(URL,
                                   headers=self.session.headers,
                                   proxies=PROXIES)
            response.raise_for_status()
        except requests.HTTPError as http_err:
            FATAL('HTTP error: {}'.format(http_err))
        except Exception as err:
            FATAL('non HTTP error occured: {}'.format(err))
        return response

    def unpack(self, dst):
        mdir = os.path.join(dst, 'manifests/{}:{}'.format(self.name, self.tag))

        # Download image if manifest doesn't exist locally.
        if not os.path.exists(os.path.join(mdir, 'manifest.json')):
            self.download(dst)

        print("unpacking image '{}:{}' ...".format(self.name, self.tag))

        ldir = os.path.join(dst, 'layers')
        if not os.path.isdir(ldir):
            os.makedirs(ldir)
        os.chdir(ldir)

        # Read manifest layer list; create a dict of key-value pairs where
        # k = layer hash and v = a tarfile object.
        mf_json   = json.load(open(os.path.join(mdir, 'manifest.json'), 'r'))
        layers_d  = dict()
        for layer in mf_json.get('layers'):
            layer = layer.get('digest')
            tar = layer.split('sha256:')[-1] # exclude algorithm
            if not os.path.exists(tar):
                FATAL("{} doesn't exist".format(tar))
            if not tarfile.is_tarfile(tar):
                FATAL("{} is not a valid tar archive".format(tar))
            tf = tarfile.open(tar, 'r')
            layers_d.update({tar : tf})

        imgdir = os.path.join(dst, 'img/{}:{}'.format(self.name, self.tag))
        if os.path.isdir(imgdir):
            INFO("replacing image {}:{}".format(self.name, self.tag))
            shutil.rmtree(imgdir)
        os.makedirs(imgdir)
        os.chdir(imgdir)

        # Iterate through layers; process and unpack to STORAGE/img/IMAGE:TAG.
        # Primary operations: 1) exclude device files; 2) fail if one or more
        # file(s) with a dangerous absolute path is encountered; and 3) remove
        # file target specified by whiteout file in current layer from most recent
        # unpacked layer in STORAGE/img/IMAGE:TAG.
        dev_ct = 0
        wh_ct  = 0
        for k, v in layers_d.items():
            tf_info = v.getmembers()
            tf_members = list()
            for m in tf_info:
                if m.isdev():
                    dev_ct += 1
                    DEBUG('ignoring device file {}'.format(m.name))
                # FIXME: handle opaque whiteout files
                elif re.search('\.wh\..*', m.name):
                    wh_ct += 1
                    DEBUG('whiteout found: {}'.format(m.name))
                    wh = os.path.basename(m.name)
                    wh_dirname = os.path.dirname(m.name)
                    wh_target = os.path.join(wh_dirname, wh.split('.wh.')[-1])
                    if os.path.exists(wh_target):
                        DEBUG('removing {}'.format(wh_target))
                        if os.path.isdir(wh_target):
                            shutil.rmtree(wh_target)
                        else:
                           os.remove(wh_target)
                    else:
                       FATAL("whiteout target {} doesn't exist".format(wh_target))
                elif re.search('^\.\./.*', m.name) or re.search('^/.*', m.name):
                    FATAL("dangerous extraction path '{}'".format(m.name))
                else:
                    tf_members.append(m)

            INFO('extracting layer {}'.format(k))
            v.extractall(members=tf_members)

        print('image successfully unpacked.')
        if dev_ct > 0:
            INFO("{} device files ignored.".format(dev_ct))
        if wh_ct > 0:
            INFO("{} whiteout files handled.".format(wh_ct))

class MySession:
    def __init__(self, image):
        self.token   = self.get_token(image)
        self.headers = self.get_headers()

    def get_headers(self):
        return {'Authorization': 'Bearer {}'.format(self.token)}

    def get_token(self, image):
        tokenService = '{}/token?service={}'.format(authBase, authService)
        scopeRepo    = '&scope=repository:{}:pull'.format(image.name)
        authURL      = tokenService + scopeRepo
        return session.get(authURL, proxies=PROXIES).json()['token']


## Supporting functins ##

def DEBUG(*args, **kwargs):
    color("36m", sys.stderr)
    print(flush=True, file=sys.stderr, *args, **kwargs)
    color_reset(sys.stderr)

def ERROR(*args, **kwargs):
    color("31m", sys.stderr)
    print(flush=True, file=sys.stderr, *args, **kwargs)
    color_reset(sys.stderr)

def FATAL(*args, **kwargs):
    ERROR(*args, **kwargs)
    sys.exit(1)

def INFO(*args, **kwargs):
        print(flush=True, *args, **kwargs)

def color(color, fp):
    if (fp.isatty()):
        print("\033[" + color, end="", flush=True, file=fp)

def color_reset(*fps):
    for fp in fps:
        color("0m", fp)

def log():
    logging.basicConfig(format='%(levelname)s:%(message)s')
    HTTPConnection.debuglevel = 1
    logging.getLogger().setLevel(logging.DEBUG)
    rlog = logging.getLogger("requests.packages.urllib3").setLevel(logging.DEBUG)
