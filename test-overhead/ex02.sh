#!/bin/bash


#create schema
printf "ID, E2E-TG1, E2E-TG2, E2E-TG3\n" > ex02-E2E.csv


UnpackedTar=$HOME/hello
Squash=$HOME/chorkshop/hello.sqfs



#repeat 1000 times
for i in {1..1000}
do

#Write ID
printf "$i," >> ex02-E2E.csv

#Time E2E for each Test Group

E2ETG1= time sh -c 'ch-run $UnpackedTar -- ./hello.py'

E2ETG2= time sh -c 'ch-mount ~/chorkshop/hello.sqfs /var/tmp && ch-run /var/tmp/hello -- ./hello.py && ch-umount /var/tmp/hello'

E2ETG3= time sh -c '$HOME/charliecloud/bin/ch-run $Squash -- ./hello.py'

printf "$E23TG1, $E2ETG2, $E2ETG3\n" >> ex02-E2E.csv

done



printf "ID, MT-TG2, MT-TG3, UT-TG2, UT-TG3, RT-TG1, RT-TG2, RT-TG3\n" > ex02.csv
#Mount Times





#Unmount Times



#RunTimes













done

