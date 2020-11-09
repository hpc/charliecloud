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
if [[ -z $MINIMAL_DEPS ]]; then
    sudo apt-get install pigz pv
else
    PACK_FMT=tar
    if [[ $CH_BUILDER != ch-image ]]; then
        # Remove ch-image dependency "requests" (issue #806).
        sudo dpkg --remove \
                  apport \
                  cloud-init \
                  gce-compute-image-packages \
                  python3-apport \
                  python3-requests \
                  python3-requests-unixsocket \
                  ssh-import-id \
                  ubuntu-server
    fi
fi
if [[ $CH_BUILDER = ch-image ]]; then
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

# Install Buildah; adapted from upstream instructions [1]. I believe this
# tracks upstream current version fairly well. (I tried to use
# add-app-repository but couldn't get it to work.)
#
# [1]: https://github.com/containers/buildah/blob/master/install.md
if [[ $CH_BUILDER = buildah* ]]; then
    echo 'deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_18.04/ /' | sudo tee /etc/apt/sources.list.d/buildah.list
    wget -nv -O /tmp/Release.key https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/xUbuntu_18.04/Release.key
    sudo apt-key add /tmp/Release.key
    sudo apt-get update
    sudo apt-get -y install buildah
    command -v buildah && buildah --version
    sudo ln -s /usr/sbin/runc /usr/bin/runc
    command -v runc && runc --version
    # As of 2020-04-21, stock registries.conf is pretty simple; it includes
    # Docker Hub (docker.io) and then quay.io. Still, use ours for stability.
    cat /etc/containers/registries.conf
    cat <<'EOF' | sudo tee /etc/containers/registries.conf
[registries.search]
  registries = ['docker.io']
EOF
fi

# Documentation.
if [[ -z $MINIMAL_DEPS ]]; then
    sudo pip3 install sphinx sphinx-rtd-theme
fi

set +ex
