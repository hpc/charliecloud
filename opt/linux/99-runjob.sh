#!/bin/bash

. $(dirname $0)/charlie.sh
. $(dirname $0)/util.sh

JOBSCRIPT=/ch/meta/jobscript

if [ ! -x $JOBSCRIPT -o -e /ch/meta/interactive ]; then
    log "$JOBSCRIPT not found/not executable, or interactive mode requested"
else
    log 'forking to run user job'
    (
        # -i gets charlie's environment, which is necessary to make the job
        # script work. This generates an error in the log:
        #
        #   bash: cannot set terminal process group (456): Inappropriate ioctl for device
        #   bash: no job control in this shell
        #
        # but alternatives (-l, $BASH_ENV, sourcing .bashrc explicitly) do not
        # pass tests. The error seems benign, so I have not debugged further.
        sudo -nu charlie -- bash -ic "$JOBSCRIPT 1> /dev/ttyS1 2> /dev/ttyS2" || true
        log "user job complete"
        chsync jobdone 0
        if [[ $CH_GUEST_ID == 0 ]]; then
            log 'shutting down because guest 0'
            shutdown -h now
        else
            log 'staying up because not guest 0'
        fi
    ) >& /dev/console &  # output is lost w/o redirect
fi
