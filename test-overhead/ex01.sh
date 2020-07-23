#!/bin/bash

printf "ID, Size, E2E-TG2A, E2E-TG2B, E2E-TG3\n" > ex01-E2E.csv



while IFS=, read -r bytes file

do

#echo "I got:$bytes|$file"
#100 trials per file size
for i in {1..5}
do

printf "$i, $bytes," >> ex01-E2E.csv


#Ch-Mount High Level Workflow: end to end test group 2
E2ETG2A=$((time sh -c '~/charliecloud/bin/ch-mounthl ~/chorkshop/"$file" /var/tmp && ch-run /var/tmp/hello -- ./hello.py && ch-umount /var/tmp/hello') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')


#Ch-mount low level workflow: end to end test group 2
E2ETG2B=$((time sh -c '~/charliecloud/bin/ch-mount ~/chorkshop/"$file" /var/tmp && ch-run /var/tmp/hello -- ./hello.py && ch-umount /var/tmp/hello') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')


#New automount workflow: end to end test group 3
E2ETG3=$((time sh -c '~/charliecloud/bin/ch-run ~/chorkshop/"$file" -- ./hello.py') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')



#printf "$E2ETG2A, $E2ETG2B, $E2ETG3\n" >> ex02-E2E.csv

done


done < ex01-files.csv

