# shellcheck shell=bash
# shellcheck disable=SC2164

# Install conditional packages.
if [[ -z "$MINIMAL_DEPS" ]]; then
    sudo apt-get install pigz pv skopeo squashfuse
fi
if [[ $CH_BUILDER = ch-grow ]]; then
    sudo apt-get install skopeo
    sudo pip3 install lark-parser
fi

# Project Atomic PPA provides buggy Buildah for Xenial, and we need Kevin's
# patched version, so build from source.
if [[ $CH_BUILDER = buildah* ]]; then
    add-apt-repository -y ppa:alexlarsson/flatpak
    add-apt-repository -y ppa:gophers/archive
    apt-get -y install libapparmor-dev libdevmapper-dev libglib2.0-dev \
                       libgpgme11-dev libostree-dev libseccomp-dev \
                       libselinux1-dev skopeo-containers go-md2man
    apt-get -y install golang-1.10
    command -v go && go --version
    mkdir /usr/local/src/go
    cd /usr/local/src/go
    export GOPATH=$PWD
    git clone https://github.com/containers/buildah \
              src/github.com/containers/buildah
    cd src/github.com/containers/buildah
    git checkout v1.9.0
    make runc all SECURITYTAGS="apparmor seccomp"
    sudo make install install.runc
    command -v buildah && buildah --version
    command -v runc && runc --version
    cat <<'EOF' > /etc/containers/registries.conf
[registries.search]
  registries = ['docker.io']
EOF
fi

# umoci provides a binary build; no appropriate Ubuntu package for Xenial.
if [[ -z $MINIMAL_DEPS || $CH_BUILDER = ch-grow ]]; then
    wget -nv https://github.com/openSUSE/umoci/releases/download/v0.4.4/umoci.amd64
    sudo chmod 755 umoci.amd64
    sudo mv umoci.amd64 /usr/local/bin/umoci
    umoci --version
fi

# We need Python 3 because Sphinx 1.8.0 doesn't work right under Python 2 (see
# issue #241). Travis provides images pre-installed with Python 3, but it's in
# a virtualenv and unavailable by default under sudo, in package builds, and
# maybe elsewhere. It's simpler and fast enough to install it with apt-get.
if [[ -z $MINIMAL_DEPS ]]; then
    sudo pip3 install sphinx sphinx-rtd-theme
fi
