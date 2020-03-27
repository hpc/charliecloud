# shellcheck shell=bash

set -ex

# Make /usr/local/src writeable for everyone.
sudo chmod 1777 /usr/local/src

# Remove Travis Bats. We need buggy version provided by Ubuntu (issue #552).
sudo rm /usr/local/bin/bats

# Allow sudo to user root, group non-root.
sudo sed -Ei 's/=\(ALL\)/=(ALL:ALL)/g' /etc/sudoers.d/travis
sudo cat /etc/sudoers.d/travis

# Install conditional packages.
if [[ "$MINIMAL_DEPS" ]]; then
    PACK_FMT=tar
else
    sudo apt-get install pigz pv skopeo
fi
if [[ $CH_BUILDER = ch-grow ]]; then
    sudo pip3 install lark-parser requests
fi
case $PACK_FMT in
    '')  # default
        export CH_PACK_FMT=squash
        sudo apt-get install squashfs-tools squashfuse
        ;;
    squash-unpack)
        export CH_PACK_FMT=squash
        sudo apt-get install squashfs-tools
        ;;
    tar)
        export CH_PACK_FMT=tar
        # tar already installed
        ;;
    *)
        echo "unknown \$PACK_FMT: $PACK_FMT" 1>&2
        exit 1
        ;;
esac

# Project Atomic PPA provides buggy Buildah for Xenial, and we need Buildah's
# unprivileged version, so build from source.
if [[ $CH_BUILDER = buildah* ]]; then
    buildah_repo=https://github.com/containers/buildah
    buildah_branch=v1.11.2
    sudo add-apt-repository -y ppa:alexlarsson/flatpak
    sudo apt-get update
    sudo apt-get -y install libapparmor-dev libdevmapper-dev libglib2.0-dev \
                            libgpgme11-dev libostree-dev libseccomp-dev \
                            libselinux1-dev skopeo-containers go-md2man
    sudo apt-get -y install golang-1.10
    sudo apt-get --purge autoremove
    command -v go && go version
    mkdir /usr/local/src/go
    pushd /usr/local/src/go
    export GOPATH=$PWD
    export GOROOT=/usr/lib/go-1.10
    git clone $buildah_repo src/github.com/containers/buildah
    cd src/github.com/containers/buildah
    git checkout $buildah_branch
    PATH=/usr/lib/go-1.10/bin:$PATH make -j $(getconf _NPROCESSORS_ONLN) runc all SECURITYTAGS="apparmor seccomp"
    sudo -E PATH=/usr/lib/go-1.10/bin:"$PATH" make install install.runc
    command -v buildah && buildah --version
    command -v runc && runc --version
    cat <<'EOF' | sudo tee /etc/containers/registries.conf
[registries.search]
  registries = ['docker.io']
EOF
    popd
fi

# umoci provides a binary build; no appropriate Ubuntu package for Xenial.
if [[ -z $MINIMAL_DEPS ]]; then
    wget -nv https://github.com/openSUSE/umoci/releases/download/v0.4.4/umoci.amd64
    sudo chmod 755 umoci.amd64
    sudo mv umoci.amd64 /usr/local/bin/umoci
    umoci --version
fi

# Documentation.
if [[ -z $MINIMAL_DEPS ]]; then
    sudo pip3 install sphinx sphinx-rtd-theme
fi

set +ex
