#!/bin/bash

# Do all the Charliecloud setup stuff and then run the job, if
# any. See README.md for details.
#
# Alternatives considered and rejected:
#
# 1. Script in /etc/init.d: More or less the same as rc.local here,
#    but requires messing with runlevels and whatnot.
#
# 2. @reboot entry in crontab: Naturally runs the job as unprivileged
#    user, but does not cover privileged setup stuff.

cd $(dirname $0)
. ./util.sh

export PYTHONUNBUFFERED=8675309

t_start_all=$(date +"%s")
log "starting Charliecloud boot.sh"

for script in [0123456789][0123456789]-*; do
    log "running $script"
    t_start=$(date +"%s")
    ./$script
    t_end=$(date +"%s")
    log "$script done in $(($t_end - $t_start)) seconds"
done

t_end_all=$(date +"%s")
log "boot.sh done in $(($t_end_all - $t_start_all)) seconds"
