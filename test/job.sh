#!/bin/bash

# This script evaluates the configuration and state of the virtual cluster. We
# test if everything is in order with the guest and host by comparing its
# output to reference output. To facilitate variable output, there is a
# comment facility; anything on a line matching '\s+//.*$' is removed before
# comparison.

exec 2>&1

export LC_ALL=C  # for consistent sorting, etc.
export PATH=$PATH:/sbin

function sec () {
    echo
    echo "$@"
}


sec '#### Test initialization ####'

sec '* distribution ID'
if [ -f /etc/debian_version ]; then
    echo 'ok  // Debian or derivative'
    DEBIAN=yes
elif [ -f /etc/redhat-release ]; then
    echo 'ok  // Red Hat or derivative'
    REDHAT=yes
else
    echo 'error: unknown distribution, aborting'
    exit 1
fi

sec '* Charliecloud environment variables used in this script'
if [ -d "$CH_DATA1" -a -n "$CH_GUEST_ID" ]; then
    mkdir -p $CH_DATA1/$CH_GUEST_ID
    OUTDIR=$CH_DATA1/$CH_GUEST_ID
    echo ok
else
    echo 'missing Charliecloud environment variables, aborting'
    exit 1
fi

sec '* needed binaries'
for i in ip lsb_release route; do
    echo -n "$i: "
    type -t $i || echo 'not found'
done

sec '* sudo without password'
if ( ! sudo -n echo 'ok' ); then
    echo 'sudo failed, aborting'
    exit 1
fi


sec '#### Installation ####'

sec '* root filesystem label'
sudo dumpe2fs /dev/vda1 2>&1 | fgrep 'Filesystem volume name' 2>&1

sec '* user charlie is present'
id -nu charlie


sec '#### Configuration ####'  # see also bootstrap.sh

sec '### Console and friends'

sec '* serial console'
tr '[:space:]' '\n' < /proc/cmdline | fgrep console= | sort

sec '* FANCYTTY off'
if [ "$DEBIAN" ]; then
    fgrep -q 'FANCYTTY=0' /etc/lsb-base-logging.sh && echo ok
elif [ "$REDHAT" ]; then
    echo 'ok  // not tested for Red Hat (issue #37)'
fi

sec '* framebuffer console disabled'
# http://kb.digium.com/articles/FAQ/How-to-disable-the-Linux-frame-buffer-if-it-s-causing-problems
dmesg | fgrep -i 'frame buffer'


sec '### Filesystem'

sec '* Environment variables'
set | fgrep -i proxy | sort > $OUTDIR/vars-proxy.actual
# trim final octets of MAC and IP addresses
set \
  | fgrep -i ch_ \
  | sort > $OUTDIR/vars-charlie.actual

sec '* /ch and subdirectories'
ls -1F /ch

sec '* /etc/fstab and filesystems mounted under /ch'
egrep '(^LABEL=)|(/ch)' /etc/fstab | sort
mount | fgrep /ch | sort


sec '### Network'

sec '* persistent network device names'
ls -1 /etc/udev/rules.d/*-persistent-net*.rules
cat /etc/udev/rules.d/75-persistent-net-generator.rules

sec '* interface configuration'
echo 'not tested: we test functionality instead'

sec '* symlinks to files in /ch/meta'
readlink -e /etc/hosts
readlink -e /etc/resolv.conf


sec '### Users and groups'

sec '* umask'
umask

#sec '* /sbin and /usr/sbin in $PATH'
#echo $PATH | tr : '\n' | egrep '^/sbin$'
#echo $PATH | tr : '\n' | egrep '^/usr/sbin$'

sec '* serial port permissions'
ls -l /dev/ttyS[012] | sed -r -e 's/[T-] /Z /' \
                              -e 's/[A-Za-z0-9 :]{12} \//[timestamp] \//'
id charlie | fgrep -q '(dialout)' && echo 'charlie is in dialout group'

sec '## Passwords & authentication'

sec '* SSH configuration'
for i in PubkeyAuthentication PasswordAuthentication PermitRootLogin; do
    egrep "^$i " /etc/ssh/sshd_config
done

sec '* /etc/sudoers'
# sudo itself tested above
sudo bash -c set | fgrep -i proxy | sort > $OUTDIR/vars-proxy-sudo.actual

sec '* charlie empty password'
sudo egrep '^charlie:' /etc/shadow | cut -d: -f1-2

sec '## SSH keys'

sec '* ~/.ssh contents'
ls -1 ~/.ssh/{authorized_keys,config,id_*}

sec '* authorized_keys'
cat ~/.ssh/authorized_keys \
  | fgrep charlie@ \
  | sed -r 's/(ssh-)(dsa|rsa) [A-Za-z0-9+/=]+ charlie@([a-z0-9]+)$/\1[xsa] [key] charlie@[host]/'

sec '* config'
egrep -v '^#' ~/.ssh/config


sec '### Miscellaneous'

sec '* MPI hostfile configuration'
egrep '^orte_default_hostfile' /etc/openmpi/openmpi-mca-params.conf


sec '#### Runtime tests ####'

sec '### Filesystems'
# fstab and mounts checked above

sec '## /ch directories'

sec '* /ch/meta'
# This is not comprehensive. It just checks if a few key files are present.
ls -1 /ch/meta/{guest-macs,hostfile,hosts,resolv.conf}

sec '* /ch/opt'
ls -1 /ch/opt/$(lsb_release --short --codename)

sec '* /ch/tmp is writeable'
echo 'hello world' > /ch/tmp/test
sync
ls -1 /ch/tmp

sec '* /ch/data[1234]'
echo 'no additional tests'

sec '* swap space present'
cat /proc/swaps


sec '### Networking'

mac=$(ip addr show eth0 | sed -rn s'/^.* link\/ether ([0-9a-z:]+).*$/\1/p')
ip=$(ip addr show eth0 | sed -rn s'/^.* inet ([0-9.]+).*$/\1/p')
mask=$(ip addr show eth0 | sed -rn s'/^.* inet [0-9.]+(\/[0-9.]+).*$/\1/p')
bcast=$(ip addr show eth0 | sed -rn s'/^.* brd ([0-9.]+).*$/\1/p')

sec '* hostname'
hostname > $OUTDIR/hostname.actual

sec '* MAC and IP space'
echo $mac | sed -r 's/(:[0-9a-z]+){2}$/:xx:xx/'
echo $ip | sed -r 's/(\.[0-9]{1,3}){2}$/.xxx.xxx/'
echo $mask
echo $bcast | sed -r 's/(\.[0-9]{1,3}){2}$/.xxx.xxx/'

sec '* MAC and IP match'
diff -u <(echo $mac) <(echo -n 0c:00; printf ':%02x' ${ip//./ }; echo)

sec '* MAC matches /ch/meta/guest-macs'
diff -ui <(echo $mac) <(sed -nr "s/^$CH_GUEST_ID (.+)$/\1/p" /ch/meta/guest-macs)

sec '* routing table'
ip route > $OUTDIR/route.actual

sec '* /etc/hosts link'
readlink /etc/hosts

sec '* /etc/resolv.conf link'
readlink /etc/resolv.conf

sec '* can we reach the internet?'
# Note that this is a little bit of an odd duck, because there is currently no
# way to tell whether the network *should* be reachable. Therefore, we're
# going to just print the results later and let the user interpret them.
#
# We try www.google.com by name and IP so that we know whether DNS is getting
# in the way.
WGET="wget -nv --tries=1 --no-cookies --timeout=5 -O /dev/null"
$WGET http://216.58.216.228 2> $OUTDIR/wget.net
$WGET http://www.google.com 2>> $OUTDIR/wget.net
unset WGET

sec '* ssh other nodes'
for i in $(cat /ch/meta/guests); do
    ssh $i hostname
done

sec '* simple MPI job'
mpirun hostname | sort

sec '* listening ports'
sudo netstat -tulp | sed -r 's/[0-9]+\//[pid]\//'

sec '### Users and groups'

sec '* are we charlie?'
whoami

sec '* charlie users and groups'
id charlie \
  | sed -r 's/groups=//' \
  | tr ' ,' '\n' \
  | egrep '^[a-z]|[0-9]{4,}|[5-9][0-9]{2}' \
  | sort \
  > $OUTDIR/id-charlie.actual

sec '### Miscellaneous'

sec '* running virtualized?'
dmesg | fgrep 'QEMU Standard PC'

sec '* job stderr'
echo 'hello stderr' > /dev/ttyS2

sec '* virtio drivers in use?'
lspci | fgrep -i virtio | sed -r 's/^[0-9a-f.:]+ /[pciaddr] /' | sort

sec '* running processes not whitelisted'
ps axo args= \
  | egrep -v '^(\[|-?bash|cut|e?grep|init|less|orted|ps|sshd:?|sort|su|tee|udevd)' \
  | egrep -v '^(\(sd-pam)\)' \
  | egrep -v '^(/s?bin/(agetty|bash|getty|init|login|sh))' \
  | egrep -v '^(/usr/s?bin/(acpid|atd|cron|dbus-daemon|irqbalance|r?syslogd|sshd))' \
  | egrep -v '^(/lib/systemd/systemd(-(journald|logind|udevd))?)' \
  | cut -d' ' -f1 \
  | sort -u
