[ -e /run/ch_netinfo.sh ] && . /run/ch_netinfo.sh

export CH_META=/ch/meta
export CH_TMP=/ch/tmp

export CH_GUEST_ID=$(fgrep "$CH_GUEST_MAC" $CH_META/guest-macs | cut -f1 -d' ')
export CH_GUEST_CT=$(wc -l $CH_META/guest-macs | cut -f1 -d' ')

for i in $(seq 4); do
    if (cat /proc/mounts | fgrep -q "/ch/data$i"); then
        export CH_DATA$i="/ch/data$i"
    fi
done
