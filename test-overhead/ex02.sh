#!/bin/bash


#create schema
printf "ID, E2E-TG1, E2E-TG2, E2E-TG3\n" > ex02-E2E.csv


UnpackedTar="$HOME/hello"
Squash=$HOME/chorkshop/hello.sqfs



#repeat 1000 times
for i in {1..1000}
do

#Write ID
printf "$i," >> ex02-E2E.csv

#Time E2E for each Test Group
E2ETG1=$((time sh -c 'ch-run ~/hello -- ./hello.py') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')


E2ETG2=time sh -c 'ch-mount ~/chorkshop/hello.sqfs /var/tmp && ch-run /var/tmp/hello -- ./hello.py && ch-umount /var/tmp/hello'


E2ETG2=$((time sh -c 'ch-mount ~/chorkshop/hello.sqfs /var/tmp && ch-run /var/tmp/hello -- ./hello.py && ch-umount /var/tmp/hello') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')



E2ETG3=$((time sh -c '~/charliecloud/bin/ch-run ~/chorkshop/hello.sqfs -- ./hello.py') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')



printf "$E2ETG1, $E2ETG2, $E2ETG3\n" >> ex02-E2E.csv

done





printf "ID, MT-TG2, MT-TG3, UT-TG2, UT-TG3, RT-TG2, RT-TG3\n" > ex02.csv

for i in {1..1}
do

printf "$i," >> ex02.csv
#Test group 3
MTTG3=$((time sh -c 'ch-mount ~/chorkshop/hello.sqfs /var/tmp') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')


RTTG3=$((time sh -c 'ch-run /var/tmp/hello -- ./hello.py') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')



UTTG3=$((time sh -c 'ch-umount /var/tmp/hello') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')



#Test group 2


printf "$MTTG2, $MTTG3, $UTTG2, $UTTG3, $RTTG2,$RTTG3\n" >> ex02.csv
done 











