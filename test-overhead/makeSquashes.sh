#!/bin/bash


printf "ID, Bytes, Filename\n" > ex01-files.csv


unsquashfs hello.sqfs || { echo 'hello.sqfs must be in this directory'; exit 1; }

for i in {0..0}
do

	var=$((2**"$i"))
	dd if=/dev/urandom of=ugh.txt bs="$var"M count=1  
	mv ugh.txt squashfs-root/
	filename=hello"$var".sqfs
	mksquashfs squashfs-root "$filename"

	

	Bytes=$(ls -l "$filename" | awk '{print $5}')
        printf "$i, $Bytes, $filename\n" >> ex01-files.csv
	


done
rm -rf squashfs-root

