#!/bin/bash

# FIXME: Give up after a certain number of iterations.

set -e

# Remove all containers.
buildah rm --all
#while true; do
    #cmd='sudo docker ps -aq'
    #cs_ct=$($cmd | wc -l)
    #echo "found $cs_ct containers"
    # [[ 0 -eq $cs_ct ]] && break
    # shellcheck disable=SC2046
    #$sudo docker rm $($cmd)
#done

# Untag all images. This fails with:
#
#   Error response from daemon: invalid reference format
#
# sometimes. I don't know why.
# Can't currently figure out how to untag images in buildah
#if [[ $1 != --all ]]; then
#    while true; do
#        #cmd='sudo docker images --filter dangling=false --format {{.Repository}}:{{.Tag}}'
#        tag_ct=$($cmd | wc -l)
#        echo "found $tag_ct tagged images"
#        [[ 0 -eq $tag_ct ]] && break
#        # shellcheck disable=SC2046
#        #sudo docker rmi -f --no-prune $($cmd)
#    done
#fi

# If --all specified, remove all images.
if [[ $1 = --all ]]; then
    buildah rm --all --force
    #while true; do
        #cmd='sudo docker images -q'
        #img_ct=$($cmd | wc -l)
        #echo "found $img_ct images"
        #[[ 0 -eq $img_ct ]] && break
        # shellcheck disable=SC2046
        #sudo docker rmi -f $($cmd)
        buildah rm --all --force
    #done
fi
