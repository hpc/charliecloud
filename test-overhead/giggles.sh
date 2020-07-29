#!/bin/bash


########## VARIABLES ############################################

CHMOUNTHL=$HOME/charliecloud/bin/ch-mounthl
CHMOUNTLL=$HOME/charliecloud/bin/ch-mount
CHUMOUNT=$HOME/charliecloud/bin/ch-umount
CHRUN=$HOME/charliecloud/bin/ch-run
CHTAR2DIR=$HOME/charliecloud/bin/ch-tar2dir

SQFS=$HOME/chorkshop/hello.sqfs
TAR=$HOME/hello.tar.gz
PROG=/bin/true
TRIALS=30

####### PROCESSING ##############################################

if [! -z "$1"]; then
    TRIALS=$1
    echo ""$1" trials will be performed, data will be output in giggles.csv"
else
    echo "Default Number of Trials is 30, data will be output in giggles.csv"
fi


#################################################################
# End to End Workflow just for giggles (giggles.csv)            #
#################################################################


printf "ID, start-tb, end-tb, start-sfsh, end-sfsh, start-sfsl, end-sfsl, start-psfsh, end-psfsh\n" > giggles.csv

for i in $(seq "$TRIALS")
do
    #Suggested SquashfS High Level Workflow
    S_SFSH=$(date '+%s.%N')
    $CHMOUNTHL $SQFS /var/tmp && $CHRUN /var/tmp/hello -- $PROG && $CHUMOUNT /var/tmp/hello
    E_SFSH=$(date '+%s.%N')

    #Suggested SquashFS Low Level Workflow
    S_SFSL=$(date '+%s.%N')
    $CHMOUNTLL $SQFS /var/tmp && $CHRUN /var/tmp/hello -- $PROG && $CHUMOUNT /var/tmp/hello
    E_SFSL=$(date '+%s.%N')

    #Proposed SquashFS High Level Workflow
    S_PSFSH=$(date '+%s.%N')
    $CHRUN $SQFS -- $PROG
    E_PSFSH=$(date '+%s.%N')

    #Tar Ball
    S_TB=$(date '+%s.%N')
    $CHTAR2DIR $TAR /tmp && $CHRUN /tmp/hello -- $PROG
    E_TB=$(date '+%s.%N')

    rm -rf --one-file-system /tmp/hello


    printf "$i, $S_TB, $E_TB, $S_SFSH, $E_SFSH, $S_SFSL, $E_SFSL, $S_PSFSH,$E_PSFSH\n" >> giggles.csv


done




