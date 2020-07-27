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
EX=ex02
TRIALS=1000

########## PROCESSING ##########################################


if [ $# -eq 0 ]; then
    echo "No arguments specified, moving forward with defauls.
            Identifier is ex02, Trials is 1000, sqfs = ~/chorkshop/hello.sqfs"
elif [ $# -ne 3 ]; then 
    echo "USAGE: ./ex02.sh <Identifier> <trial count> <sqfs>"
    echo "example: ./ex02.sh ex02 1000 ~/chorkshop/hello.sqfs"
    exit 1
else 
    EX=$1
    TRIALS=$2
    SQFS=$3
    echo "defaults have been updated: Identifier is now "$EX", trials is now "$TRIALS",
    sqfs is now "$SQFS""
fi

################################################################
# Full workflow(ex02-E2E.csv)                                  #
################################################################


#create schema
printf "ID, S_SFSH, E_SFSH, S_SFSL, E_SFSL,S_PSFSH, E_PSFSH\n" > "$EX"-E2E.csv

#1000 trials
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

    printf "$i, $S_SFSH,$E_SFSH,$S_SFSL,$E_SFSH,$S_PSFSH,$E_PSFSH\n" >> "$EX"-E2E.csv

done


###################################################################
# Broken Workflow (ex02.csv)                                      #
###################################################################


printf "ID, S_SFSH, E_SFSH, S_SFSL, E_SFSL,S_PSFSH, E_PSFSH\n" > "$EX"-MT.csv
printf "ID, S_SFSH, E_SFSH, S_SFSL, E_SFSL,S_PSFSH, E_PSFSH\n" > "$EX"-UT.csv
printf "ID, S_SFSH, E_SFSH, S_SFSL, E_SFSL,S_PSFSH, E_PSFSH, S_TB, E_TB\n" > "$EX"-RT.csv


mkdir /var/tmp/bois/
$CHTAR2DIR $TAR /var/tmp/bois/

for i in $(seq "$TRIALS")
do

    #Suggested SquashFS Low Level Workflow
    S_SFSL_MT=$(date '+%s.%N')
    $CHMOUNTLL $SQFS /var/tmp
    E_SFSL_MT=$(date '+%s.%N')

    S_SFSL_RT=$(date '+%s.%N')
    $CHRUN /var/tmp/hello -- $PROG
    E_SFSL_RT=$(date '+%s.%N')

    S_SFSL_UT=$(date '+%s.%N')
    $CHUMOUNT /var/tmp/hello
    E_SFSL_UT=$(date '+%s.%N')


    #Suggested SquashfS High Level Workflow
    S_SFSH_MT=$(date '+%s.%N')
    $CHMOUNTHL $SQFS /var/tmp
    E_SFSH_MT=$(date '+%s.%N')

    S_SFSH_RT=$(date '+%s.%N')
    $CHRUN /var/tmp/hello -- $PROG
    E_SFSH_RT=$(date '+%s.%N')

    S_SFSH_UT=$(date '+%s.%N')
    $CHUMOUNT /var/tmp/hello
    E_SFSH_UT=$(date '+%s.%N')

    #Proposed SquashFS High Level Workflow
    rm out.txt
    adddate() {
        while IFS= read -r line; do
            printf '%s %s\n' "$(date '+%s.%N')" "$line" >> out.txt;
        done
    }
    S_PSFSH_MT=$(date '+%s.%N')
    $CHRUN $SQFS -- $PROG |& adddate 
    E_PSFSH_MT=$(cat out.txt | grep -w "mount" | awk '{printf $1}')
    S_PSFSH_RT=$E_PSFSH_MT
    E_PSFSH_RT=$(cat out.txt | grep -F "run" | awk '{printf $1}')
    S_PSFSH_UT=$E_PSFSH_UT
    E_PSFSH_UT=$(cat out.txt | grep -m2 "unmount" | tail -n1 |  awk '{printf $1}')


    #Tar Ball Workflow (Just Runtime)
    S_TB_RT=$(date '+%s.%N')    
    $CHRUN /var/tmp/bois/hello -- $PROG
    E_TB_RT=$(date '+%s.%N')

    printf "$i, $S_SFSH_MT, $E_SFSH_MT, $S_SFSL_MT, $E_SFSL_MT,$S_PSFSH_MT, $E_PSFSH_MT\n" >> "$EX"-MT.csv
    printf "$i, $S_SFSH_UT, $E_SFSH_UT, $S_SFSL_UT, $E_SFSL_UT,$S_PSFSH_UT, $E_PSFSH_UT\n" >> "$EX"-UT.csv
    printf "$i, $S_SFSH_RT, $E_SFSH_RT, $S_SFSL_RT, $E_SFSL_RT,$S_PSFSH_RT, $E_PSFSH_RT, $S_TB_RT, $E_TB_RT\n" >> "$EX"-RT.csv

done 

rm -rf --one-file-system /var/tmp/bois/hello
rm out.txt

