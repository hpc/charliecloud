#!/bin/bash

# This script is run by ifup (see "man interfaces"). It sets the IP address of
# eth0 (or equivalent) according to Charliecloud rules and saves some
# parameters in a file for later use.

CH_GUEST_MAC=$(ip addr show dev $IFACE |  perl -ne '/(0c:00:[0-9a-f:]+)/ && print uc("$1\n")')

ip1=$((0x$(echo $CH_GUEST_MAC | cut -c7-8)))
ip2=$((0x$(echo $CH_GUEST_MAC | cut -c10-11)))
ip3=$((0x$(echo $CH_GUEST_MAC | cut -c13-14)))
ip4=$((0x$(echo $CH_GUEST_MAC | cut -c16-17)))

CH_GUEST_IP="$ip1.$ip2.$ip3.$ip4"
CH_GATEWAY_IP="$ip1.$ip2.$ip3.254"
CH_BROADCAST="$ip1.$ip2.$ip3.255"

ip addr flush dev $IFACE
ip addr add $CH_GUEST_IP/24 broadcast $CH_BROADCAST dev $IFACE
ip route add default via $CH_GATEWAY_IP dev $IFACE

cat <<EOF > /run/ch_netinfo.sh
export CH_GUEST_MAC=$CH_GUEST_MAC
export CH_GUEST_IP=$CH_GUEST_IP
export CH_GATEWAY_IP=$CH_GATEWAY_IP
EOF
