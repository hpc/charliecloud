load ../common

@test 'ch-dir2squash: squash image' {
    scope standard
    need_squashfs

    image_ok "$ch_timg"
    #if squash exists remove
    if [ -e /tmp/"$(basename "$ch_timg")".sqfs ]; then 
        rm -rf /tmp/"$(basename "$ch_timg")".sqfs
    fi
    ch-dir2squash "$ch_timg" "/tmp"
    [[ -e /tmp/$(basename "$ch_timg").sqfs ]]
    rm -rf /tmp/"$(basename "$ch_timg")".sqfs
}

@test 'ch-tar2squash: convert image' {
    scope standard
    need_squashfs

    [[ -e "$ch_ttar" ]]
    ch-tar2squash "$ch_ttar" "/tmp"
    [[ -e /tmp/"$(basename "$ch_timg")".sqfs ]]
}

@test 'ch-run: run squashfs image' {
    # Also tests mounting, and unmounting a squashfs
    scope standard
    need_squashfs

    image_ok "$ch_timg"
    if [ ! -e /tmp/"$(basename "$ch_timg")".sqfs ]; then 
        ch-dir2squash "$ch_timg" "/tmp"
    fi
    ch-mount /tmp/"$(basename "$ch_timg")".sqfs /tmp/squash
    [[ -e /tmp/squash/chtest/WEIRD_AL_YANKOVIC ]]
    run ch-run /tmp/squash/chtest -- /bin/true
    [[ $status -eq 0 ]]
    ch-umount /tmp/squash/chtest
    [[ ! -e /tmp/squash/chtest/WEIRD_AL_YANKOVIC ]]
}