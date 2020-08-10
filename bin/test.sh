#!/bin/bash

#############################################################################
# quick QA check                                                            #
#############################################################################

NAME=hello2
SQPATH=$HOME/chorkshop/hello2.sqfs
PROG=./hello.py

RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'


checkDirNotExist() {
   if [ -d "$1" ]; then
     printf "${RED} not met\n ${NC}"
   else
     printf "${GREEN} met\n ${NC}"
   fi   
}


checkNoMount() {
   if mount | grep "$1" > /dev/null; then
     printf "${RED} not met\n ${NC}"
   else
     printf "${GREEN} met\n ${NC}"
   fi
}

checkSuccess() {
    if [ $? != 0 ]; then
        printf "${RED} FAIL\n ${NC}"
    else
        printf "${GREEN} SUCCESS\n ${NC}"
    fi
}

echo "CASE 1: automount to /var/tmp"

printf "PRECONDITIONS\n"
printf "mount directory does not exist:"
checkDirNotExist /var/tmp/$NAME
printf "user mount does not exist:"
checkNoMount $NAME


printf "EXECUTE\n"
./ch-run $SQPATH -- $PROG
checkSuccess


printf "POSTCONDITIONS\n"
printf "mount directory does not exist:"
checkDirNotExist /var/tmp/$NAME
printf "user mount does not exist:"
checkNoMount $NAME


echo "---------------------------------------------------------------------------------------"



echo "CASE 2: mount point specified"

printf "PRECONDITIONS\n"
printf "mount directory does not exist:"
checkDirNotExist /var/tmp/$NAME
printf "user mount does not exist:"
checkNoMount $NAME


printf "EXECUTE\n"
./ch-run --squash=/var/tmp/ $SQPATH -- $PROG
checkSuccess

printf "POSTCONDITIONS\n"
printf "mount directory does not exist:"
checkDirNotExist /var/tmp/$NAME
printf "user mount does not exist:"
checkNoMount $NAME


echo "----------------------------------------------------------------------------------------"

echo "CASE 3: original workflow"

printf "EXECUTE\n"
./ch-mount $SQPATH /var/tmp
./ch-run /var/tmp/$NAME -- $PROG
./ch-umount /var/tmp/$NAME
