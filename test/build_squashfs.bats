load common

@test 'ch-tar2squash: convert image' {
    scope standard
    need_squashfs

    [[ -e "$ch_ttar" ]]
    ch-tar2squash "$ch_ttar" "/tmp"
    [[ -e /tmp/"$(basename "$ch_timg")".sqfs ]]
}

@test 'ch-dir2squash: squash image' {
    scope standard
    need_squashfs

    [[ -e "$ch_ttar" ]]
    mkdir -p "$ch_imgdir"
    ch-tar2dir "$ch_ttar" "$ch_imgdir"
    image_ok "$ch_timg"
    #if squash exists remove
    if [[ -e /tmp/"$(basename "$ch_timg")".sqfs ]]; then 
        rm -rf /tmp/"$(basename "$ch_timg")".sqfs
    fi
    ch-dir2squash "$ch_timg" "/tmp"
    [[ -e /tmp/$(basename "$ch_timg").sqfs ]]
    rm -rf /tmp/"$(basename "$ch_timg")".sqfs "$ch_timg" "$CH_IMG_DIR"
}
