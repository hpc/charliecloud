#!/bin/bash


#create schema
#printf "ID, E2E-TG1, E2E-TG2A, E2E-TG2B, E2E-TG3\n" > ex02-E2E.csv




#TEST THE END TO END WORKFLOW FOR ALL TEST GROUPS AND PIPE TO ex02-E2E.csv
#1000 trials
for i in {1..0}
do

#Unpacked Tar Ball Workflow: end to end test group 1
E2ETG1=$((time sh -c 'ch-run ~/hello -- ./hello.py') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')



#Ch-Mount High Level Workflow: end to end test group 2
E2ETG2A=$((time sh -c '~/charliecloud/bin/ch-mounthl ~/chorkshop/hello.sqfs /var/tmp && ch-run /var/tmp/hello -- ./hello.py && ch-umount /var/tmp/hello') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')


#Ch-mount low level workflow: end to end test group 2
E2ETG2B=$((time sh -c '~/charliecloud/bin/ch-mount ~/chorkshop/hello.sqfs /var/tmp && ch-run /var/tmp/hello -- ./hello.py && ch-umount /var/tmp/hello') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')


#New automount workflow: end to end test group 3
E2ETG3=$((time sh -c '~/charliecloud/bin/ch-run ~/chorkshop/hello.sqfs -- ./hello.py') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')



#printf "$i, $E2ETG1, $E2ETG2A, $E2ETG2B, $E2ETG3\n" >> ex02-E2E.csv

done





printf "ID, MT-TG2A, MT-TG2B, MT-TG3, UT-TG2A, UT-TG2B,  UT-TG3, RT-TG2A, RT-TG2B, RT-TG3\n" > ex02.csv

#TEST BROKEN UP WORKFLOW FOR ALL TEST GROUPS AND PIPE TO EX02.CSV
for i in {1..1000}
do

printf "$i," >> ex02.csv
MTTG2B=$((time sh -c '~/charliecloud/bin/ch-mount ~/chorkshop/hello.sqfs /var/tmp') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')


RTTG2B=$((time sh -c 'ch-run /var/tmp/hello -- ./hello.py') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')



UTTG2B=$((time sh -c 'ch-umount /var/tmp/hello') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')

MTTG2A=$((time sh -c '~/charliecloud/bin/ch-mounthl ~/chorkshop/hello.sqfs /var/tmp') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')


RTTG2A=$((time sh -c 'ch-run /var/tmp/hello -- ./hello.py') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')



UTTG2A=$((time sh -c 'ch-umount /var/tmp/hello') 2>&1 | grep -F real | awk '{print $2}' | grep -Eo '[+]?([.][0-9]+)?')






out=$(sh -c '~/charliecloud/bin/ch-run ~/chorkshop/hello.sqfs -- ./hello.py')
MTTG3=$((echo $out) | awk '{print $4}')
RTTG3=$((echo $out) | awk '{print $6}')
UTTG3=$((echo $out) | awk '{print $8}')

printf "$MTTG2A,$MTTG2B, $MTTG3, $UTTG2A, $UTTG2B, $UTTG3, $RTTG2A,$RTTG2B,$RTTG3\n" >> ex02.csv
done 











