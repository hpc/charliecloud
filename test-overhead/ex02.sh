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

#################################################################
# End to End Workflow just for giggles (giggles.csv)            #
#################################################################


printf "ID, E2E-TB, E2E-SFSH, E2E-SFSL, E2E-PSFSH\n" > giggles.csv

for i in {1..30}
do
    start=`date '+%s.%N'`
    #Suggested SquashfS High Level Workflow
    $CHMOUNTHL $SQFS /var/tmp && $CHRUN /var/tmp/hello -- $PROG && $CHUMOUNT /var/tmp/hello

    end1=`date '+%s.%N'`

    #Suggested SquashFS Low Level Workflow
    $CHMOUNTLL $SQFS /var/tmp && $CHRUN /var/tmp/hello -- $PROG && $CHUMOUNT /var/tmp/hello
    end2=`date '+%s.%N'`

    #Proposed SquashFS High Level Workflow
    $CHRUN $SQFS -- $PROG
    end3=`date '+%s.%N'`

    #Tar Ball
    $CHTAR2DIR $TAR /tmp && $CHRUN /tmp/hello -- $PROG
    end4=`date '+%s.%N'`

    rm -rf /tmp/hello

    E2ESFSH=$(echo "$end1" - "$start" | bc -l)

    E2ESFSL=$(echo "$end2" - "$end1" | bc -l)

    E2EPSFSH=$(echo "$end3" - "$end2" | bc -l)

    E2ETB=$(echo "$end4" - "$end3" | bc -l)

    printf "$i, $E2ETB, $E2ESFSH, $E2ESFSL, $E2EPSFSH\n" >> giggles.csv


done





################################################################
# Full workflow(ex02-E2E.csv)                                  #
################################################################


#create schema
printf "ID, E2E-SFSH, E2E-SFSL, E2E-PSFSH\n" > ex02-E2E.csv

#1000 trials
for i in {1..1000}
do
    start=`date '+%s.%N'`
    #Suggested SquashfS High Level Workflow
    $CHMOUNTHL $SQFS /var/tmp && $CHRUN /var/tmp/hello -- $PROG && $CHUMOUNT /var/tmp/hello

    end1=`date '+%s.%N'`

    #Suggested SquashFS Low Level Workflow
    $CHMOUNTLL $SQFS /var/tmp && $CHRUN /var/tmp/hello -- $PROG && $CHUMOUNT /var/tmp/hello
    end2=`date '+%s.%N'`

    #Proposed SquashFS High Level Workflow
    $CHRUN $SQFS -- $PROG
    end3=`date '+%s.%N'`

    E2ESFSH=$(echo "$end1" - "$start" | bc -l)

    E2ESFSL=$(echo "$end2" - "$end1" | bc -l)

    E2EPSFSH=$(echo "$end3" - "$end2" | bc -l)

    printf "$i, $E2ESFSH, $E2ESFSL, $E2EPSFSH\n" >> ex02-E2E.csv

done


###################################################################
# Broken Workflow (ex02.csv)                                      #
###################################################################



printf "ID, MT-SFSH, MT-SFSL, MT-PSFSH, UT-SFSH, UT-SFSL,  UT-PSFSH, RT-SFSH, RT-SFSL, RT-PSFSH, RT-TB\n" > ex02.csv

$CHTAR2DIR $TAR /tmp/

for i in {1..1000}
do

    #Suggested SquashFS Low Level Workflow

    start=`date '+%s.%N'`
    $CHMOUNTLL $SQFS /var/tmp
    end1=`date '+%s.%N'`

    $CHRUN /var/tmp/hello -- $PROG
    end2=`date '+%s.%N'`

    $CHUMOUNT /var/tmp/hello
    end3=`date '+%s.%N'`

    MTSFSL=$(echo "$end1" - "$start" | bc -l)

    RTSFSL=$(echo "$end2" - "$end1" | bc -l)

    UTSFSL=$(echo "$end3" - "$end2" | bc -l)


    #Suggested SquashfS High Level Workflow
    
    start=`date '+%s.%N'`
    $CHMOUNTHL $SQFS /var/tmp
    end1=`date '+%s.%N'`

    $CHRUN /var/tmp/hello -- $PROG
    end2=`date '+%s.%N'`

    $CHUMOUNT /var/tmp/hello
    end3=`date '+%s.%N'`

    MTSFSH=$(echo "$end1" - "$start" | bc -l)

    RTSFSH=$(echo "$end2" - "$end1" | bc -l)

    UTSFSH=$(echo "$end3" - "$end2" | bc -l)


    #Proposed SquashFS High Level Workflow

    rm -rf out.txt
    adddate() {
        while IFS= read -r line; do
            printf '%s %s\n' "$(date '+%s.%N')" "$line" >> out.txt;
        done
    }
    start=`date '+%s.%N'`

    $CHRUN $SQFS -- $PROG |& adddate 


    end1=$(cat out.txt | grep -w "mount" | awk '{printf $1}')

    end2=$(cat out.txt | grep -F "run" | awk '{printf $1}')

    end3=$(cat out.txt | grep -m2 "unmount" | tail -n1 |  awk '{printf $1}')


    MTPSFSH=$(echo "$end1" - "$start" | bc -l)

    RTPSFSH=$(echo "$end2" - "$end1" | bc -l)

    UTPSFSH=$(echo "$end3" - "$end2" | bc -l)


    #Tar Ball Workflow (Just Runtime)
    
    starti=`date '+%s.%N'`    
    $CHRUN /tmp/hello -- $PROG
    end4=`date '+%s.%N'`

    RTTB=$(echo "$end4" - "$starti" | bc -l)
    echo $RTTB

    printf "$i,$MTSFSH,$MTSFSL, $MTPSFSH, $UTSFSH, $UTSFSL, $UTPSFSH, $RTSFSL,$RTSFSH,$RTPSFSH,$RTTB\n" >> ex02.csv
done 

rm -rf /tmp/hello









