set -e

function log () {
    echo $(date +"%Y-%m-%dT%H:%M:%S")':' "$@"
}

function chsync () {
    # synchronize with other guests
    # arg 1: sync identifier
    # arg 2: only wait if this guest ID (optional)

    tag=$1
    wait_id=$2
    file=$CH_GUEST_ID.$tag
    wait=1

    log "writing $file"
    touch $CH_META/sync/$file

    if [[ -z $wait_id || $CH_GUEST_ID == $wait_id ]]; then
        log "synchronizing with other guests: $tag"
        for (( i=0; i<$CH_GUEST_CT; i++ )); do
            ofile=$i.$tag
            while true; do
                if [ -f $CH_META/sync/$ofile ]; then
                    log "found $ofile"
                    break
                else
                    log "$ofile not found, waiting $wait seconds"
                    sleep $wait
                fi
            done
        done
    fi
}
