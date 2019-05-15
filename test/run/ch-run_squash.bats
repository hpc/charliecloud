load ../common

@test 'ch-run: run squashfs image' {
    # Also tests mounting, and unmounting a squashfs
    scope standard
    need_squashfs

    image_ok "$ch_timg"
    if [[ ! -e /tmp/"$(basename "$ch_timg")".sqfs ]]; then 
        ch-dir2squash "$ch_timg" "/tmp"
    fi
    ch-mount /tmp/"$(basename "$ch_timg")".sqfs /tmp/squash
    [[ -e /tmp/squash/chtest/WEIRD_AL_YANKOVIC ]]
    run ch-run /tmp/squash/chtest -- /bin/true
    [[ $status -eq 0 ]]
    ch-umount /tmp/squash/chtest
    [[ ! -e /tmp/squash/chtest/WEIRD_AL_YANKOVIC ]]
}
