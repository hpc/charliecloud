#!/bin/bash


printf "ID, Bytes, Filename\n" > ex01-files.csv


unsquashfs hello.sqfs 

for i in {0..3}
do

	var=$((2**"$i"))
	dd if=/dev/urandom of=ugh.txt bs="$var"M count=1  
	cp ugh.txt squashfs-root/home/
	cp ugh.txt squashfs-root/lib64/
	cp ugh.txt squashfs-root/dev/
	cp ugh.txt squashfs-root/bin/
	filename=hello"$var".sqfs
	mksquashfs squashfs-root "$filename" -comp xz
	Bytes=$(ls -l "$filename" | awk '{print $5}')
	rp=$(realpath "$filename")
        printf "$i, $Bytes, $rp\n" >> ex01-files.csv
	


done
rm -rf squashfs-root

