#!/bin/bash

printf "ID, Size, Runtime G1, Runtime G2\n" > out.csv




for j in {1..3}
do
for i in {1..10}
do
   
   printf "$i," >> out.csv
   Size=wc -c $HOME/chorkshop/hello.sqfs | awk '{print $1}'
   printf "$Size," >> out.csv
   truncate -s + 10000000 $HOME/chorkshop/hello.sqfs 

   G1=time ch-mount $HOME/chorkshop/hello.sqfs /var/tmp && ch-run /var/tmp/hello -- ./hello.py && fusermount -u /var/tmp/hello
   G2=time ch-run $HOME/chorkshop/hello.sqfs -- ./hello.py
   printf "$G1,$G2\n" >> out.csv
done
done
